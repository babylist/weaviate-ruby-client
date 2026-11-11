# frozen_string_literal: true

# Hand-written gRPC service definitions mirroring v1/weaviate.proto and the
# Weaviate health check (served on the standard grpc.health.v1.Health path).
require "grpc"
require_relative "weaviate_pb"
require_relative "health_weaviate_pb"

module Weaviate
  module V1
    module WeaviateService
      class Service
        include ::GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = "weaviate.v1.Weaviate"

        rpc :Search, ::Weaviate::V1::SearchRequest, ::Weaviate::V1::SearchReply
        rpc :BatchObjects, ::Weaviate::V1::BatchObjectsRequest, ::Weaviate::V1::BatchObjectsReply
        rpc :BatchReferences, ::Weaviate::V1::BatchReferencesRequest, ::Weaviate::V1::BatchReferencesReply
        rpc :BatchDelete, ::Weaviate::V1::BatchDeleteRequest, ::Weaviate::V1::BatchDeleteReply
        rpc :TenantsGet, ::Weaviate::V1::TenantsGetRequest, ::Weaviate::V1::TenantsGetReply
        rpc :Aggregate, ::Weaviate::V1::AggregateRequest, ::Weaviate::V1::AggregateReply
        rpc :BatchStream, stream(::Weaviate::V1::BatchStreamRequest), stream(::Weaviate::V1::BatchStreamReply)
      end

      Stub = Service.rpc_stub_class
    end

    module HealthService
      class Service
        include ::GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = "grpc.health.v1.Health"

        rpc :Check, ::Weaviate::V1::WeaviateHealthCheckRequest, ::Weaviate::V1::WeaviateHealthCheckResponse
      end

      Stub = Service.rpc_stub_class
    end
  end
end
