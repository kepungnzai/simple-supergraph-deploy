# Stage 1: Build supergraph schema
FROM node:18-alpine AS composer

RUN apk add --no-cache curl python3

# Install Rover
RUN curl -sSL https://rover.apollo.dev/nix/latest | sh
ENV PATH="/root/.rover/bin:${PATH}"

WORKDIR /build
COPY supergraph-config.yaml .
COPY products-subgraph/ ./products-subgraph/

# Pre-stage subgraph startup for composition
RUN cd products-subgraph && \
    python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --no-cache-dir "strawberry-graphql[fastapi]" uvicorn

# Start subgraph in background and compose schema
RUN cd products-subgraph && \
    . venv/bin/activate && \
    uvicorn app:app --port 4001 --host 0.0.0.0 > /dev/null 2>&1 & \
    sleep 5 && \
    rover supergraph compose --config ../supergraph-config.yaml --output ../supergraph-schema.graphql && \
    wait

# Stage 2: Subgraph runtime
FROM python:3.11-slim AS subgraph-base

WORKDIR /subgraph
COPY products-subgraph/ .

RUN python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --no-cache-dir "strawberry-graphql[fastapi]" uvicorn

EXPOSE 4001
CMD ["/bin/bash", "-c", "source venv/bin/activate && uvicorn app:app --host 0.0.0.0 --port 4001"]

# Stage 3: Router runtime
FROM ubuntu:22.04 AS router

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://router.apollo.dev/download/nix/latest | sh
ENV PATH="/root/.router/bin:${PATH}"

WORKDIR /app
COPY router.yaml .
COPY --from=composer /build/supergraph-schema.graphql .

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:4000/.well-known/apollo/server-health || exit 1

CMD ["router", "--config", "router.yaml", "--supergraph", "supergraph-schema.graphql"]