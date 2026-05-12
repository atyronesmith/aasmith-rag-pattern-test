#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0
WARN=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }
warn() { echo "  WARN: $1"; ((WARN++)); }

wait_for() {
    local desc=$1 cmd=$2 timeout=${3:-120}
    local elapsed=0
    while ! eval "$cmd" &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $timeout ]; then
            fail "$desc (timed out after ${timeout}s)"
            return 1
        fi
    done
    pass "$desc"
}

echo "============================================================"
echo "  Validated Pattern Deployment Validation"
echo "============================================================"
echo ""

# --- Phase 1: Pre-flight ---
echo "--- Phase 1: Pre-flight ---"

if oc whoami &>/dev/null; then
    USER=$(oc whoami)
    pass "Logged in as $USER"
else
    fail "Not logged into cluster"
    echo "Run: oc login -u kubeadmin https://api.crc.testing:6443"
    exit 1
fi

if oc get nodes &>/dev/null; then
    NODE_COUNT=$(oc get nodes --no-headers | wc -l | tr -d ' ')
    pass "Cluster accessible ($NODE_COUNT nodes)"
else
    fail "Cannot reach cluster"
    exit 1
fi

READY=$(oc get nodes --no-headers | grep -c " Ready" || echo 0)
if [ "$READY" -eq "$NODE_COUNT" ]; then
    pass "All nodes Ready"
else
    fail "$READY/$NODE_COUNT nodes Ready"
fi

echo ""

# --- Phase 2: Namespaces ---
echo "--- Phase 2: Namespaces ---"

EXPECTED_NS="rag vault golang-external-secrets openshift-nfd nvidia-gpu-operator redhat-ods-operator openshift-serverless"
for ns in $EXPECTED_NS; do
    if oc get namespace "$ns" &>/dev/null; then
        pass "Namespace $ns exists"
    else
        fail "Namespace $ns missing"
    fi
done

if oc get namespace rag -o jsonpath='{.metadata.labels.opendatahub\.io/dashboard}' 2>/dev/null | grep -q "true"; then
    pass "rag namespace has opendatahub.io/dashboard label"
else
    warn "rag namespace missing opendatahub.io/dashboard label"
fi

echo ""

# --- Phase 3: Operator Subscriptions ---
echo "--- Phase 3: Operator Subscriptions ---"

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
        pass "Subscription $op in $ns"
    else
        fail "Subscription $op missing in $ns"
    fi
done

echo ""
echo "CSV install status (may take several minutes):"
for op in "${!OPERATORS[@]}"; do
    ns="${OPERATORS[$op]}"
    CSV=$(oc get subscription "$op" -n "$ns" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")
    if [ -n "$CSV" ]; then
        PHASE=$(oc get csv "$CSV" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$PHASE" = "Succeeded" ]; then
            pass "CSV $CSV ($PHASE)"
        else
            warn "CSV $CSV ($PHASE) — may still be installing"
        fi
    else
        warn "No CSV yet for $op — operator still installing"
    fi
done

echo ""

# --- Phase 4: ArgoCD ---
echo "--- Phase 4: ArgoCD ---"

ARGOCD_NS="openshift-gitops"
if oc get namespace "$ARGOCD_NS" &>/dev/null; then
    pass "ArgoCD namespace exists"
else
    fail "ArgoCD namespace $ARGOCD_NS missing"
fi

if oc get pods -n "$ARGOCD_NS" --no-headers 2>/dev/null | grep -q "Running"; then
    pass "ArgoCD pods running"
else
    fail "No ArgoCD pods running"
fi

echo ""
echo "ArgoCD applications:"
APPS=$(oc get applications.argoproj.io -n "$ARGOCD_NS" --no-headers 2>/dev/null || echo "")
if [ -n "$APPS" ]; then
    while IFS= read -r line; do
        APP_NAME=$(echo "$line" | awk '{print $1}')
        SYNC=$(echo "$line" | awk '{print $2}')
        HEALTH=$(echo "$line" | awk '{print $3}')
        if [ "$SYNC" = "Synced" ]; then
            pass "App $APP_NAME: $SYNC / $HEALTH"
        elif [ "$SYNC" = "OutOfSync" ]; then
            warn "App $APP_NAME: $SYNC / $HEALTH"
        else
            fail "App $APP_NAME: $SYNC / $HEALTH"
        fi
    done <<< "$APPS"
else
    warn "No ArgoCD applications found yet"
fi

echo ""

# --- Phase 5: Infrastructure ---
echo "--- Phase 5: Infrastructure (Vault + ExternalSecrets) ---"

if oc get pods -n vault --no-headers 2>/dev/null | grep -q "Running"; then
    pass "Vault pods running"
else
    warn "Vault pods not running yet"
fi

if oc get pods -n golang-external-secrets --no-headers 2>/dev/null | grep -q "Running"; then
    pass "External Secrets Operator pods running"
else
    warn "External Secrets Operator pods not running yet"
fi

if oc get crd externalsecrets.external-secrets.io &>/dev/null; then
    pass "ExternalSecret CRD registered"
else
    warn "ExternalSecret CRD not yet registered"
fi

if oc get crd clustersecretstores.external-secrets.io &>/dev/null; then
    pass "ClusterSecretStore CRD registered"
else
    warn "ClusterSecretStore CRD not yet registered"
fi

ES_COUNT=$(oc get externalsecrets -n rag --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$ES_COUNT" -gt 0 ]; then
    pass "$ES_COUNT ExternalSecrets in rag namespace"
    oc get externalsecrets -n rag --no-headers 2>/dev/null | while read -r line; do
        ES_NAME=$(echo "$line" | awk '{print $1}')
        ES_STATUS=$(echo "$line" | awk '{print $2}')
        if echo "$ES_STATUS" | grep -qi "ready\|synced\|SecretSynced"; then
            pass "  ExternalSecret $ES_NAME: $ES_STATUS"
        else
            warn "  ExternalSecret $ES_NAME: $ES_STATUS"
        fi
    done
else
    warn "No ExternalSecrets in rag namespace yet"
fi

echo ""

# --- Phase 6: Application Resources ---
echo "--- Phase 6: Application Resources (rag namespace) ---"

for kind in configmap service route deployment; do
    COUNT=$(oc get "$kind" -n rag --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
        pass "$COUNT ${kind}s in rag namespace"
    else
        warn "No ${kind}s in rag namespace"
    fi
done

PODS=$(oc get pods -n rag --no-headers 2>/dev/null || echo "")
if [ -n "$PODS" ]; then
    TOTAL=$(echo "$PODS" | wc -l | tr -d ' ')
    RUNNING=$(echo "$PODS" | grep -c "Running" || echo 0)
    PENDING=$(echo "$PODS" | grep -c "Pending" || echo 0)
    CRASH=$(echo "$PODS" | grep -c "CrashLoop\|Error\|ImagePull" || echo 0)
    echo "  Pods: $TOTAL total, $RUNNING running, $PENDING pending, $CRASH errored"
    if [ "$CRASH" -gt 0 ]; then
        warn "Some pods in error state (expected without GPU)"
    fi
    if [ "$RUNNING" -gt 0 ]; then
        pass "Some pods running in rag namespace"
    fi
else
    warn "No pods in rag namespace yet"
fi

echo ""

# --- Summary ---
echo "============================================================"
echo "  Summary: $PASS passed, $FAIL failed, $WARN warnings"
echo "============================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
