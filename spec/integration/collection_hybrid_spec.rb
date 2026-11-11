# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_hybrid.py
RSpec.describe "collection hybrid", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }
  let(:exc) { Weaviate::Exceptions }

  def prop(name, type = cfg::DataType::TEXT) = cfg::Property.new(name: name, data_type: type)

  def contextionary_collection(name_prop = "Name")
    collection_factory(
      properties: [prop(name_prop)],
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false)
    )
  end

  def named_contextionary_collection
    collection_factory(
      properties: [prop("text"), prop("int", cfg::DataType::INT)],
      vectorizer_config: [
        cfg::Configure::NamedVectors.text2vec_contextionary(name: "text", vectorize_collection_name: false),
        cfg::Configure::NamedVectors.text2vec_contextionary(name: "int", vectorize_collection_name: false)
      ]
    )
  end

  def first_second_collection
    collection_factory(
      properties: [],
      vectorizer_config: [cfg::Configure::NamedVectors.none("first"), cfg::Configure::NamedVectors.none("second")]
    )
  end

  [Weaviate::Classes::Query::HybridFusion::RANKED, Weaviate::Classes::Query::HybridFusion::RELATIVE_SCORE]
    .each do |fusion_type|
    it "test_search_hybrid[#{fusion_type}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      collection.data.insert({ "Name" => "some name" }, uuid: SecureRandom.uuid)
      collection.data.insert({ "Name" => "other word" }, uuid: SecureRandom.uuid)
      objs = collection.query.hybrid("name", alpha: 0, fusion_type: fusion_type, include_vector: true).objects
      expect(objs.length).to eq(1)

      objs = collection.query.hybrid("name", alpha: 1, fusion_type: fusion_type,
                                             vector: objs[0].vector["default"]).objects
      expect(objs.length).to eq(2)
    end
  end

  it "test_search_hybrid_group_by" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    collection.data.insert({ "Name" => "some name" }, uuid: SecureRandom.uuid)
    collection.data.insert({ "Name" => "other word" }, uuid: SecureRandom.uuid)
    objs = collection.query.hybrid(
      "name", alpha: 0, include_vector: true,
              group_by: q::GroupBy.new(prop: "name", objects_per_group: 1, number_of_groups: 2)
    ).objects
    expect(objs.length).to eq(1)
    expect(objs[0].belongs_to_group).to eq("some name")
  end

  [nil, ""].each do |query|
    it "test_search_hybrid_only_vector[#{query.inspect}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      uuid_ = collection.data.insert({ "Name" => "some name" }, uuid: SecureRandom.uuid)
      vec = collection.query.fetch_object_by_id(uuid_, include_vector: true).vector
      expect(vec).not_to be_nil

      collection.data.insert({ "Name" => "other word" }, uuid: SecureRandom.uuid)

      objs = collection.query.hybrid(query, alpha: 1, vector: vec["default"]).objects
      expect(objs.length).to eq(2)
    end
  end

  [1, 2].each do |limit|
    it "test_hybrid_limit[#{limit}]" do
      collection = collection_factory(properties: [prop("Name")], vectorizer_config: cfg::Configure::Vectorizer.none)
      res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
      expect(res.has_errors).to be(false)
      expect(collection.query.hybrid("test", alpha: 0, limit: limit).objects.length).to eq(limit)
    end
  end

  [[0, 2], [1, 1], [2, 0]].each do |offset, expected|
    it "test_hybrid_offset[#{offset}-#{expected}]" do
      collection = collection_factory(properties: [prop("Name")], vectorizer_config: cfg::Configure::Vectorizer.none)
      res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
      expect(res.has_errors).to be(false)

      expect(collection.query.hybrid("test", alpha: 0, offset: offset).objects.length).to eq(expected)
    end
  end

  it "test_hybrid_alpha" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection("name")

    res = collection.data.insert_many([{ "name" => "banana" }, { "name" => "fruit" }, { "name" => "car" }])
    expect(res.has_errors).to be(false)

    hybrid_res = collection.query.hybrid("fruit", alpha: 0)
    bm25_res = collection.query.bm25("fruit")
    hybrid_res.objects.each_index do |i|
      expect(bm25_res.objects[i].uuid).to eq(hybrid_res.objects[i].uuid)
    end

    hybrid_res = collection.query.hybrid("fruit", alpha: 1)
    text_res = collection.query.near_text("fruit")
    hybrid_res.objects.each_index do |i|
      expect(text_res.objects[i].uuid).to eq(hybrid_res.objects[i].uuid)
    end
  end

  it "test_hybrid_near_vector_search" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection("text")
    uuid_banana = collection.data.insert({ "text" => "banana" })
    obj = collection.query.fetch_object_by_id(uuid_banana, include_vector: true)

    if server_version.is_lower_than(1, 25, 0)
      expect do
        collection.query.hybrid(nil, vector: q::HybridVector.near_vector(obj.vector["default"])).objects
      end.to raise_error(exc::WeaviateUnsupportedFeatureError)
      next
    end

    collection.data.insert({ "text" => "dog" })
    collection.data.insert({ "text" => "different concept" })

    hybrid_objs = collection.query.hybrid(nil, vector: q::HybridVector.near_vector(obj.vector["default"])).objects

    expect(hybrid_objs[0].uuid).to eq(uuid_banana)
    expect(hybrid_objs.length).to eq(3)

    # make a near vector search to get the distance
    near_vec = collection.query.near_vector(obj.vector["default"], return_metadata: ["distance"]).objects
    expect(near_vec[0].metadata.distance).not_to be_nil

    hybrid_objs2 = collection.query.hybrid(
      nil,
      vector: q::HybridVector.near_vector(obj.vector["default"], distance: near_vec[0].metadata.distance + 0.001),
      return_metadata: q::MetadataQuery.full
    ).objects

    expect(hybrid_objs2[0].uuid).to eq(uuid_banana)
    expect(hybrid_objs2.length).to eq(1)
  end

  it "test_hybrid_near_vector_search_named_vectors" do
    skip_if_native!("requires text2vec-contextionary")
    collection = named_contextionary_collection

    uuid_banana = collection.data.insert({ "text" => "banana" })
    collection.data.insert({ "text" => "dog" })
    collection.data.insert({ "text" => "different concept" })

    obj = collection.query.fetch_object_by_id(uuid_banana, include_vector: true)

    if server_version.is_lower_than(1, 25, 0)
      expect do
        collection.query.hybrid(nil, vector: q::HybridVector.near_vector(obj.vector["text"]),
                                     target_vector: "text").objects
      end.to raise_error(exc::WeaviateUnsupportedFeatureError)
      next
    end

    hybrid_objs = collection.query.hybrid(nil, vector: q::HybridVector.near_vector(obj.vector["text"]),
                                               target_vector: "text").objects

    expect(hybrid_objs[0].uuid).to eq(uuid_banana)
    expect(hybrid_objs.length).to eq(3)

    # make a near vector search to get the distance
    near_vec = collection.query.near_vector(obj.vector["text"], return_metadata: ["distance"],
                                                                target_vector: "text").objects
    expect(near_vec[0].metadata.distance).not_to be_nil

    hybrid_objs2 = collection.query.hybrid(
      nil,
      vector: q::HybridVector.near_vector(obj.vector["text"], distance: near_vec[0].metadata.distance + 0.001),
      target_vector: "text",
      return_metadata: q::MetadataQuery.full
    ).objects

    expect(hybrid_objs2[0].uuid).to eq(uuid_banana)
    expect(hybrid_objs2.length).to eq(1)
  end

  it "test_hybrid_near_text_search" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection("text")

    if server_version.is_lower_than(1, 25, 0)
      expect do
        collection.query.hybrid(nil, vector: q::HybridVector.near_text("banana pudding")).objects
      end.to raise_error(exc::WeaviateUnsupportedFeatureError)
      next
    end

    uuid_banana_pudding = collection.data.insert({ "text" => "banana pudding" })
    collection.data.insert({ "text" => "banana smoothie" })
    collection.data.insert({ "text" => "different concept" })

    hybrid_objs = collection.query.hybrid(nil, vector: q::HybridVector.near_text("banana pudding")).objects

    expect(hybrid_objs[0].uuid).to eq(uuid_banana_pudding)
    expect(hybrid_objs.length).to eq(3)

    hybrid_objs2 = collection.query.hybrid(
      nil,
      vector: q::HybridVector.near_text(
        "banana",
        move_to: q::Move.new(concepts: "pudding", force: 0.1),
        move_away: q::Move.new(concepts: "smoothie", force: 0.1)
      ),
      return_metadata: q::MetadataQuery.full
    ).objects

    expect(hybrid_objs2[0].uuid).to eq(uuid_banana_pudding)
  end

  it "test_hybrid_near_text_search_named_vectors" do
    skip_if_native!("requires text2vec-contextionary")
    collection = named_contextionary_collection

    uuid_banana_pudding = collection.data.insert({ "text" => "banana pudding" })
    collection.data.insert({ "text" => "banana smoothie" })
    collection.data.insert({ "text" => "different concept" })

    if server_version.is_lower_than(1, 25, 0)
      expect do
        collection.query.hybrid(nil, vector: q::HybridVector.near_text("banana pudding"), target_vector: "text").objects
      end.to raise_error(exc::WeaviateUnsupportedFeatureError)
      next
    end

    hybrid_objs = collection.query.hybrid(nil, vector: q::HybridVector.near_text("banana pudding"),
                                               target_vector: "text").objects

    expect(hybrid_objs[0].uuid).to eq(uuid_banana_pudding)
    expect(hybrid_objs.length).to eq(3)

    hybrid_objs2 = collection.query.hybrid(
      nil,
      vector: q::HybridVector.near_text(
        "banana",
        move_to: q::Move.new(concepts: "pudding", force: 0.1),
        move_away: q::Move.new(concepts: "smoothie", force: 0.1)
      ),
      target_vector: "text",
      return_metadata: q::MetadataQuery.full
    ).objects

    expect(hybrid_objs2[0].uuid).to eq(uuid_banana_pudding)
  end

  # numpy / polars / pandas inputs are represented by a non-Array list-like (Batch4Helpers::ArrayLike).
  {
    "list" => -> { { "first" => [1, 0], "second" => [1, 0, 0] } },
    "np.array" => -> { { "first" => [1, 0], "second" => Batch4Helpers.array_like([1, 0, 0]) } },
    "pl.Series" => -> { { "first" => [1, 0], "second" => Batch4Helpers.array_like([1, 0, 0]) } },
    "pd.Series" => -> { { "first" => [1, 0], "second" => Batch4Helpers.array_like([1, 0, 0]) } }
  }.each do |label, vector|
    it "test_vector_per_target[#{label}]" do
      collection_factory(name: "dummy")
      skip("No multi target search below 1.26") if server_version.is_lower_than(1, 26, 0)

      collection = first_second_collection

      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [1, 0, 0] })
      uuid2 = collection.data.insert({}, vector: { "first" => [0, 1], "second" => [0, 0, 1] })

      objs = collection.query.hybrid(nil, vector: vector.call, target_vector: %w[first second]).objects
      expect(objs.length).to eq(2)
      expect(objs[0].uuid).to eq(uuid1)
      expect(objs[1].uuid).to eq(uuid2)

      objs = collection.query.hybrid(nil, vector: q::HybridVector.near_vector(vector.call, distance: 0.1),
                                          target_vector: %w[first second]).objects
      expect(objs.length).to eq(1)
      expect(objs[0].uuid).to eq(uuid1)
    end
  end

  hv = Weaviate::Classes::Query::HybridVector
  [
    -> { { "first" => [0, 1], "second" => [[1, 0, 0], [0, 0, 1]] } },
    -> { { "first" => [[0, 1], [0, 1]], "second" => [1, 0, 0] } },
    -> { { "first" => [[0, 1], [0, 1]], "second" => [[1, 0, 0], [0, 0, 1]] } },
    -> { hv.near_vector({ "first" => [0, 1], "second" => [[1, 0, 0], [0, 0, 1]] }) },
    -> { hv.near_vector({ "first" => [[0, 1], [0, 1]], "second" => [1, 0, 0] }) },
    -> { hv.near_vector({ "first" => [[0, 1], [0, 1]], "second" => [[1, 0, 0], [0, 0, 1]] }) }
  ].each_with_index do |near_vector, idx|
    it "test_same_target_vector_multiple_input_combinations[#{idx}]" do
      collection_factory(name: "dummy")
      if server_version.is_lower_than(1, 27, 0)
        skip("Multi vector per target is not supported in versions lower than 1.27.0")
      end

      collection = first_second_collection

      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [0, 1, 0] })
      uuid2 = collection.data.insert({}, vector: { "first" => [0, 1], "second" => [1, 0, 0] })

      objs = collection.query.hybrid(nil, vector: near_vector.call, target_vector: %w[first second],
                                          return_metadata: q::MetadataQuery.full).objects
      expect(objs.map(&:uuid).sort).to eq([uuid2, uuid1].sort)
    end
  end

  it "test_vector_distance" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection("name")

    if server_version.is_lower_than(1, 26, 3)
      skip("Hybrid max vector distance is only supported in versions higher than 1.26.3")
    end

    uuid1 = collection.data.insert({}, vector: [1, 0, 0])
    collection.data.insert({}, vector: [0, 1, 0])
    collection.data.insert({}, vector: [0, 0, 1])

    objs = collection.query.hybrid("name", vector: [1, 0, 0])
    expect(objs.objects.length).to eq(3)
    expect(objs.objects[0].uuid).to eq(uuid1)

    objs = collection.query.hybrid("name", vector: [1, 0, 0], max_vector_distance: 0.1)
    expect(objs.objects.length).to eq(1)
    expect(objs.objects[0].uuid).to eq(uuid1)
  end

  it "test_aggregate_max_vector_distance" do
    collection = collection_factory(properties: [prop("name")], vectorizer_config: cfg::Configure::Vectorizer.none)

    if server_version.is_lower_than(1, 26, 3)
      skip("Hybrid max vector distance is only supported in versions higher than 1.26.3")
    end

    collection.data.insert({ "name" => "banana one" }, vector: [1, 0, 0, 0])
    collection.data.insert({ "name" => "banana two" }, vector: [0, 1, 0, 0])
    collection.data.insert({ "name" => "banana three" }, vector: [0, 1, 0, 0])
    collection.data.insert({ "name" => "banana four" }, vector: [1, 0, 0, 0])

    res = collection.aggregate.hybrid(
      "banana",
      vector: [1, 0, 0, 0],
      max_vector_distance: 0.5,
      return_metrics: [Weaviate::Classes::Aggregate::Metrics.new("name").text(count: true)]
    )
    expect(res.total_count).to eq(2)
  end

  it "test_hybrid_bm25_operators" do
    collection = collection_factory(properties: [prop("name")], vectorizer_config: cfg::Configure::Vectorizer.none)

    skip("bm25 operators are only supported in versions higher than 1.31.0") if server_version.is_lower_than(1, 31, 0)

    uuid1 = collection.data.insert({ "name" => "banana one" }, vector: [1, 0, 0, 0])
    uuid2 = collection.data.insert({ "name" => "banana two" }, vector: [0, 1, 0, 0])
    uuid3 = collection.data.insert({ "name" => "banana three" }, vector: [0, 1, 0, 0])
    uuid4 = collection.data.insert({ "name" => "banana four" }, vector: [1, 0, 0, 0])

    objs = collection.query.hybrid("banana two", vector: nil, alpha: 0.0,
                                                 bm25_operator: q::BM25Operator.or_(minimum_match: 1))
    expect(objs.objects.length).to eq(4)
    expect(objs.objects[0].uuid).to eq(uuid2)
    expect(objs.objects[1..].map(&:uuid).sort).to eq([uuid1, uuid3, uuid4].sort)
  end
end
