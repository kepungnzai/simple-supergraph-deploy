import strawberry
from strawberry.fastapi import GraphQLRouter
from fastapi import FastAPI

# In-memory "database" for the demo
PRODUCTS_DB = {
    "1": {"id": "1", "name": "Wireless Mouse", "price": 29.99},
    "2": {"id": "2", "name": "Mechanical Keyboard", "price": 89.99},
}


@strawberry.federation.type(keys=["id"])
class Product:
    id: strawberry.ID
    name: str
    price: float

    # This is the entity resolver. The router calls this whenever
    # another subgraph (e.g. Orders) only has a Product reference
    # (just the id) and needs the rest of the fields resolved.
    @classmethod
    def resolve_reference(cls, id: strawberry.ID) -> "Product":
        data = PRODUCTS_DB[id]
        return cls(id=data["id"], name=data["name"], price=data["price"])


@strawberry.type
class Query:
    @strawberry.field
    def product(self, id: strawberry.ID) -> Product:
        data = PRODUCTS_DB[id]
        return Product(id=data["id"], name=data["name"], price=data["price"])

    @strawberry.field
    def products(self) -> list[Product]:
        return [Product(**p) for p in PRODUCTS_DB.values()]


# federation_version turns on @key, @shareable, _service, _entities etc.
schema = strawberry.federation.Schema(query=Query, federation_version="2.6")

graphql_app = GraphQLRouter(schema)

app = FastAPI()
app.include_router(graphql_app, prefix="/graphql")
