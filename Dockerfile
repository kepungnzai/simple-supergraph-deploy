# Stage 1: Build supergraph schema
FROM python:3.11-slim as composer

# Install curl for downloading tools
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy app and config
COPY app.py .
COPY supergraph-config.yaml .
COPY pyproject.toml .
COPY requirements.txt* .

# Install Python dependencies
RUN python -m pip install --no-cache-dir "strawberry-graphql[fastapi]" uvicorn

# Download Rover CLI
RUN curl -sSL https://rover.apollo.dev/nix/latest | sh && \
    /root/.rover/bin/rover --version

# Start subgraph and compose supergraph schema
RUN nohup python -m uvicorn app:app --port 4001 --host 0.0.0.0 > /dev/null 2>&1 & \
    sleep 5 && \
    /root/.rover/bin/rover supergraph compose \
    --config ./supergraph-config.yaml \
    --output ./supergraph-schema.graphql && \
    kill %1 2>/dev/null || true

# Verify schema was created
RUN test -f supergraph-schema.graphql && test -s supergraph-schema.graphql || \
    (echo "Error: supergraph-schema.graphql not created"; exit 1)

# Stage 2: Subgraph runtime
FROM python:3.11-slim as subgraph

WORKDIR /app

# Install dependencies
COPY app.py .
COPY pyproject.toml* .
COPY requirements.txt* .

RUN python -m pip install --no-cache-dir "strawberry-graphql[fastapi]" uvicorn

EXPOSE 4001

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:4001/graphql')" || exit 1

CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "4001"]

# Stage 3: Router runtime
FROM ubuntu:22.04 as router

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download Apollo Router
RUN mkdir -p /root/.router/bin && \
    curl -sSL https://router.apollo.dev/download/linux/x86_64/latest | \
    tar xz -C /root/.router/bin router && \
    /root/.router/bin/router --version

WORKDIR /app

# Copy router config
COPY router.yaml .

# Copy composed supergraph schema from builder stage
COPY --from=composer /build/supergraph-schema.graphql .

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/.well-known/apollo/server-health || exit 1

CMD ["/root/.router/bin/router", "--config", "router.yaml", "--supergraph", "supergraph-schema.graphql"]