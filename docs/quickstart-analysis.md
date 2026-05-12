# rag

A Helm chart for Kubernetes

- **Version:** 0.2.44
- **Source:** `/private/var/folders/wj/6vyn2w8x48xgp8rhmwwf4_t00000gn/T/quickpat-sgnsa60a/deploy/helm/rag`

## Architecture

This quickstart provides the following capabilities:

- **LLM Serving** - Model inference endpoint (e.g. vLLM, llama-stack)
- **Vector Database** - Stores document embeddings for similarity search
- **Object Storage** - S3-compatible storage for raw documents and artifacts
- **Data Pipeline** - Automated document ingestion, chunking, and embedding

> **Note:** This quickstart requires GPU resources.

## Helm Dependencies

| Chart | Version | Repository |
|-------|---------|------------|
| pgvector | 0.5.5 | https://rh-ai-quickstart.github.io/ai-architecture-charts |
| llm-service | 0.5.9 | https://rh-ai-quickstart.github.io/ai-architecture-charts |
| configure-pipeline | 0.5.7 | https://rh-ai-quickstart.github.io/ai-architecture-charts |
| ingestion-pipeline | 0.7.4 | https://rh-ai-quickstart.github.io/ai-architecture-charts |
| llama-stack | 0.7.3 | https://rh-ai-quickstart.github.io/ai-architecture-charts |
| mcp-servers | 0.5.15 | https://rh-ai-quickstart.github.io/ai-architecture-charts |

## Required OpenShift Operators

The following operators are automatically installed by the Validated Pattern:

| Operator | Subscription | Channel | Source |
|----------|-------------|---------|--------|
| Node Feature Discovery | nfd | stable | redhat-operators |
| NVIDIA GPU Operator | gpu-operator-certified | v24.9 | certified-operators |
| Red Hat OpenShift AI | rhods-operator | fast | redhat-operators |
| OpenShift Pipelines | openshift-pipelines-operator-rh | latest | redhat-operators |
| OpenShift Serverless | serverless-operator | stable | redhat-operators |
| OpenShift Service Mesh | servicemeshoperator | stable | redhat-operators |

## Secrets Configuration

The following secrets were detected and should be configured before deployment:

| Secret | Values Path | Action |
|--------|-------------|--------|
| `secret` | `rag.llm-service.secret` | Set via Vault or values |
| `hf_token` | `rag.llm-service.secret.hf_token` | Set via Vault or values |
| `secret` | `rag.pgvector.secret` | Set via Vault or values |
| `password` | `rag.pgvector.secret.password` | Set via Vault or values |
| `TAVILY_SEARCH_API_KEY` | `rag.llama-stack.secrets.TAVILY_SEARCH_API_KEY` | Set via Vault or values |
| `secret` | `rag.configure-pipeline.minio.secret` | Set via Vault or values |
| `password` | `rag.configure-pipeline.minio.secret.password` | Set via Vault or values |
| `token` | `rag.ingestion-pipeline.pipelines.hr-pipeline.GITHUB.token` | Set via Vault or values |
| `token` | `rag.ingestion-pipeline.pipelines.legal-pipeline.GITHUB.token` | Set via Vault or values |
| `token` | `rag.ingestion-pipeline.pipelines.sales-pipeline.GITHUB.token` | Set via Vault or values |
| `token` | `rag.ingestion-pipeline.pipelines.procurement-pipeline.GITHUB.token` | Set via Vault or values |
| `token` | `rag.ingestion-pipeline.pipelines.techsupport-pipeline.GITHUB.token` | Set via Vault or values |

## Framework Architecture

This pattern uses the **multisource configuration** approach. Infrastructure Helm charts (clustergroup, vault, external-secrets) are pulled dynamically from the upstream Validated Patterns registry rather than stored locally. This means:

- No fork of multicloud-gitops required
- Upstream bug fixes are received by bumping `clusterGroupChartVersion`
- No `common/` git subtree needed (modern patterns use Ansible collections in the utility container)

The `pattern.sh` script runs all make targets inside a podman-based utility container (`quay.io/validatedpatterns/utility-container`) which includes the `rhvp.cluster_utils` Ansible collection and all required tooling.

> **Note:** The multisource feature is not yet documented on validatedpatterns.io but is used by all current production patterns (multicloud-gitops, rag-llm-gitops) and documented in the [common repo README](https://github.com/validatedpatterns/common).

## Pattern Configuration

- **Pattern name:** rag-pattern
- **Application name:** rag
- **Namespace:** rag
- **Chart strategy:** remote
- **Vault enabled:** True

## Deployment

```bash
git init && git add -A && git commit -m "Initial pattern"
oc login <cluster>
./pattern.sh make install
```
