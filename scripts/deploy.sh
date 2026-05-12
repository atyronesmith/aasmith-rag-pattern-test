#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALUES_SECRET_FILE="${VALUES_SECRET:-$HOME/values-secret-rag-pattern.yaml}"

echo "=== RAG Validated Pattern — CRC Deployment ==="
echo "  Pattern dir: $PATTERN_DIR"
echo "  Secrets file: $VALUES_SECRET_FILE"
echo ""

# --- Pre-flight checks ---
echo "--- Pre-flight checks ---"

if ! command -v oc &>/dev/null; then
    echo "ERROR: oc not found. Run: eval \$(crc oc-env)"
    exit 1
fi

if ! command -v podman &>/dev/null; then
    echo "ERROR: podman not found."
    exit 1
fi

if ! oc whoami &>/dev/null; then
    echo "oc not logged in. Attempting CRC login..."
    eval "$(crc oc-env)"
    KUBEADMIN_PASS=$(crc console --credentials 2>&1 | grep kubeadmin | grep -oE "'[^']+'" | tail -1 | tr -d "'")
    if [ -n "$KUBEADMIN_PASS" ]; then
        oc login -u kubeadmin -p "$KUBEADMIN_PASS" https://api.crc.testing:6443 --insecure-skip-tls-verify=true
    else
        echo "ERROR: Could not extract kubeadmin password."
        echo "Run: crc console --credentials"
        exit 1
    fi
fi

echo "  Logged in as: $(oc whoami)"
echo "  Cluster: $(oc whoami --show-server)"
echo ""

# --- Git repo setup ---
echo "--- Git repo setup ---"

cd "$PATTERN_DIR"

if [ -d .git ]; then
    echo "  Already a git repo."
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo "  Committing uncommitted changes..."
        git add -A
        git commit -m "Pre-deploy snapshot" --allow-empty 2>/dev/null || true
    fi
else
    echo "  Initializing git repo (required by pattern.sh)..."
    git init
    git add -A
    git commit -m "Initial pattern"
fi
echo ""

# --- Secrets file ---
echo "--- Secrets file ---"

if [ -f "$VALUES_SECRET_FILE" ]; then
    echo "  Using existing: $VALUES_SECRET_FILE"
else
    echo "  Creating dummy secrets file for structural testing..."
    cat > "$VALUES_SECRET_FILE" << 'SECRETS_EOF'
version: '2.0'
secrets:
- name: pgvector
  vaultPrefixes:
  - hub
  fields:
  - name: user
    value: 'testuser'
  - name: password
    value: 'testpass'
  - name: host
    value: 'pgvector.rag.svc.cluster.local'
  - name: port
    value: '5432'
  - name: dbname
    value: 'vectordb'
  - name: jdbc-uri
    value: 'jdbc:postgresql://pgvector.rag.svc.cluster.local:5432/vectordb'
  - name: uri
    value: 'postgresql://testuser:testpass@pgvector.rag.svc.cluster.local:5432/vectordb'
- name: llm-service
  vaultPrefixes:
  - hub
  fields:
  - name: HF_TOKEN
    value: 'hf_dummy_token_for_testing'
- name: configure-pipeline
  vaultPrefixes:
  - hub
  fields:
  - name: SOURCE
    value: 'minio'
  - name: EMBEDDING_MODEL
    value: 'nomic-embed-text-v1.5'
  - name: NAME
    value: 'rag-pipeline'
  - name: VERSION
    value: '1.0'
  - name: ACCESS_KEY_ID
    value: 'minioadmin'
  - name: SECRET_ACCESS_KEY
    value: 'minioadmin'
  - name: ENDPOINT_URL
    value: 'http://minio.rag.svc.cluster.local:9000'
  - name: BUCKET_NAME
    value: 'rag-data'
  - name: REGION
    value: 'us-east-1'
  - name: MINIO_ENDPOINT
    value: 'http://minio.rag.svc.cluster.local:9000'
  - name: MINIO_ACCESS_KEY
    value: 'minioadmin'
  - name: MINIO_SECRET_KEY
    value: 'minioadmin'
  - name: LLAMASTACK_BASE_URL
    value: 'http://llama-stack.rag.svc.cluster.local:8321'
  - name: DS_PIPELINE_URL
    value: 'http://ds-pipeline.rag.svc.cluster.local:8888'
- name: llama-stack
  vaultPrefixes:
  - hub
  fields:
  - name: GOOGLE_APPLICATION_CREDENTIALS
    value: '{"type":"service_account","project_id":"dummy"}'
SECRETS_EOF
    echo "  Created: $VALUES_SECRET_FILE"
fi
echo ""

# --- Deploy ---
echo "--- Deploying pattern ---"
echo "  Running: ./pattern.sh make install"
echo ""

export VALUES_SECRET="$VALUES_SECRET_FILE"
cd "$PATTERN_DIR"
./pattern.sh make install

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Operators and ArgoCD will take 5-10 minutes to stabilize."
echo "Run: ./scripts/validate-deployment.sh"
