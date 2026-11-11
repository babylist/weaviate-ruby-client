# frozen_string_literal: true

# Extra fixtures for the ported references / filter / nested / batch integration specs
# (collection_factory_get from integration/conftest.py, batch_collection from test_collection_batch.py
# and the client_factory of test_batch_v4.py). Include with `include Batch3Helpers`.
module Batch3Helpers
  # Python's numpy/torch/tensorflow/pandas test doubles: Ruby accepts any object responding to `to_a`
  # (e.g. Numo::NArray) as a vector.
  MockArrayLike = Struct.new(:array) do
    def to_a = array
  end

  # conftest.collection_factory_get: a handle to an (existing or not) collection by name.
  def collection_factory_get(name, skip_argument_validation: false)
    name = name.gsub(/[\[\]\- .]/, "")
    name = name[0].upcase + name[1..]
    client_factory.collections.use(name, skip_argument_validation: skip_argument_validation)
  end

  # test_collection_batch.batch_collection fixture.
  def batch_collection(name: "", multi_tenancy: false)
    config = Weaviate::Classes::Config
    collection = collection_factory(
      name: name,
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [
        config::Property.new(name: "name", data_type: config::DataType::TEXT),
        config::Property.new(name: "age", data_type: config::DataType::INT)
      ],
      multi_tenancy_config: config::Configure.multi_tenancy(enabled: multi_tenancy)
    )
    collection.config.add_reference(config::ReferenceProperty.new(name: "test", target_collection: collection.name))
    collection
  end

  # test_batch_v4.client_factory fixture: returns [client, name] of a fresh collection with the
  # "name"/"age" properties and a self reference "test".
  def batch_client_factory(name: "", ports: [8080, 50_051], multi_tenant: false)
    config = Weaviate::Classes::Config
    client = client_factory(ports: ports)
    name_fixture = IntegrationContext.sanitize_collection_name(
      "#{File.basename(RSpec.current_example.file_path, ".rb")}_#{RSpec.current_example.description}"
    )[0, 100] + name
    client.collections.delete(name_fixture) if client.collections.exists(name_fixture)
    integration_collections << [client, name_fixture]
    client.collections.create(
      name_fixture,
      properties: [
        config::Property.new(name: "name", data_type: config::DataType::TEXT),
        config::Property.new(name: "age", data_type: config::DataType::INT)
      ],
      references: [config::ReferenceProperty.new(name: "test", target_collection: name_fixture)],
      multi_tenancy_config: config::Configure.multi_tenancy(enabled: multi_tenant),
      vectorizer_config: config::Configure::Vectorizer.none
    )
    [client, name_fixture]
  end

  # Ruby UUIDs are Strings; Python's `uuid.UUID(...).hex` is the 32-char form without dashes.
  def uuid_hex(uuid) = uuid.delete("-")

  def random_uuid = SecureRandom.uuid
end
