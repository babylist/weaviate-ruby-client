# frozen_string_literal: true

# Port of test/test_cluster_models.py
RSpec.describe Weaviate::Outputs::Replication::ReplicateOperationStatus do
  [
    [["legacy error"], ["legacy error"]],
    [[{ "message" => "structured error", "whenErroredUnixMs" => 123 }], ["structured error"]],
    [[{ "whenErroredUnixMs" => 123 }], [""]],
    [[], []],
    [nil, []],
    [
      ["legacy error", { "message" => "structured error", "whenErroredUnixMs" => 123 }, { "whenErroredUnixMs" => 456 }],
      ["legacy error", "structured error", ""]
    ]
  ].each_with_index do |(errors, expected), i|
    it "test_replicate_operation_status_parses_error_messages[#{i}]" do
      status = described_class.from_weaviate(
        { "state" => Weaviate::Outputs::Replication::ReplicateOperationState::CANCELLED, "errors" => errors }
      )

      expect(status.errors).to eq(expected)
    end
  end
end

RSpec.describe Weaviate::Cluster::ConvertFromREST do
  it "fills verbose defaults for nodes without shards or stats" do
    nodes = described_class.nodes_verbose([{ "status" => "TIMEOUT", "shards" => nil, "name" => "node1" }])
    expect(nodes.first).to eq(
      Weaviate::Outputs::Cluster::Node.new(
        git_hash: "None", name: "node1", shards: [],
        stats: Weaviate::Outputs::Cluster::Stats.new(object_count: 0, shard_count: 0), status: "TIMEOUT", version: ""
      )
    )
  end

  it "parses verbose shards" do
    nodes = described_class.nodes_verbose(
      [{ "name" => "n", "status" => "HEALTHY", "version" => "1.30.0", "gitHash" => "abc",
         "stats" => { "objectCount" => 3, "shardCount" => 1 },
         "shards" => [{ "class" => "C", "name" => "s1", "objectCount" => 3, "vectorIndexingStatus" => "READY",
                        "vectorQueueLength" => 0, "compressed" => false, "loaded" => true }] }]
    )
    expect(nodes.first.shards.first).to eq(
      Weaviate::Outputs::Cluster::Shard.new(collection: "C", name: "s1", node: "n", object_count: 3,
                                            vector_indexing_status: "READY", vector_queue_length: 0,
                                            compressed: false, loaded: true)
    )
    expect(nodes.first.stats.object_count).to eq(3)
  end
end
