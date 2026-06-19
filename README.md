# Python subgraph + Apollo Router — minimal supergraph

This is the smallest possible federated GraphQL setup: one Python subgraph
(Strawberry GraphQL + FastAPI) and the Apollo Router composing/serving it
as a supergraph.

## 1. Start the Python subgraph

    cd products-subgraph
    python3 -m venv .venv && source .venv/bin/activate
    pip install "strawberry-graphql[fastapi]" uvicorn
    uvicorn app:app --port 4001

Verify it speaks the federation protocol:

curl -s -X POST http://localhost:4001/graphql  -H "Content-Type: application/json"  -d "{"query":"{ _service { sdl } }"}"

You should see the subgraph's SDL, including `@key(fields: "id")` on `Product`.

## 2. Install Rover (Apollo's CLI)

    curl -sSL https://rover.apollo.dev/nix/latest | sh

## 3. Compose the supergraph locally (no GraphOS account needed for this step)

    C:\Users\nzai\.rover\bin\rover supergraph compose --config ./supergraph-config.yaml --output ./supergraph-schema.graphql

`supergraph-config.yaml` in this folder points rover at the running
subgraph's URL so it can introspect + compose. The output is the compiled
supergraph SDL — `supergraph-schema.graphql` in this folder shows what
that file looks like for this one-subgraph example (note the `join__`
directives — that's the router's internal "which field lives in which
subgraph" map).

## 4. Install and run Apollo Router

    curl -sSL https://router.apollo.dev/download/nix/latest | sh
    c:\tools\router --config router.yaml --supergraph supergraph-schema.graphql

The router now listens on http://localhost:4000.

## 5. Query through the router

    curl -s -X POST http://localhost:4000 \
      -H "Content-Type: application/json" \
      -d '{"query":"{ products { id name price } }"}'

curl -s -X POST http://localhost:4000  -H "Content-Type: application/json"  -d "{\"query\":\"{ products { id name price } }\"}"

This request never touches the Python subgraph directly — it goes to the
router, which plans the query, calls the Products subgraph at
localhost:4001 on your behalf, and returns the merged result.

## Notes
- This sandbox could not download `rover` or `router` binaries (network
  egress here only allowlists package registries like pip/npm/github, not
  apollo.dev), so steps 2-4 are shown as exact commands to run on your own
  machine rather than executed here. Steps 1 and the subgraph's federation
  behavior (the `_service { sdl }` response) were verified live in this
  environment.
- Once you add a second subgraph (e.g. an `orders` service referencing
  `Product` by key), add it to `supergraph-config.yaml` and re-run
  `rover supergraph compose` — that's the entire mechanism described in
  the deployment pipeline from earlier in this conversation.
