# frozen_string_literal: true

require_relative "models"

module Weaviate
  module Cluster
    # Port of weaviate.cluster.replicate.sync._Replicate (`client.cluster.replications`).
    class Replicate
      def initialize(connection)
        @connection = connection
      end

      # Get a replicate operation by its UUID, or nil if it does not exist.
      def get(uuid:, include_history: false)
        params = {}
        params["includeHistory"] = include_history if include_history
        res = @connection.get(
          "/replication/replicate/#{uuid}", params: params, error_msg: "Failed to get replicate operation",
                                            status_codes: codes([200, 404], "replicate get")
        )
        return nil if res.status_code == 404

        ReplicateOperation.from_weaviate(res.json, include_history)
      end

      # List all replicate operations (with history).
      def list_all
        res = @connection.get(
          "/replication/replicate/list", params: { "includeHistory" => true },
                                         error_msg: "Failed to list replicate operations",
                                         status_codes: codes([200], "replicate list")
        )
        res.json.map { |item| ReplicateOperation.from_weaviate(item, true) }
      end

      # Query replicate operations by collection, shard, target node, or any combination of the three.
      def query(collection: nil, shard: nil, target_node: nil, include_history: false)
        params = {}
        params["collection"] = collection if present?(collection)
        params["shard"] = shard if present?(shard)
        params["targetNode"] = target_node if present?(target_node)
        params["includeHistory"] = include_history if include_history

        res = @connection.get(
          "/replication/replicate/list", params: params, error_msg: "Failed to query replicate operations",
                                         status_codes: codes([200], "replicate query")
        )
        res.json.map { |item| ReplicateOperation.from_weaviate(item, include_history) }
      end

      # Cancel a replicate operation by its UUID.
      def cancel(uuid:)
        @connection.post("/replication/replicate/#{uuid}/cancel", weaviate_object: {},
                                                                  error_msg: "Failed to cancel replicate operation",
                                                                  status_codes: codes([204], "replicate cancel"))
        nil
      end

      # Delete a replicate operation by its UUID.
      def delete(uuid:)
        @connection.delete("/replication/replicate/#{uuid}", error_msg: "Failed to delete replicate operation",
                                                             status_codes: codes([204], "replicate delete"))
        nil
      end

      # Delete all replicate operations.
      def delete_all
        @connection.delete("/replication/replicate", error_msg: "Failed to delete all replicate operations",
                                                     status_codes: codes([204], "replicate delete all"))
        nil
      end

      private

      def present?(value)
        !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
      end

      def codes(ok, error)
        ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)
      end
    end
  end
end
