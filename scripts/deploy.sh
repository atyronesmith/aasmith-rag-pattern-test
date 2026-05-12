#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATTERN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALUES_SECRET_FILE="${VALUES_SECRET:-$HOME/values-secret-rag-pattern.yaml}"
PATTERN_NAME="rag-pattern"
ARGOCD_NS="openshift-gitops"

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

if ! command -v helm &>/dev/null; then
    echo "ERROR: helm not found. Install: brew install helm"
    exit 1
fi

CURRENT_USER=$(oc whoami 2>/dev/null || echo "")
if [ -z "$CURRENT_USER" ] || [ "$CURRENT_USER" != "kubeadmin" ]; then
    echo "  Need kubeadmin access (current: ${CURRENT_USER:-not logged in}). Logging in..."
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
    echo "  Initializing git repo (required by VP framework)..."
    git init
    git add -A
    git commit -m "Initial pattern"
fi

TARGET_BRANCH=$(git rev-parse --abbrev-ref HEAD)
TARGET_REPO=$(git remote get-url origin 2>/dev/null || echo "file://$PATTERN_DIR")
echo "  Branch: $TARGET_BRANCH"
echo "  Repo: $TARGET_REPO"
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

# --- Deploy pattern-install chart ---
echo "--- Deploying pattern (direct helm, bypassing utility container) ---"
echo ""

cd "$PATTERN_DIR"

HELM_OPTS=(
    --include-crds
    --name-template "$PATTERN_NAME"
    -f values-global.yaml
    --set main.git.repoURL="$TARGET_REPO"
    --set main.git.revision="$TARGET_BRANCH"
    --set global.pattern="$PATTERN_NAME"
    --set global.clusterDomain="$(oc get ingress.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo 'apps-crc.testing')"
    --set global.clusterVersion="$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo '4.21')"
    --set global.clusterPlatform="None"
)

echo "Step 1a: Rendering pattern-install chart..."
RENDERED=$(helm template "${HELM_OPTS[@]}" oci://quay.io/validatedpatterns/pattern-install 2>/dev/null)

echo "Step 1b: Applying CRDs and non-Pattern resources..."
echo "$RENDERED" | grep -v '^---$' | awk 'BEGIN{RS="---\n"; ORS="---\n"} !/kind: Pattern/' | oc apply -f- 2>&1

echo "Step 1c: Waiting for Pattern CRD to register..."
for i in $(seq 1 30); do
    if oc get crd patterns.gitops.hybrid-cloud-patterns.io &>/dev/null; then
        echo "  Pattern CRD ready."
        break
    fi
    echo "  Waiting for CRD... ($i/30)"
    sleep 5
done

echo "Step 1d: Applying Pattern CR..."
echo "$RENDERED" | grep -v '^---$' | awk 'BEGIN{RS="---\n"; ORS="---\n"} /kind: Pattern/' | oc apply -f- 2>&1

echo ""
echo "Step 2: Waiting for ArgoCD to be ready..."
for i in $(seq 1 30); do
    if oc get pods -n "$ARGOCD_NS" --no-headers 2>/dev/null | grep -q "Running"; then
        echo "  ArgoCD pods running."
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

echo ""
echo "Step 3: Checking ArgoCD applications..."
sleep 15
oc get applications.argoproj.io -n "$ARGOCD_NS" 2>/dev/null || echo "  No applications yet — may take a few minutes."

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Operators and ArgoCD will take 5-10 minutes to stabilize."
echo "Next steps:"
echo "  1. Watch progress:  oc get applications.argoproj.io -n $ARGOCD_NS -w"
echo "  2. Validate:        ./scripts/validate-deployment.sh"
echo "  3. Teardown:        ./scripts/teardown.sh"
