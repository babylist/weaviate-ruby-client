# frozen_string_literal: true

module Weaviate
  # Port of weaviate.cluster (models, `client.cluster`, `client.cluster.replications`).
  module Cluster
    # Python `Verbosity` literal.
    module Verbosity
      extend ::Weaviate::StrEnum
      MINIMAL = "minimal"
      VERBOSE = "verbose"
    end

    # Enum for replication types.
    module ReplicationType
      extend ::Weaviate::StrEnum
      COPY = "COPY"
      MOVE = "MOVE"
    end

    # Enum for replication operation states.
    module ReplicateOperationState
      extend ::Weaviate::StrEnum
      REGISTERED = "REGISTERED"
      HYDRATING = "HYDRATING"
      FINALIZING = "FINALIZING"
      DEHYDRATING = "DEHYDRATING"
      INTEGRATING = "INTEGRATING"
      READY = "READY"
      CANCELLED = "CANCELLED"
    end

    # The status of a replication operation.
    class ReplicateOperationStatus < ::Weaviate::Model
      attribute :state
      attribute :errors

      def self.from_weaviate(data)
        new(
          state: ReplicateOperationState.from(data["state"]),
          errors: (data["errors"] || []).map { |e| e.is_a?(Hash) ? e.fetch("message", "") : e }
        )
      end
    end

    # A replication operation. +status_history+ is nil unless requested.
    class ReplicateOperation < ::Weaviate::Model
      attribute :collection
      attribute :shard
      attribute :source_node
      attribute :status
      attribute :status_history
      attribute :target_node
      attribute :transfer_type
      attribute :uuid

      def self.from_weaviate(data, include_history)
        history =
          if include_history && !data["statusHistory"].nil?
            data["statusHistory"].map { |s| ReplicateOperationStatus.from_weaviate(s) }
          end
        new(
          collection: data["collection"],
          shard: data["shard"],
          source_node: data["sourceNode"],
          status: ReplicateOperationStatus.from_weaviate(data["status"]),
          status_history: history,
          target_node: data["targetNode"],
          transfer_type: ReplicationType.from(data["type"]),
          uuid: ::Weaviate::Util.get_valid_uuid(data["id"])
        )
      end
    end
    # Python generic aliases of _ReplicateOperation.
    ReplicateOperationWithHistory = ReplicateOperation
    ReplicateOperationWithoutHistory = ReplicateOperation

    # A shard and the nodes holding its replicas.
    class ShardReplicas < ::Weaviate::Model
      attribute :name
      attribute :replicas

      def self.from_weaviate(data)
        new(name: data["shard"], replicas: data["replicas"])
      end
    end

    # The sharding state of a collection.
    class ShardingState < ::Weaviate::Model
      attribute :collection
      attribute :shards

      def self.from_weaviate(data)
        ss = data["shardingState"]
        new(collection: ss["collection"], shards: ss["shards"].map { |s| ShardReplicas.from_weaviate(s) })
      end
    end

    # --- RAFT cluster statistics ---

    # A member in the RAFT cluster's latest configuration.
    class RaftConfigurationMember < ::Weaviate::Model
      attribute :address
      attribute :node_id
      attribute :suffrage

      def self.from_weaviate(data)
        new(address: data["address"], node_id: data["id"], suffrage: data["suffrage"])
      end
    end

    # RAFT consensus statistics for a node.
    class RaftStats < ::Weaviate::Model
      FIELDS = {
        applied_index: "appliedIndex", commit_index: "commitIndex", fsm_pending: "fsmPending",
        last_contact: "lastContact", last_log_index: "lastLogIndex", last_log_term: "lastLogTerm",
        last_snapshot_index: "lastSnapshotIndex", last_snapshot_term: "lastSnapshotTerm",
        latest_configuration: "latestConfiguration", latest_configuration_index: "latestConfigurationIndex",
        num_peers: "numPeers", protocol_version: "protocolVersion", protocol_version_max: "protocolVersionMax",
        protocol_version_min: "protocolVersionMin", snapshot_version_max: "snapshotVersionMax",
        snapshot_version_min: "snapshotVersionMin", state: "state", term: "term"
      }.freeze
      FIELDS.each_key { |f| attribute f }

      def self.from_weaviate(data)
        kwargs = FIELDS.to_h { |attr, key| [attr, data.fetch(key, "")] }
        kwargs[:latest_configuration] =
          data.fetch("latestConfiguration", []).map { |m| RaftConfigurationMember.from_weaviate(m) }
        new(**kwargs)
      end
    end

    # RAFT cluster statistics for a single node.
    class NodeStatistics < ::Weaviate::Model
      attribute :candidates
      attribute :db_loaded
      attribute :initial_last_applied_index
      attribute :is_voter
      attribute :leader_address
      attribute :leader_id
      attribute :name
      attribute :is_open
      attribute :raft
      attribute :ready
      attribute :status

      def self.from_weaviate(data)
        new(
          candidates: data.fetch("candidates", {}),
          db_loaded: data.fetch("dbLoaded", false),
          initial_last_applied_index: data.fetch("initialLastAppliedIndex", 0),
          is_voter: data.fetch("isVoter", false),
          leader_address: data.fetch("leaderAddress", ""),
          leader_id: data.fetch("leaderId", ""),
          name: data.fetch("name", ""),
          is_open: data.fetch("open", false),
          raft: RaftStats.from_weaviate(data.fetch("raft", {})),
          ready: data.fetch("ready", false),
          status: data.fetch("status", "")
        )
      end
    end

    # Response from GET /v1/cluster/statistics (RAFT cluster statistics).
    class ClusterStatistics < ::Weaviate::Model
      attribute :statistics
      attribute :synchronized

      def self.from_weaviate(data)
        new(
          statistics: data.fetch("statistics", []).map { |s| NodeStatistics.from_weaviate(s) },
          synchronized: data.fetch("synchronized", false)
        )
      end
    end

    # --- Nodes (port of weaviate.collections.classes.cluster) ---

    # The properties of a single shard of a collection.
    class Shard < ::Weaviate::Model
      attribute :collection
      attribute :name
      attribute :node
      attribute :object_count
      attribute :vector_indexing_status # "READONLY" | "INDEXING" | "READY" | "LAZY_LOADING"
      attribute :vector_queue_length
      attribute :compressed
      attribute :loaded # not present in <1.24.x
    end

    # The statistics of a collection.
    class Stats < ::Weaviate::Model
      attribute :object_count
      attribute :shard_count
    end

    # The properties of a single node in the cluster. +shards+ / +stats+ are nil for
    # minimal output (NodeMinimal) and populated for verbose output (NodeVerbose).
    class Node < ::Weaviate::Model
      attribute :git_hash
      attribute :name
      attribute :shards
      attribute :stats
      attribute :status
      attribute :version
    end
    NodeVerbose = Node
    NodeMinimal = Node

    # Port of _ConvertFromREST.
    module ConvertFromREST
      module_function

      def nodes_verbose(nodes)
        nodes.map do |node|
          shards =
            if node["shards"].nil?
              []
            else
              node["shards"].map do |shard|
                Shard.new(
                  collection: shard["class"], name: shard["name"], node: node["name"],
                  object_count: shard["objectCount"], vector_indexing_status: shard["vectorIndexingStatus"],
                  vector_queue_length: shard["vectorQueueLength"], compressed: shard["compressed"],
                  loaded: shard["loaded"]
                )
              end
            end
          stats =
            if node.key?("stats")
              Stats.new(object_count: node["stats"]["objectCount"], shard_count: node["stats"]["shardCount"])
            else
              Stats.new(object_count: 0, shard_count: 0)
            end
          Node.new(git_hash: node.fetch("gitHash", "None"), name: node["name"], shards: shards, stats: stats,
                   status: node["status"], version: node.fetch("version", ""))
        end
      end

      def nodes_minimal(nodes)
        nodes.map do |node|
          Node.new(git_hash: node.fetch("gitHash", "None"), name: node["name"], shards: nil, stats: nil,
                   status: node["status"], version: node.fetch("version", ""))
        end
      end
    end
  end
end
