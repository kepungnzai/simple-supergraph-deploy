# Production Deployment Guide

## Overview

This repository uses GitHub Actions to automate:
1. **Supergraph Composition** — compiles federation schema using Apollo Rover
2. **Schema Validation** — ensures valid GraphQL composition
3. **Docker Build & Push** — builds multi-stage image and pushes to registry

## GitHub Actions Workflow

The workflow (`.github/workflows/supergraph-deploy.yaml`) has two jobs:

### Job 1: `compose-and-validate`
Runs on every push/PR to verify the supergraph composes correctly:

- Downloads Rover CLI (Linux x86_64)
- Starts the Python subgraph (`app.py`)
- Composes the supergraph schema using `supergraph-config.yaml`
- Validates GraphQL syntax
- Uploads `supergraph-schema.graphql` as build artifact

### Job 2: `build-and-push`
Runs only on `main` branch push after validation:

- Repeats supergraph composition
- Builds multi-stage Docker image (composer → subgraph → router)
- Pushes to container registry
- Tags with `latest` and `${{ github.sha }}`

## Docker Image

The `Dockerfile` uses 3 build stages:

### Stage 1: `composer` (Python 3.11-slim)
- Downloads Rover CLI
- Starts the subgraph on port 4001
- Composes `supergraph-schema.graphql`
- Verifies schema is created

### Stage 2: `subgraph` (Python 3.11-slim)
- Runs the Python GraphQL subgraph
- Exposes port 4001
- Health check on `/graphql` endpoint

### Stage 3: `router` (Ubuntu 22.04)
- Downloads Apollo Router binary
- Copies the composed schema from Stage 1
- Exposes port 4000
- Health check on `/.well-known/apollo/server-health`

## Local Testing

### Test composition locally
```bash
# Install Rover
curl -sSL https://rover.apollo.dev/download/linux/x86_64/latest | tar xz -C ~/.rover/bin rover

# Start subgraph
python -m uvicorn app:app --port 4001 &

# Compose supergraph
rover supergraph compose --config supergraph-config.yaml --output supergraph-schema.graphql

# Verify
cat supergraph-schema.graphql
```

### Test Docker locally
```bash
# Build entire image
docker build -t supergraph:latest .

# Run subgraph target
docker build --target subgraph -t supergraph-subgraph:latest .
docker run -p 4001:4001 supergraph-subgraph:latest

# Run router target
docker build --target router -t supergraph-router:latest .
docker run -p 4000:4000 supergraph-router:latest

# Use docker-compose
docker-compose up
```

## GitHub Actions Setup

### Required Secrets

If using a private container registry (e.g., GitHub Container Registry, Docker Hub, or private registry):

Add these to your repository settings (`Settings` → `Secrets and variables` → `Actions`):

| Secret | Value | Example |
|--------|-------|---------|
| `REGISTRY_URL` | Container registry hostname | `ghcr.io`, `docker.io`, or private registry URL |
| `REGISTRY_USERNAME` | Registry login username | Your GitHub username or Docker username |
| `REGISTRY_PASSWORD` | Registry auth token/password | GitHub PAT or Docker Hub token |

**Note:** If secrets are not configured, the workflow will still run composition validation but skip the push step.

### Optional Configuration

#### Apollo GraphOS Integration (Managed Federation)
If you plan to use managed federation later, add:
```yaml
- name: Register Schema with Apollo
  run: rover subgraph publish ...
  env:
    APOLLO_KEY: ${{ secrets.APOLLO_KEY }}
```

## Troubleshooting

### Workflow Fails at "Compose Supergraph"
- **Cause:** Subgraph not responding or incorrect `supergraph-config.yaml`
- **Fix:** 
  - Verify `app.py` has `@strawberry.federation.type` decorators
  - Ensure `supergraph-config.yaml` points to `http://localhost:4001/graphql`
  - Check subgraph starts: `curl -X POST http://localhost:4001/graphql -H "Content-Type: application/json" -d '{"query":"{ _service { sdl } }"}'`

### Docker Build Fails During Composition
- **Cause:** Rover binary download fails or subgraph startup times out
- **Fix:**
  - Increase sleep timeout in Dockerfile composer stage
  - Check Rover download URL works: `curl -I https://rover.apollo.dev/download/linux/x86_64/latest`
  - Verify `python -m uvicorn app:app` works locally

### Registry Push Fails
- **Cause:** Secrets not configured or invalid credentials
- **Fix:**
  - Verify `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` are set
  - Test credentials locally: `docker login $REGISTRY_URL`
  - For GHCR: Use GitHub PAT with `write:packages` scope

## Files Overview

| File | Purpose |
|------|---------|
| `.github/workflows/supergraph-deploy.yaml` | CI/CD pipeline |
| `Dockerfile` | Multi-stage image for both subgraph and router |
| `docker-compose.yml` | Local testing orchestration |
| `supergraph-config.yaml` | Rover composition config |
| `app.py` | Python/Strawberry GraphQL subgraph |
| `router.yaml` | Apollo Router configuration |

## Next Steps

1. **Set up registry secrets** if not already done
2. **Test locally:** `docker-compose up`
3. **Push to main branch** to trigger GitHub Actions
4. **Monitor Actions tab** for build status
5. **Download artifacts** to inspect composed schema
6. **Pull Docker image** and deploy to your infrastructure

## Production Considerations

- Consider adding **schema change notifications** to Slack/Teams
- Set up **branch protection rules** to require passing Actions checks
- Add **vulnerability scanning** (e.g., `docker/scout-action`)
- Configure **image signing** using Cosign
- Add **smoke tests** after deployment
- Monitor **Apollo Router metrics** (CPU, memory, query latency)
