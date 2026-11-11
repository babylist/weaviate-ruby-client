# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_near_vector.py
RSpec.describe "collection near_vector", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }
  let(:exc) { Weaviate::Exceptions }

  def contextionary_collection(properties = [cfg::Property.new(name: "Name", data_type: cfg::DataType::TEXT)])
    collection_factory(
      properties: properties,
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false)
    )
  end

  def first_second_collection
    collection_factory(
      vectorizer_config: [cfg::Configure::NamedVectors.none("first"), cfg::Configure::NamedVectors.none("second")]
    )
  end

  it "test_near_vector" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    banana = collection.query.fetch_object_by_id(uuid_banana, include_vector: true)

    full_objects = collection.query.near_vector(
      banana.vector["default"], return_metadata: q::MetadataQuery.new(distance: true, certainty: true)
    ).objects
    expect(full_objects.length).to eq(4)

    objects_distance = collection.query.near_vector(banana.vector["default"],
                                                    distance: full_objects[2].metadata.distance).objects
    expect(objects_distance.length).to eq(3)

    objects_distance = collection.query.near_vector(banana.vector["default"],
                                                    certainty: full_objects[2].metadata.certainty).objects
    expect(objects_distance.length).to eq(3)
  end

  it "test_near_vector_limit" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    banana = collection.query.fetch_object_by_id(uuid_banana, include_vector: true)

    objs = collection.query.near_vector(banana.vector["default"], limit: 2).objects
    expect(objs.length).to eq(2)
  end

  it "test_near_vector_offset" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    uuid_fruit = collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    banana = collection.query.fetch_object_by_id(uuid_banana, include_vector: true)

    objs = collection.query.near_vector(banana.vector["default"], offset: 1).objects
    expect(objs.length).to eq(3)
    expect(objs[0].uuid).to eq(uuid_fruit)
  end

  it "test_near_vector_group_by_argument" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection(
      [cfg::Property.new(name: "Name", data_type: cfg::DataType::TEXT),
       cfg::Property.new(name: "Count", data_type: cfg::DataType::INT)]
    )
    uuid_banana1 = collection.data.insert({ "Name" => "Banana", "Count" => 51 })
    collection.data.insert({ "Name" => "Banana", "Count" => 72 })
    collection.data.insert({ "Name" => "car", "Count" => 12 })
    collection.data.insert({ "Name" => "Mountain", "Count" => 1 })

    banana1 = collection.query.fetch_object_by_id(uuid_banana1, include_vector: true)

    ret = collection.query.near_vector(
      banana1.vector["default"],
      group_by: q::GroupBy.new(prop: "name", number_of_groups: 4, objects_per_group: 10),
      return_metadata: q::MetadataQuery.new(distance: true, certainty: true)
    )

    expect(ret.objects.length).to eq(4)
    expect(ret.objects[0].belongs_to_group).to eq("Banana")
    expect(ret.objects[1].belongs_to_group).to eq("Banana")
    expect(ret.objects[2].belongs_to_group).to eq("car")
    expect(ret.objects[3].belongs_to_group).to eq("Mountain")
  end

  # numpy / polars / pandas inputs are represented by a non-Array list-like (Batch4Helpers::ArrayLike).
  {
    "ints" => -> { [1, 0] },
    "floats" => -> { [1.0, 0.0] },
    "np.array" => -> { Batch4Helpers.array_like([1, 0]) },
    "pl.Series" => -> { Batch4Helpers.array_like([1, 0]) },
    "pd.Series" => -> { Batch4Helpers.array_like([1, 0]) }
  }.each do |label, near_vector|
    it "test_near_vector_with_other_input[#{label}]" do
      collection = collection_factory(vectorizer_config: cfg::Configure::Vectorizer.none)

      uuid1 = collection.data.insert({}, vector: [1, 0])
      collection.data.insert({}, vector: [0, 1])

      ret = collection.query.near_vector(near_vector.call, distance: 0.1)
      expect(ret.objects.length).to eq(1)
      expect(ret.objects[0].uuid).to eq(uuid1)
    end
  end

  {
    "ints" => -> { { "first" => [1, 0], "second" => [1, 0, 0] } },
    "np.array" => -> { { "first" => Batch4Helpers.array_like([1, 0]), "second" => [1, 0, 0] } },
    "pl.Series" => -> { { "first" => Batch4Helpers.array_like([1, 0]), "second" => [1, 0, 0] } },
    "pd.Series" => -> { { "first" => Batch4Helpers.array_like([1, 0]), "second" => [1, 0, 0] } },
    "floats" => -> { { "first" => [1.0, 0.0], "second" => [1.0, 0.0, 0.0] } }
  }.each do |label, near_vector|
    it "test_near_vector_with_named_vector_other_input[#{label}]" do
      collection_factory(name: "dummy")
      skip("Named vectors are supported in versions higher than 1.26.0") if server_version.is_lower_than(1, 26, 0)

      collection = first_second_collection

      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [1, 0, 0] })
      collection.data.insert({}, vector: { "first" => [0, 1], "second" => [0, 0, 1] })

      ret = collection.query.near_vector(near_vector.call, distance: 0.1, target_vector: %w[first second])
      expect(ret.objects.length).to eq(1)
      expect(ret.objects[0].uuid).to eq(uuid1)
    end
  end

  it "test_near_vector_with_extra_vectors" do
    collection_factory(name: "dummy")
    skip("Named vectors are supported in versions higher than 1.26.0") if server_version.is_lower_than(1, 26, 0)

    collection = first_second_collection

    collection.data.insert({}, vector: { "first" => [1, 0], "second" => [1, 0, 0] })
    expect do
      collection.query.near_vector({ "first" => [1, 0], "second" => [1, 0, 0] }, target_vector: ["second"])
    end.to raise_error(exc::WeaviateInvalidInputError)
  end
end
