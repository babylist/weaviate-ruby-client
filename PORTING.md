# Porting conventions (weaviate-python-client v4 → Ruby)

Source of truth: `../weaviate-python-client/weaviate` (v4.24.1+). Port the **sync** API only
(`WeaviateClient`, `Collection`, `_*Sync`/sync executors). The async client, grpc-web/Pyodide,
v3 GraphQL builders (`weaviate/gql`) and `weaviate/agents` (external package) are out of scope.

## Naming
- Ruby module paths mirror Python packages, CamelCased, private `_` prefix dropped:
  `weaviate.collections.classes.filters._FilterValue` → `Weaviate::Classes::Query::FilterValue`
  (see the area map below for where each Python module lands).
- Method and keyword names stay **identical to Python** (snake_case). Python positional-or-keyword
  first parameters (e.g. `near_text(query, ...)`, `insert(properties, ...)`) are Ruby positional;
  everything after is a keyword argument with the same default.
- Python `is_x()` methods keep their name and also get a `x?` alias.
- Python `__len__` → `length`/`size`; `__iter__` → `each` + `include Enumerable`;
  `with` context managers → method taking a block (`collection.batch.dynamic { |b| ... }`).
- Python `str` Enums → modules that `extend Weaviate::StrEnum` holding frozen String constants
  (`Weaviate::Classes::Config::DataType::TEXT == "text"`).
- pydantic models / dataclasses → subclasses of `Weaviate::Model` (`lib/weaviate/model.rb`):
  `attribute :name` (required), `attribute :limit, default: 10`, `attribute :tags, default: -> { [] }`,
  validation in `after_initialize`. Python `_to_dict()` → `to_dict` (returns String-keyed Hash in
  the exact REST JSON shape the Python client sends). Python `model_dump` → `to_h`.
- Python `Optional[X] = None` → keyword default `nil`.
- UUIDs are Strings (normalise with `Weaviate::Util.get_valid_uuid`). Datetimes are `Time`.
- Bytes/blobs are base64 Strings; use `Weaviate::Util.parse_blob` for path/IO inputs.

## Placement
- User-facing **input** classes: `Weaviate::Classes::<Area>` in `lib/weaviate/classes/<area>/…`
  (mirrors `weaviate.classes.<area>`).
- **Return/output** classes: `Weaviate::Outputs::<Area>` in `lib/weaviate/outputs/<area>/…`
  (mirrors `weaviate.outputs.<area>`).
- Executors / namespaces (`collection.query`, `client.backup`, …): `Weaviate::Collections::…`
  under `lib/weaviate/collections/…` or a top-level feature module (`Weaviate::Backup::Backup`).
- Every `.rb` under `classes/ outputs/ collections/ embedded/ aliases/ backup/ cluster/ debug/
  export/ groups/ rbac/ tokenization/ users/` is auto-required (sorted). A file that needs another
  file **at load time** (superclass, mixin, constant used in a class body) must `require_relative` it.
  Otherwise reference other areas' constants only inside methods.
- Always reference other areas with fully-qualified names (`::Weaviate::Classes::Config::DataType`):
  `Weaviate::Config` (client config), `Weaviate::Classes::Config` (schema config) and
  `Weaviate::Collections::Config` (the `collection.config` namespace) all exist, and
  `Weaviate::Collections::Collections` is a class inside the `Weaviate::Collections` module.

## Core APIs available to every area
- `connection` (`Weaviate::Connect::Connection`): `get/post/put/patch/delete/head(path, weaviate_object:,
  params:, error_msg:, status_codes: Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "…"))`
  returning `Weaviate::Connect::HTTPResponse` (`status_code`, `body`, `json`); gRPC:
  `grpc_search(req)`, `grpc_aggregate(req)`, `grpc_batch_objects(req, timeout:, max_retries:)`,
  `grpc_batch_references`, `grpc_batch_delete(req)`, `grpc_tenants_get(req)`,
  `grpc_batch_stream(enum) { |reply| }`; `weaviate_version` (`Weaviate::ServerVersion`, with
  `is_at_least(1, 25, 0)` etc.), `timeout_config`.
- Protobuf messages: `Weaviate::V1::*` (generated, `lib/weaviate/proto/v1`). Enums are Symbols
  (`:CONSISTENCY_LEVEL_ONE`). `google.protobuf.Struct` → `Google::Protobuf::Struct`.
- Errors: `Weaviate::Exceptions::*` (same class names as `weaviate.exceptions`).
- Warnings: `Weaviate::Warnings.<python_method_name>(…)` (add missing ones to `lib/weaviate/warnings.rb`
  — append only, do not reorder).
- Utils: `Weaviate::Util` (`get_valid_uuid`, `generate_uuid5`, `decode_json_response_dict`,
  `datetime_to_string`, `datetime_from_weaviate_str`, `to_beacons`, `capitalize_first_letter`, …).

## Tests
- Port the Python tests for your area to RSpec under `spec/unit/...` (from `test/`) and
  `spec/mock/...` (from `mock_tests/`), one `_spec.rb` per Python test file, keeping test names.
- Mock tests: `include_context "mock weaviate"` (see `spec/support/mock_context.rb`):
  `httpserver.expect_request(path, method:, query:, headers:, json:).respond_with_json(obj, status:)`,
  `no_auth_mock!`, `auth_mock!`, `connect_mock_client(**kw)`, and `grpc_impl { def search(req, call) … end }`
  to install gRPC behaviour (`call.metadata`, `call.deadline`; raise `GRPC::PermissionDenied` etc.).
- Run: `bundle exec rspec spec/unit spec/mock`.
- Integration tests (`integration/`) need a live Weaviate; port them under `spec/integration`
  tagged `:integration` (run with `WEAVIATE_INTEGRATION=1`).
