# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_vectors.py
RSpec.describe "vectors", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }
  let(:exc) { Weaviate::Exceptions }
  let(:data_object) { Weaviate::Classes::Data::DataObject }

  def prop(name, type = cfg::DataType::TEXT) = cfg::Property.new(name: name, data_type: type)

  def contextionary(name, **kw)
    cfg::Configure::Vectors.text2vec_contextionary(name: name, vectorize_collection_name: false, **kw)
  end

  def two_self_provided_collection
    collection_factory(
      properties: [],
      vector_config: [
        cfg::Configure::Vectors.self_provided(name: "first"),
        cfg::Configure::Vectors.self_provided(name: "second")
      ]
    )
  end

  [
    ["list", %w[title content All AllExplicit bringYourOwn bringYourOwn2]],
    ["True", true]
  ].each do |label, include_vector|
    it "test_create_named_vectors[#{label}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = collection_factory(
        properties: [prop("title"), prop("content")],
        vector_config: [
          contextionary("title", source_properties: ["title"]),
          contextionary("content", source_properties: ["content"]),
          contextionary("All"),
          contextionary("AllExplicit", source_properties: %w[title content]),
          cfg::Configure::Vectors.self_provided(name: "bringYourOwn"),
          cfg::Configure::Vectors.self_provided(name: "bringYourOwn2")
        ]
      )

      uuid = collection.data.insert(
        { "title" => "Hello", "content" => "World" },
        vector: { "bringYourOwn" => [0.5, 0.25, 0.75], "bringYourOwn2" => [0.375, 0.625, 0.875] }
      )

      obj = collection.query.fetch_object_by_id(uuid, include_vector: include_vector)
      expect(obj.vector["title"]).not_to be_nil
      expect(obj.vector["content"]).not_to be_nil
      expect(obj.vector["All"]).not_to be_nil
      expect(obj.vector["bringYourOwn"]).to eq([0.5, 0.25, 0.75])
      expect(obj.vector["bringYourOwn2"]).to eq([0.375, 0.625, 0.875])

      # vectorize different data so they must be different
      expect(obj.vector["title"]).not_to eq(obj.vector["content"])
      expect(obj.vector["title"]).not_to eq(obj.vector["All"])

      # vectorize same data so they must be the same
      expect(obj.vector["AllExplicit"]).to eq(obj.vector["All"])
    end
  end

  it "test_insert_many_add" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("title"), prop("content")],
      vector_config: [
        contextionary("title", source_properties: ["title"]),
        cfg::Configure::Vectors.self_provided(name: "bringYourOwn")
      ]
    )

    batch_return = collection.data.insert_many(
      [data_object.new(properties: { "title" => "Hello", "content" => "World" },
                       vector: { "bringYourOwn" => [0.5, 0.25, 0.75] })]
    )
    obj = collection.query.fetch_object_by_id(batch_return.uuids[0], include_vector: %w[title bringYourOwn])
    expect(obj.vector["title"]).not_to be_nil
    expect(obj.vector["bringYourOwn"]).to eq([0.5, 0.25, 0.75])
  end

  it "test_update" do
    collection = collection_factory(
      properties: [prop("title"), prop("content")],
      vector_config: cfg::Configure::Vectors.self_provided(name: "bringYourOwn")
    )

    uuid = collection.data.insert({ "title" => "Hello", "content" => "World" },
                                  vector: { "bringYourOwn" => [0.5, 0.25, 0.75] })
    expect(collection.query.fetch_object_by_id(uuid, include_vector: true).vector["bringYourOwn"])
      .to eq([0.5, 0.25, 0.75])
    collection.data.update(uuid, vector: { "bringYourOwn" => [0.375, 0.625, 0.875] })
    expect(collection.query.fetch_object_by_id(uuid, include_vector: true).vector["bringYourOwn"])
      .to eq([0.375, 0.625, 0.875])
  end

  it "test_replace" do
    collection = collection_factory(
      properties: [prop("title"), prop("content")],
      vector_config: cfg::Configure::Vectors.self_provided(name: "bringYourOwn")
    )

    uuid = collection.data.insert({ "title" => "Hello", "content" => "World" },
                                  vector: { "bringYourOwn" => [0.5, 0.25, 0.75] })
    expect(collection.query.fetch_object_by_id(uuid, include_vector: true).vector["bringYourOwn"])
      .to eq([0.5, 0.25, 0.75])
    collection.data.replace(uuid, properties: { "title" => "Hello", "content" => "World" },
                                  vector: { "bringYourOwn" => [0.375, 0.625, 0.875] })
    expect(collection.query.fetch_object_by_id(uuid, include_vector: true).vector["bringYourOwn"])
      .to eq([0.375, 0.625, 0.875])
  end

  it "test_query" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("title"), prop("content")],
      vector_config: [
        contextionary("title", source_properties: ["title"]),
        contextionary("content", source_properties: ["content"])
      ]
    )

    uuid1 = collection.data.insert({ "title" => "Hello", "content" => "World" })
    uuid2 = collection.data.insert({ "title" => "World", "content" => "Hello" })

    objs = collection.query.near_text("Hello", target_vector: "title", distance: 0.1).objects
    expect(objs[0].uuid).to eq(uuid1)

    objs = collection.query.near_text("Hello", target_vector: "content", distance: 0.1).objects
    expect(objs[0].uuid).to eq(uuid2)
  end

  it "test_generate" do
    collection = openai_collection(name: "dummy")
    skip("Named vectors are not supported in versions lower than 1.24.0") if server_version.is_lower_than(1, 24, 0)
    collection = openai_collection(
      vector_config: [
        cfg::Configure::Vectors.text2vec_openai(name: "text", source_properties: ["text"],
                                                vectorize_collection_name: false),
        cfg::Configure::Vectors.text2vec_openai(name: "content", source_properties: ["content"],
                                                vectorize_collection_name: false)
      ]
    )

    uuid1 = collection.data.insert({ "text" => "Hello", "content" => "World" })
    uuid2 = collection.data.insert({ "text" => "World", "content" => "Hello" })

    prompt = "use {text} and {content} and combine them in a better order separated by whitespace"
    objs = collection.generate.near_text("Hello", target_vector: "text", return_metadata: ["distance"],
                                                  single_prompt: prompt, include_vector: %w[text content]).objects
    expect(objs[0].uuid).to eq(uuid1)
    expect(objs[0].generated).to eq("Hello World")

    objs = collection.generate.near_text("Hello", target_vector: "content", distance: 0.1,
                                                  single_prompt: prompt).objects
    expect(objs[0].uuid).to eq(uuid2)
    expect(objs[0].generated).to eq("Hello World")
  end

  it "test_batch_add" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("title"), prop("content")],
      vector_config: [
        contextionary("title", source_properties: ["title"]),
        cfg::Configure::Vectors.self_provided(name: "bringYourOwn")
      ]
    )
    uuid1 = SecureRandom.uuid

    collection.batch.dynamic do |batch|
      batch.add_object(properties: { "title" => "Hello", "content" => "World" },
                       vector: { "bringYourOwn" => [0.5, 0.25, 0.75] }, uuid: uuid1)
    end

    obj = collection.query.fetch_object_by_id(uuid1, include_vector: %w[title bringYourOwn])
    expect(obj.vector["title"]).not_to be_nil
    expect(obj.vector["bringYourOwn"]).to eq([0.5, 0.25, 0.75])
  end

  it "test_named_vector_with_index_config" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("title"), prop("second")],
      vector_config: [
        contextionary(
          "title",
          source_properties: ["title"],
          vector_index_config: cfg::Configure::VectorIndex.flat(distance_metric: cfg::VectorDistances::HAMMING),
          quantizer: cfg::Configure::VectorIndex::Quantizer.bq(rescore_limit: 10)
        ),
        cfg::Configure::Vectors.self_provided(name: "custom"),
        # vectorize_collection_name: false is needed as contextionary cant handle "_" in collection names
        contextionary("default")
      ]
    )

    config = collection.config.get

    expect(config.vectorizer_config).to be_nil
    expect(config.vectorizer).to be_nil
    expect(config.vector_config).not_to be_nil
    expect(config.vector_config).to have_key("title")
    expect(config.vector_config["title"].vectorizer.vectorizer).to eq(cfg::Vectorizers::TEXT2VEC_CONTEXTIONARY)
    expect(config.vector_config["title"].vectorizer.source_properties).to eq(["title"])
    expect(config.vector_config["title"].vectorizer.model).to eq({ "vectorizeClassName" => false })
    expect(config.vector_config["title"].vector_index_config).to be_a(cfg::VectorIndexConfigFlat)
    expect(config.vector_config["title"].vector_index_config.distance_metric).to eq(cfg::VectorDistances::HAMMING)
    expect(config.vector_config).to have_key("custom")
    expect(config.vector_config["custom"].vectorizer.vectorizer).to eq(cfg::Vectorizers::NONE)
    expect(config.vector_config["custom"].vectorizer.source_properties).to be_nil
    expect(config.vector_config["custom"].vectorizer.model).to eq({})
    expect(config.vector_config).to have_key("default")
    expect(config.vector_config["default"].vectorizer.vectorizer).to eq(cfg::Vectorizers::TEXT2VEC_CONTEXTIONARY)
    expect(config.vector_config["default"].vectorizer.source_properties).to be_nil
    expect(config.vector_config["default"].vectorizer.model).to eq({ "vectorizeClassName" => false })
  end

  it "test_aggregation" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("first"), prop("second"), prop("number", cfg::DataType::INT)],
      vector_config: [
        contextionary("first", source_properties: ["first"]),
        contextionary("second", source_properties: ["second"])
      ]
    )

    collection.data.insert({ "first" => "Hello", "second" => "World", "number" => 1 })
    uuid2 = collection.data.insert({ "first" => "World", "second" => "Hello", "number" => 2 })
    obj2 = collection.query.fetch_object_by_id(uuid2, include_vector: ["second"])
    metrics = Weaviate::Classes::Aggregate::Metrics.new("number").integer
    int_class = Weaviate::Outputs::Aggregate::AggregateInteger

    agg = collection.aggregate.near_text("Hello", target_vector: "first", object_limit: 1, return_metrics: metrics)
    expect(agg.properties["number"]).to be_a(int_class)
    expect(agg.properties["number"].sum_).to eq(1)
    expect(agg.properties["number"].minimum).to eq(1)

    agg = collection.aggregate.near_vector(obj2.vector["second"], target_vector: "second", object_limit: 1,
                                                                  return_metrics: metrics)
    expect(agg.properties["number"]).to be_a(int_class)
    expect(agg.properties["number"].sum_).to eq(2)
    expect(agg.properties["number"].minimum).to eq(2)

    agg = collection.aggregate.near_object(obj2.uuid, target_vector: "second", object_limit: 1,
                                                      return_metrics: metrics)
    expect(agg.properties["number"]).to be_a(int_class)
    expect(agg.properties["number"].sum_).to eq(2)
    expect(agg.properties["number"].minimum).to eq(2)

    agg = collection.aggregate.near_object(obj2.uuid, filters: q::Filter.by_property("number").equal(1),
                                                      target_vector: "second", object_limit: 1,
                                                      return_metrics: metrics)
    expect(agg.properties["number"]).to be_a(int_class)
    expect(agg.properties["number"].sum_).to eq(1)
    expect(agg.properties["number"].minimum).to eq(1)
  end

  it "test_update_to_enable_quantizer_on_specific_named_vector" do
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [prop("first"), prop("second")],
      vector_config: [
        contextionary("first", source_properties: ["first"]),
        contextionary("second", source_properties: ["second"])
      ]
    )
    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    expect(config.vector_config["first"].vector_index_config).not_to be_nil
    expect(config.vector_config["second"].vector_index_config).to be_a(cfg::VectorIndexConfigHNSW)
    expect(config.vector_config["second"].vector_index_config.quantizer).to be_nil

    collection.config.update(
      vector_config: [
        cfg::Reconfigure::Vectors.update(
          name: "second",
          vector_index_config: cfg::Reconfigure::VectorIndex.hnsw(quantizer: cfg::Reconfigure::VectorIndex::Quantizer.pq)
        )
      ]
    )
    config = collection.config.get
    expect(config.vector_config["first"].vector_index_config).not_to be_nil
    expect(config.vector_config["second"].vector_index_config).to be_a(cfg::VectorIndexConfigHNSW)
    expect(config.vector_config["second"].vector_index_config.quantizer).to be_a(cfg::PQConfig)
    expect(config.vector_config["second"].vector_index_config.quantizer.centroids).to eq(256)
  end

  it "test_duplicate_named_vectors" do
    expect do
      collection_factory(
        vector_config: [
          contextionary("title", source_properties: ["title"]),
          contextionary("title", source_properties: ["content"])
        ]
      )
    end.to raise_error(exc::WeaviateInvalidInputError, /Vector config names must be unique. Found duplicates/)
  end

  tv = Weaviate::Classes::Query::TargetVectors
  {
    "list" => -> { %w[first second] },
    "sum" => -> { tv.sum(%w[first second]) },
    "minimum" => -> { tv.minimum(%w[first second]) },
    "average" => -> { tv.average(%w[first second]) },
    "manual_weights" => -> { tv.manual_weights({ "first" => 1.2, "second" => 0.7 }) },
    "relative_score" => -> { tv.relative_score({ "first" => 1.2, "second" => 0.7 }) }
  }.each do |label, target_vector|
    it "test_named_vector_multi_target[#{label}]" do
      collection_factory(name: "dummy")
      skip("Named vectors are not supported in versions lower than 1.26.0") if server_version.is_lower_than(1, 26, 0)

      collection = two_self_provided_collection
      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0, 0], "second" => [0, 1, 0] })
      uuid2 = collection.data.insert({}, vector: { "first" => [0, 1, 0], "second" => [1, 0, 0] })

      objs = collection.query.near_vector([1.0, 0.0, 0.0], target_vector: target_vector.call).objects
      expect(objs.map(&:uuid).sort).to eq([uuid1, uuid2].sort) # order is not guaranteed
    end
  end

  it "test_named_vector_multi_target_vector_per_target" do
    collection_factory(name: "dummy")
    skip("Named vectors are not supported in versions lower than 1.26.0") if server_version.is_lower_than(1, 26, 0)

    collection = two_self_provided_collection
    uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [0, 1, 0] })
    uuid2 = collection.data.insert({}, vector: { "first" => [0, 1], "second" => [1, 0, 0] })

    objs = collection.query.near_vector({ "first" => [1.0, 0.0], "second" => [1.0, 0.0, 0.0] },
                                        target_vector: %w[first second]).objects
    expect(objs.map(&:uuid).sort).to eq([uuid1, uuid2].sort) # order is not guaranteed
  end

  it "test_multi_query_error_no_target_vector" do
    collection_factory(name: "dummy")
    skip("Named vectors are not supported in versions lower than 1.26.0") if server_version.is_lower_than(1, 26, 0)

    collection = two_self_provided_collection

    if server_version.is_lower_than(1, 29, 0)
      # gets checked in the client for validity
      expect { collection.query.near_vector([[1.0, 0.0], [1.0, 0.0, 0.0]]) }
        .to raise_error(exc::WeaviateInvalidInputError)
      expect { collection.query.near_vector([[[1.0, 0.0], [1.0, 0.0]], [1.0, 0.0, 0.0]]) }
        .to raise_error(exc::WeaviateInvalidInputError)
    else
      # throws an error in the server instead as implicit multi vector is understood now as using multi-vectors
      expect { collection.query.near_vector([[1.0, 0.0], [1.0, 0.0, 0.0]]) }.to raise_error(exc::WeaviateQueryError)
    end

    expect { collection.query.near_vector({ "first" => [1.0, 0.0], "second" => [1.0, 0.0, 0.0] }) }
      .to raise_error(exc::WeaviateInvalidInputError)

    expect { collection.query.near_vector({ "first" => [[1.0, 0.0], [1.0, 0.0]], "second" => [1.0, 0.0, 0.0] }) }
      .to raise_error(exc::WeaviateInvalidInputError)
  end

  [
    ["sum", -> { tv.sum(%w[first second]) }, [1, 3]],
    ["manual_weights_1_1", -> { tv.manual_weights({ "first" => 1, "second" => [1, 1] }) }, [1, 3]],
    ["manual_weights_1_2", -> { tv.manual_weights({ "first" => 1, "second" => [1, 2] }) }, [2, 4]],
    # different order
    ["manual_weights_reordered", -> { tv.manual_weights({ "second" => [1, 2], "first" => 1 }) }, [2, 4]]
  ].each do |label, target_vector, distances|
    it "test_same_target_vector_multiple_input[#{label}]" do
      collection_factory(name: "dummy")
      if server_version.is_lower_than(1, 27, 0)
        skip("Multi vector per target is not supported in versions lower than 1.27.0")
      end

      collection = two_self_provided_collection
      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [0, 1, 0] })
      uuid2 = collection.data.insert({}, vector: { "first" => [0, 1], "second" => [1, 0, 0] })

      objs = collection.query.near_vector(
        { "first" => [0.0, 1.0], "second" => [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]] },
        target_vector: target_vector.call,
        return_metadata: q::MetadataQuery.full
      ).objects
      expect(objs.map(&:uuid)).to eq([uuid2, uuid1])
      expect(objs[0].metadata.distance).to eq(distances[0])
      expect(objs[1].metadata.distance).to eq(distances[1])
    end
  end

  nv = Weaviate::Classes::Query::NearVector
  [
    [-> { { "first" => [0, 1], "second" => [[1, 0, 0], [0, 0, 1]] } }, %w[first second]],
    [-> { { "first" => [0, 1], "second" => nv.list_of_vectors([1, 0, 0], [0, 0, 1]) } }, %w[first second]],
    [-> { { "first" => [[0, 1], [0, 1]], "second" => [1, 0, 0] } }, %w[first second]],
    [-> { { "first" => [[0, 1], [0, 1]], "second" => [[1, 0, 0], [0, 0, 1]] } }, %w[first second]],
    [-> { { "first" => [[0, 1], [0, 1]], "second" => [[1, 0, 0], [0, 0, 1]] } }, %w[second first]] # different order
  ].each_with_index do |(near_vector, target_vector), idx|
    it "test_same_target_vector_multiple_input_combinations[#{idx}]" do
      collection_factory(name: "dummy")
      if server_version.is_lower_than(1, 27, 0)
        skip("Multi vector per target is not supported in versions lower than 1.27.0")
      end

      collection = two_self_provided_collection
      uuid1 = collection.data.insert({}, vector: { "first" => [1, 0], "second" => [0, 1, 0] })
      uuid2 = collection.data.insert({}, vector: { "first" => [0, 1], "second" => [1, 0, 0] })

      objs = collection.query.near_vector(near_vector.call, target_vector: target_vector,
                                                            return_metadata: q::MetadataQuery.full).objects
      expect(objs.map(&:uuid).sort).to eq([uuid2, uuid1].sort)
    end
  end

  it "test_deprecated_syntax" do
    collection_factory(name: "dummy")
    if server_version.is_at_least(1, 29, 0) || server_version.is_lower_than(1, 27, 0)
      skip("Syntax was deprecated between 1.27 and 1.29. Now it's allowed for multivector (colbert) searches")
    end

    collection = two_self_provided_collection
    collection.data.insert({}, vector: { "first" => [1, 0], "second" => [0, 1, 0] })
    collection.data.insert({}, vector: { "first" => [0, 1], "second" => [1, 0, 0] })

    expect do
      collection.query.near_vector([[0.0, 1.0], [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0]]],
                                   target_vector: %w[first second second],
                                   return_metadata: q::MetadataQuery.full)
    end.to raise_error(exc::WeaviateInvalidInputError, /This input appears to be a nested list of embeddings./)

    expect do
      collection.query.near_vector([[0.0, 1.0], [1.0, 0.0, 0.0]], target_vector: %w[first second],
                                                                  return_metadata: q::MetadataQuery.full)
    end.to raise_error(exc::WeaviateInvalidInputError, /This input appears to be a nested list of embeddings./)
  end

  [
    ["False", false, {}],
    ["list", ["bringYourOwn1"], { "bringYourOwn1" => [0, 1, 2] }],
    ["True", true, { "bringYourOwn1" => [0, 1, 2], "bringYourOwn2" => [3, 4, 5] }]
  ].each do |label, include_vector, expected|
    it "test_include_vector_on_references[#{label}]" do
      # Test include vector on reference.
      collection_factory
      if server_version.is_lower_than(1, 26, 0)
        skip("https://github.com/weaviate/weaviate/issues/6279 was resolved in >1.26.0 only.")
      end

      ref_collection = collection_factory(
        name: "Target",
        vectorizer_config: [
          cfg::Configure::NamedVectors.none("bringYourOwn1"),
          cfg::Configure::NamedVectors.none("bringYourOwn2")
        ]
      )

      to_uuid = ref_collection.data.insert({}, vector: { "bringYourOwn1" => [0, 1, 2], "bringYourOwn2" => [3, 4, 5] })

      collection = collection_factory(
        name: "Source",
        references: [cfg::ReferenceProperty.new(name: "hasRef", target_collection: ref_collection.name)]
      )

      collection.data.insert({}, references: { "hasRef" => to_uuid })

      objs = collection.query.fetch_objects(
        return_references: q::QueryReference.new(link_on: "hasRef", include_vector: include_vector)
      ).objects

      expect(objs[0].references["hasRef"].objects[0].vector).to eq(expected)
    end
  end

  it "test_colbert_vectors_byov" do
    collection_factory
    skip("ColBERT vectors are only supported in Weaviate v1.29.0 and higher.") if server_version.is_lower_than(1, 29, 0)

    collection = collection_factory(
      properties: [prop("title")],
      vector_config: [
        cfg::Configure::MultiVectors.self_provided(
          name: "colbert",
          multi_vector_config: cfg::Configure::VectorIndex::MultiVector.multi_vector(
            aggregation: cfg::MultiVectorAggregation::MAX_SIM
          )
        ),
        cfg::Configure::Vectors.self_provided(name: "regular")
      ]
    )

    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    expect(config.vector_config["colbert"].vector_index_config).to be_a(cfg::VectorIndexConfigHNSW)
    expect(config.vector_config["colbert"].vector_index_config.multi_vector).to be_a(cfg::MultiVectorConfig)
    expect(config.vector_config["colbert"].vector_index_config.multi_vector.aggregation).to eq("maxSim")

    collection.data.insert_many([data_object.new(properties: {},
                                                 vector: { "regular" => [1, 2], "colbert" => [[1, 2], [4, 5]] })])
    expect(collection.length).to eq(1)

    expect(collection.query.near_vector([1, 2], target_vector: "regular").objects.length).to eq(1)
    expect(collection.query.near_vector([[1, 2], [3, 4]], target_vector: "colbert").objects.length).to eq(1)
    expect(collection.query.near_vector({ "regular" => [[1, 2], [2, 1]] }, target_vector: "regular").objects.length)
      .to eq(1)
    expect(collection.query.near_vector({ "colbert" => [[1, 2], [3, 4]] }, target_vector: "colbert").objects.length)
      .to eq(1)
    expect(
      collection.query.near_vector({ "colbert" => nv.list_of_vectors([[1, 2], [3, 4]]) },
                                   target_vector: "colbert").objects.length
    ).to eq(1)
    expect(collection.query.hybrid(nil, vector: [1, 2], target_vector: "regular").objects.length).to eq(1)
    expect(collection.query.hybrid(nil, vector: [[1, 2], [3, 4]], target_vector: "colbert").objects.length).to eq(1)
    expect(collection.query.hybrid(nil, vector: { "colbert" => [[1, 2], [3, 4]] }, target_vector: "colbert")
                     .objects.length).to eq(1)
    expect(
      collection.query.hybrid(nil, vector: { "colbert" => nv.list_of_vectors([[1, 2], [3, 4]]) },
                                   target_vector: "colbert").objects.length
    ).to eq(1)
  end

  it "test_colbert_vectors_jinaai" do
    api_key = ENV.fetch("JINAAI_APIKEY", nil)
    skip("No JinaAI API key found.") if api_key.nil?

    collection_factory(ports: [8086, 50_057], headers: { "X-Jinaai-Api-Key" => api_key })
    skip("ColBERT vectors are only supported in Weaviate v1.29.0 and higher.") if server_version.is_lower_than(1, 29, 0)

    collection = collection_factory(
      properties: [prop("title")],
      vector_config: [cfg::Configure::MultiVectors.text2vec_jinaai(name: "colbert")]
    )

    uuid = collection.data.insert({ "title" => "Hello World" })
    expect(collection.length).to eq(1)
    obj = collection.query.fetch_object_by_id(uuid, include_vector: ["colbert"])
    vecs = obj.vector["colbert"]
    expect(vecs[0]).to be_a(Array)

    expect(collection.query.near_text("Hello").objects.length).to eq(1)
    expect(collection.query.hybrid("Hello").objects.length).to eq(1)
    shifted = vecs.map { |vec| vec.map { |e| e + 0.01 } }
    expect(collection.query.near_vector({ "colbert" => shifted }, target_vector: "colbert").objects.length).to eq(1)
    expect(collection.query.near_vector(shifted).objects.length).to eq(1)
    expect(collection.query.near_object(uuid).objects.length).to eq(1)
  end
end
