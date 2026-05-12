# CRC Structural Validation for RAG Validated Pattern

Validates that the RAG pattern deploys correctly on CRC (CodeReady Containers) — operators install, ArgoCD syncs, ExternalSecrets resolve. No GPU required; this is structural validation only.

## Prerequisites

- CRC installed (`brew install crc` or from console.redhat.com)
- Red Hat pull secret (from https://console.redhat.com/openshift/create/local)
- podman installed (required by pattern.sh)
- ~32GB free RAM

## First-time setup

```bash
# One-time: configure pull secret (interactive)
crc setup

# Start CRC with resources for VP testing
./scripts/crc-setup.sh
```

## Deploy the pattern

```bash
# Pattern needs to be a git repo
git init && git add -A && git commit -m "Initial pattern"

# Create secrets file from template
cp values-secret.yaml.template ~/values-secret-rag-pattern.yaml
# Edit ~/values-secret-rag-pattern.yaml with dummy values (structural test only)

# Deploy
export VALUES_SECRET=~/values-secret-rag-pattern.yaml
./pattern.sh make install
```

## Validate

```bash
# Run after deployment (give it 5-10 min for operators to install)
./scripts/validate-deployment.sh
```

The validation script checks:
1. Cluster connectivity and node health
2. Expected namespaces created (rag, vault, golang-external-secrets, operator namespaces)
3. Operator subscriptions installed and CSVs succeeding
4. ArgoCD applications synced
5. Vault and External Secrets Operator running
6. ExternalSecret CRDs and resources created
7. Application resources (deployments, services, routes, configmaps)

## Teardown

```bash
./scripts/teardown.sh
```

Removes ArgoCD applications, namespaces, operator subscriptions and CSVs.

## Expected results

- Operators should install (CSVs Succeeded), though GPU operator will have no work to do
- ArgoCD should sync all applications
- Vault + ExternalSecrets infrastructure should deploy
- ExternalSecrets will show errors (no real Vault secrets loaded) unless you loaded dummy secrets
- Application pods will be Pending/CrashLoop (no GPU, no model) — that's expected
- The structural win: all Kubernetes resources are accepted by the API server
