# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_multi_node.py
RSpec.describe "collection multi node", :integration do
  config = Weaviate::Classes::Config
  cl = config::ConsistencyLevel

  [cl::ONE, cl::ALL, cl::QUORUM].each do |level|
    it "test_consistency_on_multinode[#{level}]" do
      skip_if_native!("needs the 3-node cluster from the docker-compose stack")

      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [config::Property.new(name: "name", data_type: config::DataType::TEXT)],
        replication_config: config::Configure.replication(factor: 2, async_enabled: false),
        ports: [8087, 50_058]
      ).with_consistency_level(level)

      collection.data.insert({ "name" => "first" })
      ret = collection.data.insert_many(
        [Weaviate::Classes::Data::DataObject.new(properties: { "name" => "second" }),
         Weaviate::Classes::Data::DataObject.new(properties: { "name" => "third" })]
      )
      expect(ret.has_errors).to be(false)

      objects = collection.query.fetch_objects(
        return_metadata: Weaviate::Classes::Query::MetadataQuery.new(is_consistent: true)
      ).objects
      objects.each { |obj| expect(obj.metadata.is_consistent).to be_truthy }
    end
  end
end
