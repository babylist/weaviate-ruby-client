# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_client_debug.py (async variant skipped: sync API only)
RSpec.describe "client debug", :integration do
  config = Weaviate::Classes::Config

  it "test_get_object_single_node" do
    client = client_factory
    collection = collection_factory(properties: [config::Property.new(name: "name", data_type: config::DataType::TEXT)])

    uuid = collection.data.insert({ "name" => "John Doe" })

    debug_obj = client.debug.get_object_over_rest(collection.name, uuid)
    expect(debug_obj).not_to be_nil
    expect(debug_obj).to be_a(Weaviate::Classes::Debug::DebugRESTObject)
    expect(debug_obj.uuid.to_s).to eq(uuid.to_s)

    non_existant_uuid = "00000000-0000-0000-0000-000000000000"
    debug_obj = client.debug.get_object_over_rest(collection.name, non_existant_uuid)
    expect(debug_obj).to be_nil
  end

  it "test_get_object_single_node_async" do
    skip("async client is not ported to Ruby")
  end

  it "test_get_object_multi_node" do
    skip_if_native!("needs the 3-node cluster from the docker-compose stack")

    client = client_factory(ports: [8087, 50_058])
    collection = collection_factory(
      ports: [8087, 50_058], properties: [config::Property.new(name: "name", data_type: config::DataType::TEXT)]
    )

    uuid = collection.data.insert({ "name" => "John Doe" })

    %w[node1 node2 node3].each do |node_name|
      debug_obj = client.debug.get_object_over_rest(collection.name, uuid, node_name: node_name)
      expect(debug_obj).not_to be_nil
      expect(debug_obj.uuid.to_s).to eq(uuid.to_s)
    end
  end
end
