# frozen_string_literal: true

require_relative "models"

module Weaviate
  module Cluster
    # Port of weaviate.cluster.replicate.sync._Replicate (`client.cluster.replications`).
    class Replicate
      # Check each release branch with ServerVersion#is_at_least_any so an older
      # branch's backport does not incorrectly enable an unpatched newer branch.
      SCALE_PLAN_MIN_VERSIONS = [[1, 31, 20], [1, 32, 17], [1, 33, 5], [1, 34, 1]].freeze

      def initialize(connection)
        @connection = connection
      end

      # Generate a replication scale plan for a collection.
      #
      # Requires replica movement enabled and Weaviate 1.31.20+, 1.32.17+, 1.33.5+ or 1.34.1+ on the
      # corresponding release branch, or a newer minor release. Generating a plan does not change replica
      # placement. Submit the returned plan with `apply_scale_plan`, with or without edits.
      #
      # +collection+ has its first letter capitalized. +replication_factor+ is the desired number of
      # replicas per shard; the server rejects values below one.
      def generate_scale_plan(collection:, replication_factor:)
        check_scale_plan_version
        res = @connection.get(
          "/replication/scale",
          params: { "collection" => ::Weaviate::Util.capitalize_first_letter(collection),
                    "replicationFactor" => replication_factor },
          error_msg: "Failed to generate replication scale plan",
          status_codes: codes([200], "generate replication scale plan")
        )
        json = res.json
        ReplicationScalePlan.new(
          plan_id: ::Weaviate::Util.get_valid_uuid(json["planId"]),
          collection: json["collection"],
          shard_scale_actions: json["shardScaleActions"].to_h do |shard, actions|
            additions = (actions["addNodes"] || {}).map do |target_node, source_node|
              ReplicaAddition.new(target_node: target_node, source_node: source_node)
            end
            [shard, ShardScaleActions.new(remove_nodes: actions["removeNodes"], add_nodes: additions)]
          end
        )
      end

      # Apply a replication scale plan.
      #
      # Requires the same server versions as `generate_scale_plan`. The plan is submitted without
      # modification or regeneration (its collection name is sent as given); the server validates its
      # actions against the cluster state. This method does not wait for replication to complete.
      #
      # Raises WeaviateInvalidInputError if a shard lists the same target node more than once.
      def apply_scale_plan(plan:)
        check_scale_plan_version

        shard_scale_actions = plan.shard_scale_actions.to_h do |shard, actions|
          add_nodes = {}
          # Converting duplicate targets to a JSON object would silently drop an addition.
          actions.add_nodes.each do |addition|
            if add_nodes.key?(addition.target_node)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "Shard #{shard.inspect} contains duplicate target node #{addition.target_node.inspect}"
            end
            add_nodes[addition.target_node] = addition.source_node
          end
          [shard, { "removeNodes" => actions.remove_nodes, "addNodes" => add_nodes }]
        end

        res = @connection.post(
          "/replication/scale",
          weaviate_object: { "planId" => plan.plan_id.to_s, "collection" => plan.collection,
                             "shardScaleActions" => shard_scale_actions },
          error_msg: "Failed to apply replication scale plan",
          status_codes: codes([200], "apply replication scale plan")
        )
        json = res.json
        ReplicationScaleApplyResult.new(
          plan_id: ::Weaviate::Util.get_valid_uuid(json["planId"]),
          collection: json["collection"],
          operation_ids: (json["operationIds"] || []).map { |id| ::Weaviate::Util.get_valid_uuid(id) }
        )
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

      def check_scale_plan_version
        version = @connection.weaviate_version
        return if version.is_at_least_any(*SCALE_PLAN_MIN_VERSIONS)

        minimum_versions = SCALE_PLAN_MIN_VERSIONS.map { |minimum| minimum.join(".") }.join(" or ")
        raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
          "Replication scale plans", version.to_s, "#{minimum_versions} on the corresponding release branch"
        )
      end

      def present?(value)
        !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
      end

      def codes(ok, error)
        ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)
      end
    end
  end
end
