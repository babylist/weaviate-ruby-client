# frozen_string_literal: true

require_relative "models"
require_relative "replicate"

module Weaviate
  module Cluster
    # Port of weaviate.cluster.sync._Cluster (`client.cluster`).
    class Cluster
      # `client.cluster.replications`
      attr_reader :replications

      def initialize(connection)
        @connection = connection
        @replications = Replicate.new(connection)
      end

      # Replicate a shard from one node to another. Returns the UUID (String) of the replicate task.
      def replicate(collection:, shard:, source_node:, target_node:, replication_type: ReplicationType::COPY)
        body = {
          "collection" => collection,
          "shard" => shard,
          "sourceNode" => source_node,
          "targetNode" => target_node,
          "type" => ReplicationType.from(replication_type)
        }
        res = @connection.post("/replication/replicate", weaviate_object: body, error_msg: "Failed to replicate shard",
                                                         status_codes: codes([200], "replicate replicate"))
        ::Weaviate::Util.get_valid_uuid(res.json["id"])
      end

      # Query the sharding state of a collection (or of one shard). Returns a ShardingState or nil.
      def query_sharding_state(collection:, shard: nil)
        params = { "collection" => collection }
        params["shard"] = shard unless shard.nil?
        res = @connection.get("/replication/sharding-state", params: params, error_msg: "Failed to get sharding state",
                                                             status_codes: codes([200, 404], "replicate sharding state"))
        return nil if res.status_code == 404

        ShardingState.from_weaviate(res.json)
      end

      # Get the status of all nodes in the cluster.
      #
      # +output+: "minimal" or "verbose" (nil = server default, minimal).
      # Returns an Array of Node (shards/stats populated only for verbose output).
      def nodes(collection_ = nil, shard_ = nil, collection: collection_, shard: shard_, output: nil)
        path = +"/nodes"
        params = {}
        path << "/#{::Weaviate::Util.capitalize_first_letter(collection)}" unless collection.nil?
        params["shardName"] = shard unless shard.nil?
        params["output"] = output unless output.nil?

        res = @connection.get(path, params: params, error_msg: "Get nodes status failed")
        response_typed = ::Weaviate::Util.decode_json_response_dict(res, "Nodes status")
        nodes = response_typed["nodes"]
        if nodes.nil? || nodes.empty?
          raise ::Weaviate::Exceptions::EmptyResponseError, "Nodes status response returned empty"
        end

        output == "verbose" ? ConvertFromREST.nodes_verbose(nodes) : ConvertFromREST.nodes_minimal(nodes)
      end

      # Get RAFT cluster statistics. Returns a ClusterStatistics.
      def statistics
        res = @connection.get("/cluster/statistics", error_msg: "Get cluster statistics failed",
                                                     status_codes: codes([200], "cluster statistics"))
        ClusterStatistics.from_weaviate(::Weaviate::Util.decode_json_response_dict(res, "Cluster statistics"))
      end

      private

      def codes(ok, error)
        ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)
      end
    end
  end
end
