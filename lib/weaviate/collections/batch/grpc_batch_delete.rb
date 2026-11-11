# frozen_string_literal: true

require_relative "helpers"

module Weaviate
  module Collections
    module Batch
      # Port of weaviate.collections.batch.grpc_batch_delete._BatchDeleteGRPC: deletes multiple objects from
      # Weaviate using the gRPC API.
      class BatchDeleteGRPC
        def initialize(weaviate_version:, consistency_level:)
          @weaviate_version = weaviate_version
          @consistency_level = Helpers.consistency_level_to_grpc(consistency_level)
        end

        def batch_delete(connection, name:, filters:, verbose:, dry_run:, tenant:)
          request = ::Weaviate::V1::BatchDeleteRequest.new(
            collection: name,
            consistency_level: @consistency_level,
            verbose: verbose,
            dry_run: dry_run,
            tenant: tenant,
            filters: self.class.filter_to_grpc(filters)
          )
          res = connection.grpc_batch_delete(request)
          objects =
            if verbose
              res.objects.map do |obj|
                ::Weaviate::Outputs::Data::DeleteManyObject.new(
                  uuid: self.class.uuid_from_bytes(obj.uuid),
                  successful: obj.successful,
                  error: obj.error == "" ? nil : obj.error
                )
              end
            end
          ::Weaviate::Outputs::Data::DeleteManyReturn.new(failed: res.failed, successful: res.successful,
                                                          matches: res.matches, objects: objects)
        end

        # Python _WeaviateUUIDInt(int.from_bytes(uuid, "big")): 16 big-endian bytes -> canonical UUID string.
        def self.uuid_from_bytes(bytes)
          hex = bytes.unpack1("H*").rjust(32, "0")[-32..]
          "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
        end

        # Python weaviate.collections.filters._FilterToGRPC.convert (owned by the query area).
        def self.filter_to_grpc(filters)
          ::Weaviate::Collections::Grpc::FilterToGRPC.convert(filters)
        end
      end
    end
  end
end
