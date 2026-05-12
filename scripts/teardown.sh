#!/bin/bash
set -euo pipefail

echo "=== Tearing down RAG Validated Pattern ==="
echo ""

if ! oc whoami &>/dev/null; then
    echo "Not logged into cluster. Nothing to tear down."
    exit 0
fi

echo "Deleting ArgoCD applications..."
ARGOCD_NS="openshift-gitops"
for app in rag pattern-secrets vault golang-external-secrets; do
    if oc get application "$app" -n "$ARGOCD_NS" &>/dev/null; then
        oc delete application "$app" -n "$ARGOCD_NS" --wait=false 2>/dev/null || true
        echo "  Deleted application: $app"
    fi
done

echo ""
echo "Waiting for application cleanup (30s)..."
sleep 30

echo "Deleting application namespaces..."
for ns in rag vault golang-external-secrets; do
    if oc get namespace "$ns" &>/dev/null; then
        oc delete namespace "$ns" --wait=false 2>/dev/null || true
        echo "  Deleted namespace: $ns"
    fi
done

echo ""
echo "Deleting operator subscriptions..."
declare -A OPERATORS=(
    ["nfd"]="openshift-nfd"
    ["gpu-operator-certified"]="nvidia-gpu-operator"
    ["rhods-operator"]="redhat-ods-operator"
    ["openshift-pipelines-operator-rh"]="openshift-operators"
    ["serverless-operator"]="openshift-serverless"
    ["servicemeshoperator"]="openshift-operators"
)

for op in "${!OPERATORS[@]}"; do
    ns="${OPERATORS[$op]}"
    if oc get subscription "$op" -n "$ns" &>/dev/null; then
        CSV=$(oc get subscription "$op" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")
        oc delete subscription "$op" -n "$ns" 2>/dev/null || true
        if [ -n "$CSV" ]; then
            oc delete csv "$CSV" -n "$ns" 2>/dev/null || true
        fi
        echo "  Deleted subscription: $op"
    fi
done

echo ""
echo "Deleting operator namespaces..."
for ns in openshift-nfd nvidia-gpu-operator redhat-ods-operator openshift-serverless; do
    if oc get namespace "$ns" &>/dev/null; then
        oc delete namespace "$ns" --wait=false 2>/dev/null || true
        echo "  Deleted namespace: $ns"
    fi
done

echo ""
echo "=== Teardown complete ==="
echo "Note: Some resources may take a few minutes to fully terminate."
echo "Run 'scripts/validate-deployment.sh' to confirm cleanup."
