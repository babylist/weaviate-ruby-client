# frozen_string_literal: true

require "net/http"
require "securerandom"
require "json"

# Helpers shared by the integration specs ported from test_client.py, test_auth.py,
# test_backup_v4.py, test_rbac.py, test_users.py, test_replicate.py, test_tenants.py and
# test_collection_openai.py. Include explicitly (`include Batch5Helpers`) in those describes.
module Batch5Helpers
  RBAC_AUTH_CREDS = Weaviate::Auth.api_key("admin-key")

  # Port and gRPC port of the default ("8080/50051") instance, honouring WEAVIATE_PORT/WEAVIATE_GRPC_PORT.
  def self.default_port = Integer(ENV.fetch("WEAVIATE_PORT", 8080))
  def self.default_grpc_port = Integer(ENV.fetch("WEAVIATE_GRPC_PORT", 50_051))

  def default_port = Batch5Helpers.default_port
  def default_grpc_port = Batch5Helpers.default_grpc_port

  # Python: weaviate.connect.ConnectionParams.from_url("http://localhost:8080", 50051)
  def default_connection_params
    Weaviate::Connect::ConnectionParams.from_url("http://localhost:#{default_port}", default_grpc_port)
  end

  # Python: weaviate.connect_to_local(...) against the default instance.
  def connect_to_default_local(**kwargs, &block)
    Weaviate.connect_to_local(port: default_port, grpc_port: default_grpc_port, **kwargs, &block)
  end

  # Python: weaviate.connect_to_local(port: ..., ...) against a docker-only instance.
  def connect_to_docker_local(port:, grpc_port: 50_051, **kwargs, &block)
    skip("needs the docker-compose instance on port #{port}") unless IntegrationContext.available?([port, grpc_port])
    port, grpc_port = IntegrationContext.resolve_ports([port, grpc_port])
    Weaviate.connect_to_local(port: port, grpc_port: grpc_port, **kwargs, &block)
  end

  # Python test_auth.is_auth_enabled
  def is_auth_enabled(url) # rubocop:disable Naming/PredicatePrefix
    res = Net::HTTP.get_response(URI("http://#{url}/v1/.well-known/openid-configuration"))
    res.code.to_i == 200
  end

  # Python integration.conftest._sanitize_collection_name
  def sanitize_name(name) = IntegrationContext.sanitize_collection_name(name)

  # Python request.node.name: the example description (incl. parametrization suffix).
  def node_name = RSpec.current_example.description

  # Python test_backup_v4.unique_backup_id
  def unique_backup_id(name)
    sanitize_name(name) + SecureRandom.uuid.delete("-")[0, 12]
  end

  # Python `pytest.warns` / recwarn: run the block and return the captured warning messages.
  def capture_warnings(&block)
    Weaviate::Warnings.capture(&block)[1]
  end
end

# Namespace for the batch-5 integration spec files: wrapping `RSpec.describe` in `module Batch5Specs`
# makes these short constant names resolve lexically without defining top-level constants.
module Batch5Specs
  Config = Weaviate::Classes::Config
  Query = Weaviate::Classes::Query
  Data = Weaviate::Classes::Data
  Tenants = Weaviate::Classes::Tenants
  RBAC = Weaviate::Classes::RBAC
  Models = Weaviate::RBAC::Models
  Exceptions = Weaviate::Exceptions
  Tenant = Weaviate::Classes::Tenants::Tenant
  TenantCreate = Weaviate::Classes::Tenants::TenantCreate
  TenantActivityStatus = Weaviate::Classes::Tenants::TenantActivityStatus
  DataObject = Weaviate::Classes::Data::DataObject
  GroupBy = Weaviate::Classes::Query::GroupBy
  Rerank = Weaviate::Classes::Query::Rerank
  GenerativeConfig = Weaviate::Classes::Generate::GenerativeConfig
  GenerativeParameters = Weaviate::Classes::Generate::GenerativeParameters
end
