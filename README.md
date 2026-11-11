# weaviate-client (Ruby)

A Ruby port of the official [Weaviate Python client](https://github.com/weaviate/weaviate-python-client)
(v4 API, parity with Python client 4.24.1). It talks to Weaviate over REST and gRPC and keeps
the Python client's namespaces, method names and keyword arguments, so the Python documentation
applies almost verbatim.

```ruby
require "weaviate"

Config = Weaviate::Classes::Config
Query  = Weaviate::Classes::Query

Weaviate.connect_to_local do |client|               # block form closes the client
  articles = client.collections.create(
    "Article",
    properties: [
      Config::Property.new(name: "title", data_type: Config::DataType::TEXT),
      Config::Property.new(name: "views", data_type: Config::DataType::INT)
    ],
    vector_config: Config::Configure::Vectors.self_provided
  )

  articles.data.insert({ "title" => "Hello", "views" => 3 }, vector: [0.1, 0.2, 0.3])

  res = articles.query.near_vector(
    [0.1, 0.2, 0.3],
    limit: 2,
    filters: Query::Filter.by_property("views").greater_than(1),
    return_metadata: Query::MetadataQuery.new(distance: true)
  )
  res.objects.each { |o| puts "#{o.properties["title"]} #{o.metadata.distance}" }

  articles.batch.dynamic do |batch|
    100.times { |i| batch.add_object(properties: { "title" => "Doc #{i}", "views" => i }) }
  end
end
```

## Connecting

| Python                                   | Ruby                                                        |
|------------------------------------------|-------------------------------------------------------------|
| `weaviate.connect_to_local()`            | `Weaviate.connect_to_local`                                 |
| `weaviate.connect_to_weaviate_cloud(...)`| `Weaviate.connect_to_weaviate_cloud(cluster_url:, auth_credentials:)` |
| `weaviate.connect_to_custom(...)`        | `Weaviate.connect_to_custom(http_host:, ...)`               |
| `weaviate.connect_to_embedded()`         | `Weaviate.connect_to_embedded`                              |
| `with client: ...`                       | pass a block, or call `client.close`                        |
| `weaviate.classes.init.Auth.api_key(k)`  | `Weaviate::Auth.api_key(k)` (or just pass the String)       |

## Mapping conventions

- `weaviate.classes.<area>` → `Weaviate::Classes::<Area>`; `weaviate.outputs.<area>` → `Weaviate::Outputs::<Area>`.
- Method and keyword names match Python. A Python positional first argument stays positional.
- `with collection.batch.dynamic() as batch:` → `collection.batch.dynamic { |batch| ... }`.
- Python `str` enums are modules of String constants (`Config::DataType::TEXT == "text"`).
- `len(collection)` → `collection.length`; iterators include `Enumerable`.
- Errors keep the Python names under `Weaviate::Exceptions` (e.g. `Weaviate::Exceptions::WeaviateQueryError`);
  `Weaviate::Error` is the base class.
- Warnings carry the Python codes (`Dep024`, `Auth003`, ...). Capture them with
  `Weaviate::Warnings.capture { ... }` or set `Weaviate::Warnings.handler = ->(msg) { ... }`.

Not ported: the async client (Ruby code runs synchronously; use threads), grpc-web/Pyodide,
the v3 GraphQL builders and the separately packaged Weaviate Agents.

## Development

```bash
bundle install
bundle exec rspec                 # unit + mock-server specs (no Weaviate needed)
```

Integration specs (ported from the Python `integration/` suite) need a running Weaviate:

```bash
bin/integration docker [VERSION]  # full suite against the ci/ docker-compose stack (needs Docker)
bin/integration native [VERSION]  # no Docker: downloads the official Weaviate binary and starts it on
                                  # :8080/:50051 plus an API-key/RBAC instance on :8092/:50063
bin/integration running           # use a Weaviate you started yourself on :8080/:50051
```

In native mode, specs that need containers the binary can't replace (text2vec-contextionary,
okta/OIDC, the multi-node cluster, OpenAI/Cohere keys) are skipped, and version-gated specs
skip on older servers exactly like the Python suite. `bin/weaviate-native` can also be used on
its own to run extra instances (`--name`, `--port`, `--grpc-port`, `--profile rbac`); point the
specs at them with `WEAVIATE_PORT`, `WEAVIATE_GRPC_PORT` and `WEAVIATE_PORT_MAP="8092=8186,50063=50186"`.

The protobuf bindings in `lib/weaviate/proto/v1` were generated from the descriptors shipped
with the Python client (`protoc --ruby_out`); `weaviate_services_pb.rb` holds the gRPC services.
See `PORTING.md` for the porting conventions.
