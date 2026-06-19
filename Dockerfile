# Stage 1: Subgraph runtime
FROM python:3.11-slim as subgraph

WORKDIR /app

COPY app.py .
COPY pyproject.toml* .
COPY requirements.txt* .

RUN python -m pip install --no-cache-dir "strawberry-graphql[fastapi]" uvicorn

EXPOSE 4001

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:4001/graphql')" || exit 1

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "4001"]

# Stage 2: Router runtime
FROM ubuntu:22.04 as router

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Apollo Router
RUN curl -sSL curl -sSL https://router.apollo.dev/download/nix/latest | sh && \
    /root/.router/bin/router --version

WORKDIR /app

# Copy router config
COPY router.yaml .

# Copy composed supergraph schema (built by CI workflow)
COPY supergraph-schema.graphql .

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/.well-known/apollo/server-health || exit 1

CMD ["/root/.router/bin/router", "--config", "router.yaml", "--supergraph", "supergraph-schema.graphql"]
