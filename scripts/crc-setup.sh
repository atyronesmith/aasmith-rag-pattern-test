#!/bin/bash
set -euo pipefail

CRC_MEMORY=${CRC_MEMORY:-32768}
CRC_CPUS=${CRC_CPUS:-8}
CRC_DISK=${CRC_DISK:-100}

echo "=== CRC Setup for VP Structural Validation ==="
echo "  Memory: ${CRC_MEMORY}MB  CPUs: ${CRC_CPUS}  Disk: ${CRC_DISK}GB"
echo ""

if ! command -v crc &>/dev/null; then
    echo "ERROR: crc not found. Install from https://console.redhat.com/openshift/create/local"
    exit 1
fi

echo "CRC version: $(crc version | head -1)"

STATUS=$(crc status 2>/dev/null | grep "CRC VM:" | awk '{print $3}' || echo "Stopped")

if [ "$STATUS" = "Running" ]; then
    echo "CRC is already running."
    echo ""
    echo "Current config:"
    crc config view 2>/dev/null | grep -E "memory|cpus|disk" || true
    echo ""
    echo "To reconfigure, run: crc stop && crc delete && re-run this script"
else
    echo "Configuring CRC..."
    crc config set memory "$CRC_MEMORY"
    crc config set cpus "$CRC_CPUS"
    crc config set disk-size "$CRC_DISK"
    crc config set consent-telemetry no

    echo ""
    echo "Starting CRC (this takes 5-10 minutes on first run)..."
    crc start

    echo ""
    echo "CRC started successfully."
fi

echo ""
echo "=== Cluster Login ==="
eval "$(crc oc-env)"
KUBEADMIN_PASS=$(crc console --credentials 2>/dev/null | grep -oP 'password is \K[^ ]+' || true)

if [ -z "$KUBEADMIN_PASS" ]; then
    KUBEADMIN_PASS=$(crc console --credentials 2>&1 | grep kubeadmin | grep -oE "'[^']+'" | tail -1 | tr -d "'")
fi

if [ -n "$KUBEADMIN_PASS" ]; then
    oc login -u kubeadmin -p "$KUBEADMIN_PASS" https://api.crc.testing:6443 --insecure-skip-tls-verify=true
else
    echo "Could not extract kubeadmin password automatically."
    echo "Run: crc console --credentials"
    echo "Then: oc login -u kubeadmin -p <password> https://api.crc.testing:6443"
    exit 1
fi

echo ""
echo "=== Cluster Health ==="
echo "Nodes:"
oc get nodes
echo ""
echo "Cluster version:"
oc get clusterversion
echo ""
echo "Resources:"
oc adm top nodes 2>/dev/null || echo "(metrics not yet available — wait a few minutes)"
echo ""
echo "=== Ready for pattern deployment ==="
echo "Next steps:"
echo "  1. cd $(dirname "$0")/.."
echo "  2. git init && git add -A && git commit -m 'Initial pattern'"
echo "  3. export VALUES_SECRET=~/values-secret-rag-pattern.yaml"
echo "  4. ./pattern.sh make install"
