# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_replicate.py.
#
# Every test needs the multi-node docker-compose cluster on (8087, 50058); they are skipped in
# native mode (client_factory skips non-default ports).
module Batch5Specs
  RSpec.describe "replicate", :integration do
    include Batch5Helpers

    ports = [8087, 50_058]
    names = %w[
      Alice Bob Charlie David Eve Frank Grace Heidi Ivan Judy Karl Leo Mallory Nina Oscar Peggy Quentin
      Rupert Sybil Trent Uma Victor Walter Xena Yara Zane
    ]

    let(:ports) { ports }
    # Python's `replicate_client` fixture (shares the client_factory client with collection_factory).
    let(:replicate_client) { client_factory(ports: ports) }

    define_method(:replicate_collection) do
      collection_factory(name: "dummy", ports: ports)
      skip_unless_version!(client_factory(ports: ports), 1, 32, 0, "Replication operations")

      collection = collection_factory(
        properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)],
        ports: ports,
        replication_config: Config::Configure.replication(factor: 1)
      )
      sleep(1) # wait of eventual consistency of collection creation
      collection.data.insert_many(names.map { |name| { "name" => name } })
      collection
    end

    # Cleanup any existing replication operations before running tests.
    def cleanup_ops(replicate_client)
      replicate_client.cluster.replications.delete_all
      sleep(0.1) while replicate_client.cluster.replications.list_all.length.positive?
    end

    def replicate_first_shard(collection)
      nodes = replicate_client.cluster.nodes(collection: collection.name, output: "verbose")
      src_node = nodes[0].name
      tgt_node = nodes[1].name
      shard = nodes[0].shards[0].name

      cleanup_ops(replicate_client)
      op_id = replicate_client.cluster.replicate(collection: collection.name, shard: shard, source_node: src_node,
                                                 target_node: tgt_node)
      [op_id, src_node, tgt_node, shard]
    end

    it "test_replicate_and_get" do
      collection = replicate_collection
      op_id, src_node, tgt_node, shard = replicate_first_shard(collection)

      op1 = replicate_client.cluster.replications.get(uuid: op_id)

      expect(op1).not_to be_nil
      expect(op1.collection).to eq(collection.name)
      expect(op1.shard).to eq(shard)
      expect(op1.source_node).to eq(src_node)
      expect(op1.target_node).to eq(tgt_node)
      expect(op1.transfer_type).to eq(Weaviate::Classes::Replication::ReplicationType::COPY)
      expect(op1.status).not_to be_nil
      expect(op1.status_history).to be_nil

      op2 = replicate_client.cluster.replications.get(uuid: op_id, include_history: true)

      expect(op2).not_to be_nil
      expect(op2.collection).to eq(collection.name)
      expect(op2.shard).to eq(shard)
      expect(op2.source_node).to eq(src_node)
      expect(op2.target_node).to eq(tgt_node)
      expect(op2.transfer_type).to eq(Weaviate::Classes::Replication::ReplicationType::COPY)
      expect(op2.status).not_to be_nil
      expect(op2.status_history).not_to be_nil
    end

    it "test_replicate_and_cancel" do
      collection = replicate_collection
      op_id, = replicate_first_shard(collection)

      replicate_client.cluster.replications.cancel(uuid: op_id)

      start = Time.now
      until replicate_client.cluster.replications.get(uuid: op_id).status.state ==
            Weaviate::Outputs::Replication::ReplicateOperationState::CANCELLED
        sleep(0.1)
        raise "Timed out waiting for replication operation to be cancelled" if Time.now - start > 10
      end
    end

    it "test_replicate_and_delete" do
      collection = replicate_collection
      op_id, = replicate_first_shard(collection)

      replicate_client.cluster.replications.delete(uuid: op_id)

      start = Time.now
      until replicate_client.cluster.replications.get(uuid: op_id).nil?
        sleep(0.1)
        raise "Timed out waiting for replication operation to be deleted" if Time.now - start > 10
      end
    end

    it "test_replicate_and_query" do
      collection = replicate_collection
      _, src_node, tgt_node, shard = replicate_first_shard(collection)

      ops = replicate_client.cluster.replications.query(collection: collection.name, shard: shard,
                                                        target_node: tgt_node)
      expect(ops.length).to eq(1)

      ops = replicate_client.cluster.replications.query(collection: collection.name, shard: shard,
                                                        target_node: src_node)
      expect(ops.length).to eq(1)

      ops = replicate_client.cluster.replications.list_all
      expect(ops.length).to eq(1)
    end

    it "test_query_sharding_state" do
      collection = replicate_collection

      nodes = replicate_client.cluster.nodes(collection: collection.name, output: "verbose")
      shard = nodes[0].shards[0].name

      sharding_state = replicate_client.cluster.query_sharding_state(collection: collection.name)
      expect(sharding_state).not_to be_nil
      expect(sharding_state.shards.map(&:name)).to include(shard)

      sharding_state = replicate_client.cluster.query_sharding_state(collection: collection.name, shard: shard)
      expect(sharding_state).not_to be_nil
      expect(sharding_state.shards.map(&:name)).to include(shard)

      expect(replicate_client.cluster.query_sharding_state(collection: "non_existent_collection")).to be_nil
      expect(
        replicate_client.cluster.query_sharding_state(collection: collection.name, shard: "non_existent_shard")
      ).to be_nil
    end
  end
end
