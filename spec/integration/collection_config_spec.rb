# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_config.py
RSpec.describe "collection config", :integration do # rubocop:disable RSpec/DescribeClass
  include CollectionConfigBatchHelpers

  c = Weaviate::Classes::Config
  configure = c::Configure
  reconfigure = c::Reconfigure
  property = c::Property
  data_type = c::DataType
  day = 86_400 # Python datetime.timedelta values are Integer seconds in Ruby

  def version = client_factory.connection.weaviate_version

  # Python's module-level `client` fixture connects to the cluster on port 8087 only to isolate its
  # `delete_all()`; here it is the (dedicated) main instance.
  let(:client) { client_factory }

  it "test_collections_list" do
    client.collections.create("TestCollectionsList", vectorizer_config: configure::Vectorizer.none)

    collections = client.collections.list_all
    expect(collections.keys).to include("TestCollectionsList")
    expect(collections["TestCollectionsList"]).to be_a(c::CollectionConfigSimple)

    collection = client.collections.list_all(simple: false)
    expect(collections.keys).to include("TestCollectionsList")
    expect(collection["TestCollectionsList"]).to be_a(c::CollectionConfig)
  ensure
    client.collections.delete("TestCollectionsList")
  end

  it "test_collection_get_simple" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)]
    )

    config = collection.config.get(simple: true)
    expect(config).to be_a(c::CollectionConfigSimple)
  end

  it "test_collection_vectorizer_config" do
    skip_unless_modules!(client, "text2vec-contextionary")
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false),
      properties: [
        property.new(name: "name", data_type: data_type::TEXT),
        property.new(name: "age", data_type: data_type::INT, skip_vectorization: true, vectorize_property_name: false)
      ]
    )

    config = collection.config.get(simple: true)

    expect(config.properties[0].vectorizer).to eq("text2vec-contextionary")
    expect(config.properties[0].vectorizer_config).not_to be_nil
    expect(config.properties[0].vectorizer_config.skip).to be(false)
    expect(config.properties[0].vectorizer_config.vectorize_property_name).to be(true)
    expect(config.properties[1].vectorizer).to eq("text2vec-contextionary")
    expect(config.properties[1].vectorizer_config).not_to be_nil
    expect(config.properties[1].vectorizer_config.skip).to be(true)
    expect(config.properties[1].vectorizer_config.vectorize_property_name).to be(false)

    expect(config.vectorizer_config).not_to be_nil
    expect(config.vectorizer_config.vectorize_collection_name).to be(false)
    expect(config.vectorizer_config.model).to eq({})
  end

  it "test_collection_generative_config" do
    collection = openai_collection(vectorizer_config: configure::Vectorizer.none)

    config = collection.config.get

    expect(config.properties[0].vectorizer).to eq("none")
    expect(config.generative_config).not_to be_nil
    expect(config.generative_config.generative).to eq(c::GenerativeSearches::OPENAI)
    expect(config.generative_config.model).not_to be_nil
  end

  it "test_collection_config_empty" do
    collection = collection_factory
    config = collection.config.get

    expect(config.name).to eq(collection.name)
    expect(config.description).to be_nil
    expect(config.vectorizer).to eq(c::Vectorizers::NONE)

    expect(config.properties).to eq([])

    expect(config.inverted_index_config.bm25.b).to eq(0.75)
    expect(config.inverted_index_config.bm25.k1).to eq(1.2)
    expect(config.inverted_index_config.cleanup_interval_seconds).to eq(60)
    expect(config.inverted_index_config.index_timestamps).to be(false)
    expect(config.inverted_index_config.index_property_length).to be(false)
    expect(config.inverted_index_config.index_null_state).to be(false)
    expect(config.inverted_index_config.stopwords.additions).to be_nil
    expect(config.inverted_index_config.stopwords.preset).to eq(c::StopwordsPreset::EN)
    expect(config.inverted_index_config.stopwords.removals).to be_nil

    expect(config.multi_tenancy_config.enabled).to be(false)

    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(false)

    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(300)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(8)
    expect(config.vector_index_config.dynamic_ef_max).to eq(500)
    expect(config.vector_index_config.dynamic_ef_min).to eq(100)
    expect(config.vector_index_config.ef).to eq(-1)
    expect(config.vector_index_config.ef_construction).to eq(128)
    expect(config.vector_index_config.flat_search_cutoff).to eq(40_000)
    if version.is_lower_than(1, 26, 0)
      expect(config.vector_index_config.max_connections).to eq(64)
    else
      expect(config.vector_index_config.max_connections).to eq(32)
    end
    expect(config.vector_index_config.quantizer).to be_nil
    expect(config.vector_index_config.skip).to be(false)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(1_000_000_000_000)

    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
  end

  it "test_bm25_config" do
    # Python ValueError -> Ruby ArgumentError
    expect do
      collection_factory(inverted_index_config: configure.inverted_index(bm25_b: 0.8))
    end.to raise_error(ArgumentError)
  end

  it "test_collection_config_defaults" do
    collection = collection_factory(
      inverted_index_config: configure.inverted_index,
      multi_tenancy_config: configure.multi_tenancy,
      replication_config: configure.replication,
      vector_index_config: configure::VectorIndex.hnsw,
      vectorizer_config: configure::Vectorizer.none
    )
    config = collection.config.get

    expect(config.name).to eq(collection.name)
    expect(config.description).to be_nil
    expect(config.vectorizer).to eq(c::Vectorizers::NONE)

    expect(config.properties).to eq([])

    expect(config.inverted_index_config.bm25.b).to eq(0.75)
    expect(config.inverted_index_config.cleanup_interval_seconds).to eq(60)
    expect(config.inverted_index_config.index_timestamps).to be(false)
    expect(config.inverted_index_config.index_property_length).to be(false)
    expect(config.inverted_index_config.index_null_state).to be(false)
    expect(config.inverted_index_config.stopwords.additions).to be_nil
    expect(config.inverted_index_config.stopwords.preset).to eq(c::StopwordsPreset::EN)
    expect(config.inverted_index_config.stopwords.removals).to be_nil

    expect(config.multi_tenancy_config.enabled).to be(true)

    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(false)

    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(300)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(8)
    expect(config.vector_index_config.dynamic_ef_max).to eq(500)
    expect(config.vector_index_config.dynamic_ef_min).to eq(100)
    expect(config.vector_index_config.ef).to eq(-1)
    expect(config.vector_index_config.ef_construction).to eq(128)
    expect(config.vector_index_config.flat_search_cutoff).to eq(40_000)
    if version.is_lower_than(1, 26, 0)
      expect(config.vector_index_config.max_connections).to eq(64)
    else
      expect(config.vector_index_config.max_connections).to eq(32)
    end
    expect(config.vector_index_config.quantizer).to be_nil
    expect(config.vector_index_config.skip).to be(false)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(1_000_000_000_000)

    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
  end

  it "test_collection_config_full" do
    skip_unless_modules!(client, "text2vec-contextionary")
    collection = collection_factory(
      description: "Test",
      vectorizer_config: configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false),
      properties: [
        property.new(name: "text", data_type: data_type::TEXT),
        property.new(name: "texts", data_type: data_type::TEXT_ARRAY),
        property.new(name: "number", data_type: data_type::NUMBER),
        property.new(name: "numbers", data_type: data_type::NUMBER_ARRAY),
        property.new(name: "int", data_type: data_type::INT),
        property.new(name: "ints", data_type: data_type::INT_ARRAY),
        property.new(name: "date", data_type: data_type::DATE),
        property.new(name: "dates", data_type: data_type::DATE_ARRAY),
        property.new(name: "boolean", data_type: data_type::BOOL),
        property.new(name: "booleans", data_type: data_type::BOOL_ARRAY),
        property.new(name: "geo", data_type: data_type::GEO_COORDINATES),
        property.new(name: "phone", data_type: data_type::PHONE_NUMBER)
      ],
      inverted_index_config: configure.inverted_index(
        bm25_b: 0.8, bm25_k1: 1.3, cleanup_interval_seconds: 10, index_timestamps: true,
        index_property_length: true, index_null_state: true, stopwords_additions: ["a"],
        stopwords_preset: c::StopwordsPreset::EN, stopwords_removals: ["the"]
      ),
      multi_tenancy_config: configure.multi_tenancy(enabled: true, auto_tenant_activation: true,
                                                    auto_tenant_creation: true),
      replication_config: configure.replication(
        factor: 1, async_enabled: true, deletion_strategy: c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT
      ),
      vector_index_config: configure::VectorIndex.hnsw(
        cleanup_interval_seconds: 10, distance_metric: c::VectorDistances::DOT, dynamic_ef_factor: 6,
        dynamic_ef_max: 100, dynamic_ef_min: 10, ef: -2, ef_construction: 100,
        filter_strategy: c::VectorFilterStrategy::ACORN, flat_search_cutoff: 41_000, max_connections: 72,
        quantizer: configure::VectorIndex::Quantizer.pq(
          centroids: 128, encoder_distribution: c::PQEncoderDistribution::NORMAL,
          encoder_type: c::PQEncoderType::TILE, segments: 4, training_limit: 1_000_001
        ),
        vector_cache_max_objects: 100_000
      )
    )
    collection.config.add_reference(
      c::ReferenceProperty.new(name: "self", target_collection: IntegrationContext.sanitize_collection_name(collection.name))
    )
    config = collection.config.get

    expect(config.name).to eq(collection.name)
    expect(config.description).to eq("Test")
    expect(config.vectorizer).to eq(c::Vectorizers::TEXT2VEC_CONTEXTIONARY)

    [%w[text TEXT], %w[texts TEXT_ARRAY], %w[number NUMBER], %w[numbers NUMBER_ARRAY], %w[int INT],
     %w[ints INT_ARRAY], %w[date DATE], %w[dates DATE_ARRAY], %w[boolean BOOL], %w[booleans BOOL_ARRAY],
     %w[geo GEO_COORDINATES], %w[phone PHONE_NUMBER]].each_with_index do |(name, dt), i|
      expect(config.properties[i].name).to eq(name)
      expect(config.properties[i].data_type).to eq(data_type.const_get(dt))
    end

    expect(config.references[0].name).to eq("self")
    expect(config.references[0].target_collections).to eq([collection.name])

    expect(config.inverted_index_config.bm25.b).to eq(0.8)
    expect(config.inverted_index_config.bm25.k1).to eq(1.3)
    expect(config.inverted_index_config.cleanup_interval_seconds).to eq(10)
    expect(config.inverted_index_config.index_timestamps).to be(true)
    expect(config.inverted_index_config.index_property_length).to be(true)
    expect(config.inverted_index_config.index_null_state).to be(true)
    # expect(config.inverted_index_config.stopwords.additions).to eq(["a"]) # potential weaviate bug, this returns as None
    expect(config.inverted_index_config.stopwords.preset).to eq(c::StopwordsPreset::EN)
    expect(config.inverted_index_config.stopwords.removals).to eq(["the"])

    expect(config.multi_tenancy_config.enabled).to be(true)
    expect(config.multi_tenancy_config.auto_tenant_activation).to be(version.is_at_least(1, 25, 2))
    expect(config.multi_tenancy_config.auto_tenant_creation).to be(version.is_at_least(1, 25, 1))

    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(expected_async_enabled(version, factor: 1))

    if version.is_at_least(1, 24, 25)
      expect(config.replication_config.deletion_strategy).to eq(c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT)
    else
      # default value if not present in schema
      expect(config.replication_config.deletion_strategy)
        .to eq(c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION)
    end

    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::PQConfig)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(10)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::DOT)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(6)
    expect(config.vector_index_config.dynamic_ef_max).to eq(100)
    expect(config.vector_index_config.dynamic_ef_min).to eq(10)
    expect(config.vector_index_config.ef).to eq(-2)
    expect(config.vector_index_config.ef_construction).to eq(100)
    expect(config.vector_index_config.flat_search_cutoff).to eq(41_000)
    expect(config.vector_index_config.max_connections).to eq(72)
    expect(config.vector_index_config.quantizer.bit_compression).to be(false)
    expect(config.vector_index_config.quantizer.centroids).to eq(128)
    expect(config.vector_index_config.quantizer.encoder.distribution).to eq(c::PQEncoderDistribution::NORMAL)
    # expect(config.vector_index_config.pq.encoder.type_).to eq(c::PQEncoderType::TILE) # potential weaviate bug, this returns as PQEncoderType.KMEANS
    expect(config.vector_index_config.quantizer.segments).to eq(4)
    expect(config.vector_index_config.quantizer.training_limit).to eq(1_000_001)
    expect(config.vector_index_config.skip).to be(false)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(100_000)
    if version.is_at_least(1, 27, 0)
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::ACORN)
    else
      # default value if not present in schema
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::SWEEPING)
    end

    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
  end

  it "test_collection_config_update" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)],
      ports: [8087, 50_058],
      multi_tenancy_config: configure.multi_tenancy(enabled: true, auto_tenant_creation: false,
                                                    auto_tenant_activation: false)
    )

    config = retry_on_http_error(404) { collection.config.get }

    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(false)
    expect(config.multi_tenancy_config.enabled).to be(true)
    expect(config.multi_tenancy_config.auto_tenant_activation).to be(false)
    expect(config.multi_tenancy_config.auto_tenant_creation).to be(false)
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)

    if version.is_lower_than(1, 34, 0)
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::SWEEPING)
    else
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::ACORN)
    end

    collection.config.update(
      description: "Test",
      inverted_index_config: reconfigure.inverted_index(
        bm25_b: 0.8, bm25_k1: 1.25, cleanup_interval_seconds: 10, stopwords_additions: ["a"],
        stopwords_preset: c::StopwordsPreset::EN, stopwords_removals: ["the"]
      ),
      replication_config: reconfigure.replication(
        factor: 2, async_enabled: true, deletion_strategy: c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT
      ), # currently not updateable in RAFT
      vectorizer_config: reconfigure::VectorIndex.hnsw(
        vector_cache_max_objects: 2_000_000,
        filter_strategy: c::VectorFilterStrategy::ACORN,
        quantizer: reconfigure::VectorIndex::Quantizer.pq(
          centroids: 128, encoder_type: c::PQEncoderType::TILE,
          encoder_distribution: c::PQEncoderDistribution::NORMAL, segments: 4, training_limit: 100_001
        )
      ),
      multi_tenancy_config: reconfigure.multi_tenancy(auto_tenant_creation: true, auto_tenant_activation: true)
    )

    config = collection.config.get

    if version.is_at_least(1, 25, 2) || version.is_lower_than(1, 25, 0)
      expect(config.description).to eq("Test")
    else
      expect(config.description).to be_nil
    end

    expect(config.inverted_index_config.bm25.b).to eq(0.8)
    expect(config.inverted_index_config.bm25.k1).to eq(1.25)
    expect(config.inverted_index_config.cleanup_interval_seconds).to eq(10)
    # expect(config.inverted_index_config.stopwords.additions).to eq(["a"]) # potential weaviate bug, this returns as None
    expect(config.inverted_index_config.stopwords.removals).to eq(["the"])

    expect(config.replication_config.factor).to eq(2)

    expect(config.replication_config.async_enabled).to be(version.is_at_least(1, 26, 0))
    if version.is_at_least(1, 24, 25)
      expect(config.replication_config.deletion_strategy).to eq(c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT)
    else
      # default value if not present in schema
      expect(config.replication_config.deletion_strategy)
        .to eq(c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION)
    end

    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::PQConfig)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(300)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(8)
    expect(config.vector_index_config.dynamic_ef_max).to eq(500)
    expect(config.vector_index_config.dynamic_ef_min).to eq(100)
    expect(config.vector_index_config.ef).to eq(-1)
    expect(config.vector_index_config.ef_construction).to eq(128)
    expect(config.vector_index_config.flat_search_cutoff).to eq(40_000)
    if version.is_lower_than(1, 26, 0)
      expect(config.vector_index_config.max_connections).to eq(64)
    else
      expect(config.vector_index_config.max_connections).to eq(32)
    end
    expect(config.vector_index_config.quantizer.bit_compression).to be(false)
    expect(config.vector_index_config.quantizer.centroids).to eq(128)
    expect(config.vector_index_config.quantizer.encoder.type_).to eq(c::PQEncoderType::TILE)
    expect(config.vector_index_config.quantizer.encoder.distribution).to eq(c::PQEncoderDistribution::NORMAL)
    expect(config.vector_index_config.quantizer.segments).to eq(4)
    expect(config.vector_index_config.quantizer.training_limit).to eq(100_001)
    expect(config.vector_index_config.skip).to be(false)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(2_000_000)

    if version.is_at_least(1, 27, 0)
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::ACORN)
    else
      # default value if not present in schema
      expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::SWEEPING)
    end

    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)

    expect(config.multi_tenancy_config.enabled).to be(true)
    expect(config.multi_tenancy_config.auto_tenant_activation).to be(version.is_at_least(1, 25, 2))
    expect(config.multi_tenancy_config.auto_tenant_creation).to be(version.is_at_least(1, 25, 1))

    collection.config.update(
      vectorizer_config: reconfigure::VectorIndex.hnsw(
        filter_strategy: c::VectorFilterStrategy::SWEEPING,
        quantizer: reconfigure::VectorIndex::Quantizer.pq(enabled: false)
      ),
      replication_config: reconfigure.replication(
        deletion_strategy: c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION
      )
    )
    config = collection.config.get

    if version.is_at_least(1, 25, 2) || version.is_lower_than(1, 25, 0)
      expect(config.description).to eq("Test")
    else
      expect(config.description).to be_nil
    end

    expect(config.inverted_index_config.bm25.b).to eq(0.8)
    expect(config.inverted_index_config.bm25.k1).to eq(1.25)
    expect(config.inverted_index_config.cleanup_interval_seconds).to eq(10)
    # expect(config.inverted_index_config.stopwords.additions).to eq(["a"]) # potential weaviate bug, this returns as None
    expect(config.inverted_index_config.stopwords.removals).to eq(["the"])

    expect(config.replication_config.factor).to eq(2)
    expect(config.replication_config.deletion_strategy)
      .to eq(c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION)

    expect(config.replication_config.async_enabled).to be(version.is_at_least(1, 26, 0))

    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(300)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(8)
    expect(config.vector_index_config.dynamic_ef_max).to eq(500)
    expect(config.vector_index_config.dynamic_ef_min).to eq(100)
    expect(config.vector_index_config.ef).to eq(-1)
    expect(config.vector_index_config.ef_construction).to eq(128)
    expect(config.vector_index_config.flat_search_cutoff).to eq(40_000)
    if version.is_lower_than(1, 26, 0)
      expect(config.vector_index_config.max_connections).to eq(64)
    else
      expect(config.vector_index_config.max_connections).to eq(32)
    end
    expect(config.vector_index_config.quantizer).to be_nil
    expect(config.vector_index_config.skip).to be(false)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(2_000_000)
    expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::SWEEPING)

    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
  end

  it "test_hnsw_with_bq" do
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.bq(rescore_limit: 10)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::BQConfig)
  end

  it "test_hnsw_with_sq" do
    collection_factory(name: "dummy")
    skip("SQ+HNSW is not supported in Weaviate versions lower than 1.26.0") if version.is_lower_than(1, 26, 0)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 5,
        quantizer: configure::VectorIndex::Quantizer.sq(rescore_limit: 10, training_limit: 1_000_000)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::SQConfig)
  end

  it "test_hnsw_with_rq" do
    collection_factory(name: "dummy")
    skip("RQ+HNSW is not supported in Weaviate versions lower than 1.32.0") if version.is_lower_than(1, 32, 0)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 20)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.quantizer).not_to be_nil
    expect(config.vector_index_config.quantizer.bits).to eq(8)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(20)
  end

  it "test_hnsw_with_rq4c" do
    collection_factory(name: "dummy")
    if version.is_lower_than(1, 39, 2)
      skip("RQ centering is not supported in Weaviate versions lower than 1.39.2")
    end

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 5,
        quantizer: configure::VectorIndex::Quantizer.rq(bits: 4, centering: true, rescore_limit: 20,
                                                        training_limit: 5000)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.quantizer).not_to be_nil
    expect(config.vector_index_config.quantizer.bits).to eq(4)
    expect(config.vector_index_config.quantizer.centering).to be(true)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(20)
    expect(config.vector_index_config.quantizer.training_limit).to eq(5000)

    collection.config.update(
      vector_index_config: reconfigure::VectorIndex.hnsw(
        quantizer: reconfigure::VectorIndex::Quantizer.rq(rescore_limit: 50, training_limit: 10_000)
      )
    )

    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.quantizer.bits).to eq(4)
    expect(config.vector_index_config.quantizer.centering).to be(true)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(50)
    expect(config.vector_index_config.quantizer.training_limit).to eq(10_000)
  end

  it "test_hnsw_with_pathseer_filter_strategy" do
    collection_factory(name: "dummy")
    if version.is_lower_than(1, 40, 0)
      skip("pathseer filter strategy is not supported in Weaviate versions lower than 1.40.0")
    end

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(filter_strategy: c::VectorFilterStrategy::PATHSEER)
    )

    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::PATHSEER)

    collection.config.update(
      vector_index_config: reconfigure::VectorIndex.hnsw(filter_strategy: c::VectorFilterStrategy::ACORN)
    )
    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::ACORN)

    collection.config.update(
      vector_index_config: reconfigure::VectorIndex.hnsw(filter_strategy: c::VectorFilterStrategy::PATHSEER)
    )
    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.filter_strategy).to eq(c::VectorFilterStrategy::PATHSEER)
  end

  [
    -> { reconfigure::VectorIndex.hnsw(quantizer: reconfigure::VectorIndex::Quantizer.bq) },
    -> { reconfigure::VectorIndex.hnsw(quantizer: reconfigure::VectorIndex::Quantizer.sq) },
    -> { reconfigure::VectorIndex.hnsw(quantizer: reconfigure::VectorIndex::Quantizer.rq) }
  ].each_with_index do |vector_index_config, i|
    it "test_update_from_pq_with_hnsw[vector_index_config#{i}]" do
      collection = collection_factory(
        vector_index_config: configure::VectorIndex.hnsw(
          vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.pq(centroids: 128)
        )
      )
      expect do
        collection.config.update(vector_index_config: vector_index_config.call)
      end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    end
  end

  it "test_update_flat_bq" do
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.flat(
        vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.bq(rescore_limit: 10)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(5)
    expect(config.vector_index_config.quantizer).to be_a(c::BQConfig)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(10)

    collection.config.update(
      vectorizer_config: reconfigure::VectorIndex.flat(
        vector_cache_max_objects: 10, quantizer: reconfigure::VectorIndex::Quantizer.bq(rescore_limit: 20)
      )
    )
    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(10)
    expect(config.vector_index_config.quantizer).to be_a(c::BQConfig)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(20)

    # cannot enable/disable BQ after flat index was created
    # must only do this on creation
    expect do
      collection.config.update(
        vectorizer_config: reconfigure::VectorIndex.flat(quantizer: reconfigure::VectorIndex::Quantizer.bq(enabled: false))
      )
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)
  end

  it "test_update_flat_rq" do
    collection_factory(name: "dummy")
    skip("RQ in flat index is not supported in Weaviate versions lower than 1.34.0") if version.is_lower_than(1, 34, 0)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.flat(
        vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.rq(rescore_limit: 10)
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(5)
    expect(config.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(10)

    collection.config.update(
      vectorizer_config: reconfigure::VectorIndex.flat(
        vector_cache_max_objects: 10, quantizer: reconfigure::VectorIndex::Quantizer.rq(rescore_limit: 20)
      )
    )
    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(10)
    expect(config.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.quantizer.rescore_limit).to eq(20)

    # cannot disable RQ after it was enabled
    expect do
      collection.config.update(
        vectorizer_config: reconfigure::VectorIndex.flat(quantizer: reconfigure::VectorIndex::Quantizer.rq(enabled: false))
      )
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

    # cannot change bits afteradding data
    # must only do this on creation
    expect do
      collection.config.update(
        vectorizer_config: reconfigure::VectorIndex.flat(quantizer: reconfigure::VectorIndex::Quantizer.rq(bits: 1))
      )
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)
  end

  it "test_collection_config_get_shards" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)]
    )
    shards = collection.config.get_shards
    expect(shards.length).to be_positive
    if shards[0].per_node_status && !shards[0].per_node_status.empty?
      expect(shards[0].per_node_status.values).to all(eq("READY"))
    end
    expect(shards[0].status).to eq("READY")
  end

  it "test_collection_update_shards" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      multi_tenancy_config: configure.multi_tenancy(enabled: true)
    )

    tenant = Weaviate::Classes::Tenants::Tenant
    collection.tenants.create([tenant.new(name: "tenant1"), tenant.new(name: "tenant2")])
    collection.config.get_shards.each do |shard|
      expect(shard.per_node_status.values).to all(eq("READY")) if shard.per_node_status && !shard.per_node_status.empty?
      expect(shard.status).to eq("READY")
    end

    # all possibilites of calling the function
    updated_shards = collection.config.update_shards("READONLY", shard_names: "tenant1")
    expect(updated_shards.length).to eq(1)
    expect(updated_shards["tenant1"]).to eq("READONLY")

    updated_shards = collection.config.update_shards("READY", shard_names: ["tenant1"])
    expect(updated_shards.length).to eq(1)
    expect(updated_shards["tenant1"]).to eq("READY")

    updated_shards = collection.config.update_shards("READONLY", shard_names: %w[tenant1 tenant2])
    expect(updated_shards.values).to all(eq("READONLY"))

    updated_shards = collection.config.update_shards("READY", shard_names: %w[tenant1 tenant2])
    expect(updated_shards.values).to all(eq("READY"))

    updated_shards = collection.config.update_shards("READONLY")
    expect(updated_shards.values).to all(eq("READONLY"))
  end

  it "test_collection_config_get_shards_multi_tenancy" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      multi_tenancy_config: configure.multi_tenancy(enabled: true),
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)]
    )
    tenant = Weaviate::Classes::Tenants::Tenant
    collection.tenants.create([tenant.new(name: "tenant1"), tenant.new(name: "tenant2")])
    shards = collection.config.get_shards
    expect(shards.length).to eq(2)

    shards.each do |shard|
      expect(shard.per_node_status.values).to all(eq("READY")) if shard.per_node_status && !shard.per_node_status.empty?
      expect(shard.status).to eq("READY")
    end

    expect(shards.map(&:name)).to include("tenant1")
    expect(shards.map(&:name)).to include("tenant2")
  end

  it "test_config_vector_index_flat_and_quantizer_bq" do
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.flat(
        vector_cache_max_objects: 234, quantizer: configure::VectorIndex::Quantizer.bq(rescore_limit: 456)
      )
    )

    conf = collection.config.get
    expect(conf.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(conf.vector_index_config).not_to be_nil
    expect(conf.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(conf.vector_index_config.vector_cache_max_objects).to eq(234)
    expect(conf.vector_index_config.quantizer).to be_a(c::BQConfig)
    expect(conf.vector_index_config.quantizer.rescore_limit).to eq(456)
  end

  it "test_config_vector_index_flat_and_quantizer_rq" do
    collection_factory(name: "dummy")
    skip("RQ in flat index is not supported in Weaviate versions lower than 1.34.0") if version.is_lower_than(1, 34, 0)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.flat(
        vector_cache_max_objects: 234, quantizer: configure::VectorIndex::Quantizer.rq(bits: 8)
      )
    )

    conf = collection.config.get
    expect(conf.vector_index_type).to eq(c::VectorIndexType::FLAT)
    expect(conf.vector_index_config).not_to be_nil
    expect(conf.vector_index_config).to be_a(c::VectorIndexConfigFlat)
    expect(conf.vector_index_config.vector_cache_max_objects).to eq(234)
    expect(conf.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(conf.vector_index_config.quantizer.bits).to eq(8)
  end

  it "test_config_vector_index_hnsw_and_quantizer_rq" do
    collection_factory(name: "dummy")
    skip("RQ in HNSW index is not supported in Weaviate versions lower than 1.32.0") if version.is_lower_than(1, 32, 0)
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 234, ef_construction: 789,
        quantizer: configure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 123)
      )
    )

    conf = collection.config.get
    expect(conf.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(conf.vector_index_config).not_to be_nil
    expect(conf.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(conf.vector_index_config.vector_cache_max_objects).to eq(234)
    expect(conf.vector_index_config.ef_construction).to eq(789)
    expect(conf.vector_index_config.quantizer).to be_a(c::RQConfig)
    expect(conf.vector_index_config.quantizer.bits).to eq(8)
    expect(conf.vector_index_config.quantizer.rescore_limit).to eq(123)
  end

  it "test_config_vector_index_hnsw_and_quantizer_pq" do
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 234, ef_construction: 789,
        quantizer: configure::VectorIndex::Quantizer.pq(segments: 456)
      )
    )

    conf = collection.config.get
    expect(conf.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(conf.vector_index_config).not_to be_nil
    expect(conf.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(conf.vector_index_config.vector_cache_max_objects).to eq(234)
    expect(conf.vector_index_config.ef_construction).to eq(789)
    expect(conf.vector_index_config.quantizer).to be_a(c::PQConfig)
    expect(conf.vector_index_config.quantizer.segments).to eq(456)
  end

  [
    [-> { configure::Reranker.cohere }, c::Rerankers::COHERE, {}, "reranker-cohere"],
    [
      -> { configure::Reranker.cohere(model: "rerank-english-v2.0", base_url: "https://some-cohere-baseurl.ai/") },
      c::Rerankers::COHERE, { "model" => "rerank-english-v2.0", "baseURL" => "https://some-cohere-baseurl.ai/" },
      "reranker-cohere"
    ],
    [-> { configure::Reranker.transformers }, c::Rerankers::TRANSFORMERS, {}, "reranker-transformers"]
  ].each_with_index do |(reranker_config, expected_reranker, expected_model, module_name), i|
    it "test_config_reranker_module[reranker_config#{i}-#{expected_reranker}]" do
      skip_unless_modules!(client, module_name)
      collection = collection_factory(reranker_config: reranker_config.call,
                                      vectorizer_config: configure::Vectorizer.none)
      conf = collection.config.get
      expect(conf.reranker_config).not_to be_nil
      expect(conf.reranker_config.reranker).to eq(expected_reranker)
      expect(conf.reranker_config.model).to eq(expected_model)
    end
  end

  it "test_config_nested_properties" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [
        property.new(
          name: "name", data_type: data_type::OBJECT,
          nested_properties: [property.new(name: "first", data_type: data_type::TEXT),
                              property.new(name: "last", data_type: data_type::TEXT)]
        )
      ]
    )
    conf = collection.config.get
    expect(conf.properties[0].name).to eq("name")
    expect(conf.properties[0].data_type).to eq(data_type::OBJECT)
    expect(conf.properties[0].nested_properties).not_to be_nil
    expect(conf.properties[0].nested_properties[0].name).to eq("first")
    expect(conf.properties[0].nested_properties[0].data_type).to eq(data_type::TEXT)
    expect(conf.properties[0].nested_properties[1].name).to eq("last")
    expect(conf.properties[0].nested_properties[1].data_type).to eq(data_type::TEXT)
  end

  it "test_config_export_and_recreate_from_config" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)]
    )
    conf = collection.config.get

    name = "TestCollectionConfigExportAndRecreateFromConfig"
    conf.name = name

    with_local_client do |client|
      client.collections.create_from_config(conf)
      expect(conf).to eq(client.collections.use(name).config.get)
      client.collections.delete(name)
    end
  end

  it "test_config_export_and_recreate_from_dict" do
    collection = collection_factory(
      generative_config: configure::Generative.custom("generative-anyscale", module_config: { "temperature" => 0.5 }),
      vectorizer_config: configure::Vectorizer.none,
      reranker_config: configure::Reranker.custom("reranker-cohere", module_config: { "model" => "rerank-english-v2.0" }),
      properties: [
        property.new(name: "field_tokenization", data_type: data_type::TEXT, tokenization: c::Tokenization::FIELD),
        property.new(name: "field_description", data_type: data_type::TEXT, tokenization: c::Tokenization::FIELD,
                     description: "field desc"),
        property.new(name: "field_index_filterable", data_type: data_type::TEXT, index_filterable: false),
        property.new(name: "field_skip_vectorization", data_type: data_type::TEXT, skip_vectorization: true),
        property.new(name: "text", data_type: data_type::TEXT),
        property.new(name: "texts", data_type: data_type::TEXT_ARRAY),
        property.new(name: "number", data_type: data_type::NUMBER),
        property.new(name: "numbers", data_type: data_type::NUMBER_ARRAY),
        property.new(name: "int", data_type: data_type::INT),
        property.new(name: "ints", data_type: data_type::INT_ARRAY),
        property.new(name: "date", data_type: data_type::DATE),
        property.new(name: "dates", data_type: data_type::DATE_ARRAY),
        property.new(name: "boolean", data_type: data_type::BOOL),
        property.new(name: "booleans", data_type: data_type::BOOL_ARRAY),
        property.new(name: "geo", data_type: data_type::GEO_COORDINATES),
        property.new(name: "phone", data_type: data_type::PHONE_NUMBER),
        property.new(name: "field_searchable_off", data_type: data_type::TEXT, index_searchable: false),
        property.new(name: "field_index_range_filters_false", data_type: data_type::INT, index_range_filters: false),
        property.new(name: "field_index_range_filters_true", data_type: data_type::INT, index_range_filters: true),
        property.new(name: "field_skip_vectorization_false", data_type: data_type::TEXT,
                     vectorize_property_name: false),
        property.new(
          name: "nested", data_type: data_type::OBJECT,
          nested_properties: [
            property.new(name: "first", data_type: data_type::TEXT),
            property.new(name: "nested_token", data_type: data_type::TEXT, tokenization: c::Tokenization::FIELD),
            property.new(name: "nested_searchable_off", data_type: data_type::TEXT, index_searchable: false),
            property.new(name: "nested_filterable", data_type: data_type::TEXT, index_filterable: false),
            property.new(name: "nested_prop_vectorization", data_type: data_type::TEXT,
                         vectorize_property_name: false),
            property.new(name: "nested_range", data_type: data_type::TEXT, vectorize_property_name: false),
            property.new(name: "nested_skip_vectorization", data_type: data_type::TEXT, skip_vectorization: true),
            property.new(name: "nested2", data_type: data_type::OBJECT,
                         nested_properties: [property.new(name: "first", data_type: data_type::TEXT)])
          ]
        )
      ],
      multi_tenancy_config: configure.multi_tenancy(enabled: true),
      replication_config: configure.replication(factor: 1, async_enabled: false),
      vector_index_config: configure::VectorIndex.hnsw(quantizer: configure::VectorIndex::Quantizer.pq(centroids: 256)),
      inverted_index_config: configure.inverted_index(bm25_b: 0.8, bm25_k1: 1.3)
    )
    collection.config.add_reference(c::ReferenceProperty.new(name: "self", target_collection: collection.name))
    conf = collection.config.get

    name = "TestCollectionConfigExportAndRecreateFromDict"
    conf.name = name
    dconf = conf.to_dict

    with_local_client do |client|
      client.collections.delete(name)
      client.collections.create_from_dict(dconf)
      old = collection.config.get
      old.name = "dummy"
      new = client.collections.use(name).config.get
      new.name = "dummy"
      expect(old).to eq(new)

      client.collections.delete(name)
    end
  end

  it "test_config_add_existing_property_and_reference" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT)]
    )
    collection.config.add_reference(c::ReferenceProperty.new(name: "self", target_collection: collection.name))
    expect do
      collection.config.add_property(property.new(name: "name", data_type: data_type::TEXT))
    end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    expect do
      collection.config.add_reference(c::ReferenceProperty.new(name: "self", target_collection: collection.name))
    end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  it "test_config_skip_vector_index" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      vector_index_config: configure::VectorIndex.none
    )
    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.cleanup_interval_seconds).to eq(300)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.dynamic_ef_factor).to eq(8)
    expect(config.vector_index_config.dynamic_ef_max).to eq(500)
    expect(config.vector_index_config.dynamic_ef_min).to eq(100)
    expect(config.vector_index_config.ef).to eq(-1)
    expect(config.vector_index_config.ef_construction).to eq(128)
    expect(config.vector_index_config.flat_search_cutoff).to eq(40_000)
    if version.is_lower_than(1, 26, 0)
      expect(config.vector_index_config.max_connections).to eq(64)
    else
      expect(config.vector_index_config.max_connections).to eq(32)
    end
    expect(config.vector_index_config.quantizer).to be_nil
    expect(config.vector_index_config.skip).to be(true)
    expect(config.vector_index_config.vector_cache_max_objects).to eq(1_000_000_000_000)
  end

  it "test_dynamic_collection" do
    collection_factory(name: "dummy", ports: [8090, 50_061])
    skip("Dynamic index is not supported in Weaviate versions lower than 1.25.0") if version.is_lower_than(1, 25, 0)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.dynamic(
        distance_metric: c::VectorDistances::COSINE,
        threshold: 1000,
        hnsw: configure::VectorIndex.hnsw(
          cleanup_interval_seconds: 123, flat_search_cutoff: 1234, vector_cache_max_objects: 789,
          quantizer: configure::VectorIndex::Quantizer.pq(centroids: 128)
        ),
        flat: configure::VectorIndex.flat(
          vector_cache_max_objects: 7643, quantizer: configure::VectorIndex::Quantizer.bq(rescore_limit: 10)
        )
      ),
      ports: [8090, 50_061]
    )

    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigDynamic)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.threshold).to eq(1000)
    expect(config.vector_index_config.hnsw).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.hnsw.cleanup_interval_seconds).to eq(123)
    expect(config.vector_index_config.hnsw.flat_search_cutoff).to eq(1234)
    expect(config.vector_index_config.hnsw.vector_cache_max_objects).to eq(789)
    expect(config.vector_index_config.hnsw.quantizer).to be_a(c::PQConfig)
    expect(config.vector_index_config.hnsw.quantizer.centroids).to eq(128)
    expect(config.vector_index_config.flat).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.flat.vector_cache_max_objects).to eq(7643)
    expect(config.vector_index_config.flat.quantizer).to be_a(c::BQConfig)
    expect(config.vector_index_config.flat.quantizer.rescore_limit).to eq(10)

    collection.config.update(
      vectorizer_config: reconfigure::VectorIndex.dynamic(
        threshold: 2000,
        hnsw: reconfigure::VectorIndex.hnsw(
          flat_search_cutoff: 4567, vector_cache_max_objects: 678,
          quantizer: reconfigure::VectorIndex::Quantizer.pq(centroids: 128)
        ),
        flat: reconfigure::VectorIndex.flat(
          vector_cache_max_objects: 9876, quantizer: reconfigure::VectorIndex::Quantizer.bq(rescore_limit: 11)
        )
      )
    )
    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigDynamic)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.threshold).to eq(2000)
    expect(config.vector_index_config.hnsw).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.hnsw.cleanup_interval_seconds).to eq(123)
    expect(config.vector_index_config.hnsw.flat_search_cutoff).to eq(4567)
    expect(config.vector_index_config.hnsw.vector_cache_max_objects).to eq(678)
    expect(config.vector_index_config.hnsw.quantizer).to be_a(c::PQConfig)
    expect(config.vector_index_config.hnsw.quantizer.centroids).to eq(128)
    expect(config.vector_index_config.flat).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.flat.vector_cache_max_objects).to eq(9876)
    expect(config.vector_index_config.flat.quantizer).to be_a(c::BQConfig)
    expect(config.vector_index_config.flat.quantizer.rescore_limit).to eq(11)
  end

  it "test_dynamic_collection_rq" do
    collection_factory(name: "dummy", ports: [8090, 50_061])
    if version.is_lower_than(1, 34, 0)
      skip("Dynamic index with RQ is not supported in Weaviate versions lower than 1.34.0")
    end

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.dynamic(
        distance_metric: c::VectorDistances::COSINE,
        threshold: 1000,
        hnsw: configure::VectorIndex.hnsw(
          cleanup_interval_seconds: 123, flat_search_cutoff: 1234, vector_cache_max_objects: 789,
          quantizer: configure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 123)
        ),
        flat: configure::VectorIndex.flat(
          vector_cache_max_objects: 7643, quantizer: configure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 10)
        )
      ),
      ports: [8090, 50_061]
    )

    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigDynamic)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.threshold).to eq(1000)
    expect(config.vector_index_config.hnsw).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.hnsw.cleanup_interval_seconds).to eq(123)
    expect(config.vector_index_config.hnsw.flat_search_cutoff).to eq(1234)
    expect(config.vector_index_config.hnsw.vector_cache_max_objects).to eq(789)
    expect(config.vector_index_config.hnsw.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.hnsw.quantizer.bits).to eq(8)
    expect(config.vector_index_config.hnsw.quantizer.rescore_limit).to eq(123)
    expect(config.vector_index_config.flat).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.flat.vector_cache_max_objects).to eq(7643)
    expect(config.vector_index_config.flat.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.flat.quantizer.bits).to eq(8)
    expect(config.vector_index_config.flat.quantizer.rescore_limit).to eq(10)

    collection.config.update(
      vectorizer_config: reconfigure::VectorIndex.dynamic(
        threshold: 2000,
        hnsw: reconfigure::VectorIndex.hnsw(
          flat_search_cutoff: 4567, vector_cache_max_objects: 678,
          quantizer: reconfigure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 200)
        ),
        flat: reconfigure::VectorIndex.flat(
          vector_cache_max_objects: 9876, quantizer: reconfigure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 20)
        )
      )
    )
    config = collection.config.get
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigDynamic)
    expect(config.vector_index_config.distance_metric).to eq(c::VectorDistances::COSINE)
    expect(config.vector_index_config.threshold).to eq(2000)
    expect(config.vector_index_config.hnsw).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.hnsw.cleanup_interval_seconds).to eq(123)
    expect(config.vector_index_config.hnsw.flat_search_cutoff).to eq(4567)
    expect(config.vector_index_config.hnsw.vector_cache_max_objects).to eq(678)
    expect(config.vector_index_config.hnsw.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.hnsw.quantizer.bits).to eq(8)
    expect(config.vector_index_config.hnsw.quantizer.rescore_limit).to eq(200)
    expect(config.vector_index_config.flat).to be_a(c::VectorIndexConfigFlat)
    expect(config.vector_index_config.flat.vector_cache_max_objects).to eq(9876)
    expect(config.vector_index_config.flat.quantizer).to be_a(c::RQConfig)
    expect(config.vector_index_config.flat.quantizer.bits).to eq(8)
    expect(config.vector_index_config.flat.quantizer.rescore_limit).to eq(20)
  end

  it "test_config_unknown_module" do
    with_local_client do |client|
      collection_name = IntegrationContext.sanitize_collection_name(RSpec.current_example.description)
      client.collections.delete(collection_name)
      collection = client.collections.create_from_dict(
        {
          "class" => collection_name,
          "vectorizer" => "none",
          "moduleConfig" => { "generative-dummy" => {}, "reranker-dummy" => {} },
          "properties" => [{ "name" => "prop", "dataType" => ["text"] }]
        }
      )
      config = collection.config.get
      expect(config.generative_config).not_to be_nil
      expect(config.generative_config.generative.to_s).to be_a(String)
      expect(config.generative_config.generative).to eq("generative-dummy")

      expect(config.reranker_config).not_to be_nil
      expect(config.reranker_config.reranker.to_s).to be_a(String)
      expect(config.reranker_config.reranker).to eq("reranker-dummy")

      client.collections.delete(collection_name)

      collection2 = client.collections.create_from_config(config)
      config2 = collection2.config.get
      expect(config).to eq(config2)
      expect(config2.generative_config).not_to be_nil
      expect(config2.generative_config.generative).to eq("generative-dummy")

      expect(config2.reranker_config).not_to be_nil
      expect(config2.reranker_config.reranker).to eq("reranker-dummy")

      client.collections.delete(collection_name)
    end
  end

  it "test_create_custom_generative" do
    collection = collection_factory(
      generative_config: configure::Generative.custom("generative-anyscale", module_config: { "temperature" => 0.5 })
    )
    config = collection.config.get

    collection2 = collection_factory(generative_config: configure::Generative.anyscale(temperature: 0.5))
    config2 = collection2.config.get

    expect(config.generative_config).to eq(config2.generative_config)
    expect(config.generative_config).not_to be_nil
    expect(config.generative_config.generative).to eq("generative-anyscale")
    expect(config.generative_config.model).to eq({ "temperature" => 0.5 })

    if version.is_at_least(1, 25, 24)
      collection.config.update(generative_config: reconfigure::Generative.custom("generative-dummy"))
      config = collection.config.get
      expect(config.generative_config).not_to be_nil
      expect(config.generative_config.generative).to eq("generative-dummy")
    end
  end

  it "test_create_custom_reranker" do
    collection = collection_factory(
      reranker_config: configure::Reranker.custom("reranker-cohere", module_config: { "model" => "rerank-english-v2.0" })
    )
    config = collection.config.get

    collection2 = collection_factory(reranker_config: configure::Reranker.cohere(model: "rerank-english-v2.0"))
    config2 = collection2.config.get

    expect(config.reranker_config).to eq(config2.reranker_config)
    expect(config.reranker_config).not_to be_nil
    expect(config.reranker_config.reranker).to eq("reranker-cohere")
    expect(config.reranker_config.model).to eq({ "model" => "rerank-english-v2.0" })

    if version.is_at_least(1, 25, 24)
      collection.config.update(reranker_config: reconfigure::Reranker.custom("reranker-dummy"))
      config = collection.config.get
      expect(config.reranker_config).not_to be_nil
      expect(config.reranker_config.reranker).to eq("reranker-dummy")
    end
  end

  it "test_create_custom_vectorizer" do
    skip_unless_modules!(client, "text2vec-contextionary")
    collection = collection_factory(
      properties: [property.new(name: "text", data_type: data_type::TEXT)],
      vectorizer_config: configure::Vectorizer.custom("text2vec-contextionary",
                                                      module_config: { "vectorizeClassName" => false })
    )
    config = collection.config.get

    collection2 = collection_factory(
      properties: [property.new(name: "text", data_type: data_type::TEXT)],
      vectorizer_config: configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false)
    )
    config2 = collection2.config.get

    expect(config.vectorizer_config).to eq(config2.vectorizer_config)
    expect(config.vectorizer_config).not_to be_nil
    expect(config.vectorizer_config.vectorizer).to eq("text2vec-contextionary")
    expect(config.vectorizer_config.vectorize_collection_name).to be_falsey
  end

  it "test_create_custom_vectorizer_named" do
    skip_unless_modules!(client, "text2vec-contextionary")
    collection = collection_factory(
      properties: [property.new(name: "text", data_type: data_type::TEXT)],
      vectorizer_config: [
        configure::NamedVectors.custom("name", module_name: "text2vec-contextionary",
                                               module_config: { "vectorizeClassName" => false })
      ]
    )
    config = collection.config.get

    collection2 = collection_factory(
      properties: [property.new(name: "text", data_type: data_type::TEXT)],
      vectorizer_config: [configure::NamedVectors.text2vec_contextionary("name", vectorize_collection_name: false)]
    )
    config2 = collection2.config.get

    expect(config.vector_config).to eq(config2.vector_config)
    expect(config.vector_config).not_to be_nil
    expect(config.vector_config.length).to eq(1)
    expect(config.vector_config["name"].vectorizer.vectorizer).to eq("text2vec-contextionary")
    expect(config.vector_config["name"].vectorizer.model).to eq({ "vectorizeClassName" => false })
  end

  [nil, ["text"]].each do |source_properties|
    it "test_named_vectors_export_and_import[#{source_properties.inspect}]" do
      skip_unless_modules!(client, "text2vec-contextionary")
      collection = collection_factory(
        properties: [property.new(name: "text", data_type: data_type::TEXT)],
        vectorizer_config: [
          configure::NamedVectors.text2vec_contextionary("name", vectorize_collection_name: false,
                                                                 source_properties: source_properties)
        ]
      )
      config = collection.config.get

      name = "TestCollectionConfigExportAndRecreate_#{collection.name}"
      config.name = name
      with_local_client do |client|
        client.collections.delete(name)
        client.collections.create_from_config(config)
        new = client.collections.use(name).config.get
        expect(config).to eq(new)
        expect(config.to_dict).to eq(new.to_dict)
        client.collections.delete(name)
      end
    end
  end

  [nil, ["text"]].each do |source_properties|
    it "test_vectors_export_and_import[#{source_properties.inspect}]" do
      skip_unless_modules!(client, "text2vec-contextionary")
      collection = collection_factory(
        properties: [property.new(name: "text", data_type: data_type::TEXT)],
        vector_config: configure::Vectors.text2vec_contextionary(vectorize_collection_name: false,
                                                                 source_properties: source_properties)
      )
      config = collection.config.get

      name = "TestCollectionConfigExportAndRecreate_#{collection.name}"
      config.name = name
      with_local_client do |client|
        client.collections.delete(name)
        client.collections.create_from_config(config)
        new = client.collections.use(name).config.get
        expect(config).to eq(new)
        expect(config.to_dict).to eq(new.to_dict)
        client.collections.delete(name)
      end
    end
  end

  [nil, ["text"]].each do |source_properties|
    it "test_named_vectors_export_and_import_dict[#{source_properties.inspect}]" do
      skip_unless_modules!(client, "text2vec-contextionary")
      collection = collection_factory(
        properties: [property.new(name: "text", data_type: data_type::TEXT)],
        vectorizer_config: [
          configure::NamedVectors.text2vec_contextionary("name", vectorize_collection_name: false,
                                                                 source_properties: source_properties)
        ]
      )
      config = collection.config.get

      name = "TestCollectionConfigExportAndRecreateDict_#{collection.name}"
      config.name = name
      with_local_client do |client|
        client.collections.delete(name)
        client.collections.create_from_dict(config.to_dict)
        new = client.collections.use(name).config.get
        expect(config).to eq(new)
        expect(config.to_dict).to eq(new.to_dict)
        client.collections.delete(name)
      end
    end
  end

  [nil, ["text"]].each do |source_properties|
    it "test_vectors_export_and_import_dict[#{source_properties.inspect}]" do
      skip_unless_modules!(client, "text2vec-contextionary")
      collection = collection_factory(
        properties: [property.new(name: "text", data_type: data_type::TEXT)],
        vector_config: configure::Vectors.text2vec_contextionary(vectorize_collection_name: false,
                                                                 source_properties: source_properties)
      )
      config = collection.config.get

      name = "TestCollectionConfigExportAndRecreateDict_#{collection.name}"
      config.name = name
      with_local_client do |client|
        client.collections.delete(name)
        client.collections.create_from_dict(config.to_dict)
        new = client.collections.use(name).config.get
        expect(config).to eq(new)
        expect(config.to_dict).to eq(new.to_dict)
        client.collections.delete(name)
      end
    end
  end

  [true, false].each do |index_range_filters|
    it "test_range_filters[#{index_range_filters}]" do
      collection_factory(name: "dummy")
      skip("range filters are not supported in Weaviate versions lower than 1.26.0") if version.is_lower_than(1, 26, 0)

      collection = collection_factory(
        properties: [property.new(name: "text", data_type: data_type::INT, index_range_filters: index_range_filters)]
      )
      config = collection.config.get
      expect(config.properties[0].index_range_filters).to eq(index_range_filters)
    end
  end

  [c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT,
   c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION].each do |deletion_strategy|
    it "test_replication_config[#{deletion_strategy}]" do
      collection_factory(name: "dummy")
      if version.is_lower_than(1, 24, 25)
        skip("deletion strategy is supported in Weaviate versions lower than 1.24, 25")
      end

      collection = collection_factory(replication_config: configure.replication(deletion_strategy: deletion_strategy))
      config = collection.config.get
      expect(config.replication_config.deletion_strategy).to eq(deletion_strategy)
    end
  end

  it "test_replication_config_without_async_config" do
    collection = collection_factory(replication_config: configure.replication(factor: 1, async_enabled: false))
    config = collection.config.get
    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(false)
    expect(config.replication_config.async_config).to be_nil
  end

  it "test_replication_config_with_async_config" do
    collection_factory(name: "dummy")
    skip("async replication config requires Weaviate >= 1.34.18") if version.is_lower_than(1, 34, 18)

    collection = collection_factory(
      replication_config: configure.replication(
        factor: 1, async_enabled: true,
        async_config: configure::Replication.async_config(propagation_concurrency: 4, hashtree_height: 20)
      )
    )
    config = collection.config.get
    expect(config.replication_config.factor).to eq(1)
    expect(config.replication_config.async_enabled).to be(expected_async_enabled(version, factor: 1))
    expect(config.replication_config.async_config).not_to be_nil
    ac = config.replication_config.async_config
    expect(ac.propagation_concurrency).to eq(4)
    expect(ac.hashtree_height).to eq(20)
    if version.is_at_least(1, 37, 3)
      # Server removed max_workers / alive_nodes_checking_frequency from the schema in 1.37.3
      expect(ac.max_workers).to be_nil
      expect(ac.alive_nodes_checking_frequency).to be_nil
    end
  end

  # Disabling `async_enabled` must leave the collection's async replication tuning intact.
  #
  # `config.update()` is a read-modify-write PUT of the whole collection, so dropping `asyncConfig`
  # from the merged payload would silently reset the tuning to server defaults.
  it "test_replication_config_async_config_preserved_when_disabling_async_replication" do
    collection_factory(name: "dummy")
    skip("async replication config requires Weaviate >= 1.34.18") if version.is_lower_than(1, 34, 18)

    collection = collection_factory(
      replication_config: configure.replication(
        factor: 1, async_enabled: true,
        async_config: configure::Replication.async_config(propagation_concurrency: 4, hashtree_height: 20)
      )
    )
    config = collection.config.get
    expect(config.replication_config.async_config).not_to be_nil
    expect(config.replication_config.async_config.propagation_concurrency).to eq(4)

    collection.config.update(replication_config: reconfigure.replication(async_enabled: false))
    config = collection.config.get
    # False on both sides of the v1.38 compatibility shim: older servers store the
    # `asyncEnabled` we just sent, newer ones derive it as `factor > 1 and not globally
    # disabled` — and this collection has factor=1.
    expect(config.replication_config.async_enabled).to be(false)
    ac = config.replication_config.async_config
    expect(ac).not_to be_nil
    expect(ac.propagation_concurrency).to eq(4)
    expect(ac.hashtree_height).to eq(20)
  end

  it "test_replication_config_remove_async_config" do
    collection_factory(name: "dummy")
    skip("async replication config requires Weaviate >= 1.34.18") if version.is_lower_than(1, 34, 18)

    collection = collection_factory(
      replication_config: configure.replication(
        factor: 1, async_enabled: true,
        async_config: configure::Replication.async_config(propagation_concurrency: 4, hashtree_height: 20)
      )
    )
    config = collection.config.get
    expect(config.replication_config.async_config).not_to be_nil
    expect(config.replication_config.async_config.propagation_concurrency).to eq(4)

    collection.config.update(
      replication_config: reconfigure.replication(factor: 1, async_enabled: true,
                                                  async_config: reconfigure::Replication.async_config)
    )
    config = collection.config.get
    expect(config.replication_config.async_enabled).to be(expected_async_enabled(version, factor: 1))
    expect(config.replication_config.async_config).to be_nil
    expect(config.replication_config.factor).to eq(1)
  end

  it "test_replication_config_unset_single_async_field" do
    collection_factory(name: "dummy")
    skip("async replication config requires Weaviate >= 1.36.0") if version.is_lower_than(1, 36, 0)

    collection = collection_factory(
      replication_config: configure.replication(
        factor: 1, async_enabled: true,
        async_config: configure::Replication.async_config(propagation_concurrency: 4, hashtree_height: 20)
      )
    )
    config = collection.config.get
    ac = config.replication_config.async_config
    expect(ac).not_to be_nil
    expect(ac.propagation_concurrency).to eq(4)
    expect(ac.hashtree_height).to eq(20)

    # Update with only propagation_concurrency — hashtree_height reverts to server default
    collection.config.update(
      replication_config: reconfigure.replication(
        async_config: reconfigure::Replication.async_config(propagation_concurrency: 4)
      )
    )
    config = collection.config.get
    ac = config.replication_config.async_config
    expect(ac).not_to be_nil
    expect(ac.propagation_concurrency).to eq(4)
    expect(ac.hashtree_height).not_to eq(20)
  end

  # Test updating a collection that was created without async_config to add one.
  #
  # This covers the case where the existing schema has no asyncConfig key
  # and merge_with_existing must handle the missing field gracefully.
  it "test_replication_config_add_async_config_to_existing_collection" do
    collection_factory(name: "dummy")
    skip("async replication config requires Weaviate >= 1.34.18") if version.is_lower_than(1, 34, 18)

    # Create without async_config
    collection = collection_factory(replication_config: configure.replication(factor: 1, async_enabled: true))
    config = collection.config.get
    expect(config.replication_config.async_config).to be_nil

    # Update to add async_config
    collection.config.update(
      replication_config: reconfigure.replication(
        async_config: reconfigure::Replication.async_config(propagation_concurrency: 4, hashtree_height: 20)
      )
    )
    config = collection.config.get
    expect(config.replication_config.async_config).not_to be_nil
    ac = config.replication_config.async_config
    expect(ac.propagation_concurrency).to eq(4)
    expect(ac.hashtree_height).to eq(20)
  end

  it "test_update_property_descriptions" do
    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [property.new(name: "name", data_type: data_type::TEXT),
                   property.new(name: "age", data_type: data_type::INT)]
    )

    if version.is_lower_than(1, 27, 0)
      skip("Property descriptions are not supported in currently released Weaviate versions lower than 1.27.0")
    end

    config = collection.config.get
    expect(config.properties[0].description).to be_nil
    expect(config.properties[1].description).to be_nil

    update = lambda do
      collection.config.update(
        property_descriptions: { "name" => "Name of the person", "age" => "Age of the person" }
      )
    end

    ver = version
    supported = (ver.is_at_least(1, 27, 15) && ver.is_lower_than(1, 28, 0)) ||
                (ver.is_at_least(1, 28, 9) && ver.is_lower_than(1, 29, 0)) ||
                ver.is_at_least(1, 29, 1)

    if supported
      update.call

      config = collection.config.get
      descriptions = config.properties.map(&:description)
      expect(descriptions).to include("Age of the person")
      expect(descriptions).to include("Name of the person")
    else
      expect { update.call }.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)
    end
  end

  it "test_config_multi_vector_enabled" do
    collection_factory(name: "dummy", ports: [8086, 50_057])
    skip("Multi vector is not supported in Weaviate versions lower than 1.29.0") if version.is_lower_than(1, 29, 0)

    collection = collection_factory(
      ports: [8086, 50_057],
      properties: [property.new(name: "name", data_type: data_type::TEXT)],
      vector_config: [configure::MultiVectors.text2vec_jinaai(name: "vec", vectorize_collection_name: false)]
    )
    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    conf = config.vector_config["vec"].vector_index_config
    expect(conf).to be_a(c::VectorIndexConfigHNSW)
    if version.is_lower_than(1, 29, 0)
      expect(conf.multi_vector).to be_nil
    else
      expect(conf.multi_vector).not_to be_nil
    end
  end

  it "test_config_multi_vector_disabled" do
    collection = collection_factory(
      ports: [8086, 50_057],
      properties: [property.new(name: "name", data_type: data_type::TEXT)],
      vectorizer_config: [configure::NamedVectors.text2vec_cohere("vec", vectorize_collection_name: false)]
    )
    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    conf = config.vector_config["vec"].vector_index_config
    expect(conf).to be_a(c::VectorIndexConfigHNSW)
    expect(conf.multi_vector).to be_nil
  end

  it "test_config_muvera_enabled" do
    collection_factory(name: "dummy", ports: [8086, 50_057])
    skip("Muvera is not supported in Weaviate versions lower than 1.31.0") if version.is_lower_than(1, 31, 0)

    collection = collection_factory(
      ports: [8086, 50_057],
      properties: [property.new(name: "name", data_type: data_type::TEXT)],
      vector_config: [
        configure::MultiVectors.text2vec_jinaai(
          name: "vec", vectorize_collection_name: false,
          encoding: configure::VectorIndex::MultiVector::Encoding.muvera
        )
      ]
    )
    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    conf = config.vector_config["vec"].vector_index_config
    expect(conf).to be_a(c::VectorIndexConfigHNSW)
    if version.is_lower_than(1, 31, 0)
      expect(conf.multi_vector).to be_nil
    else
      expect(conf.multi_vector).not_to be_nil
      expect(conf.multi_vector.encoding).not_to be_nil
    end
  end

  it "test_config_muvera_disabled" do
    collection_factory(name: "dummy", ports: [8086, 50_057])
    skip("Multivector is not supported in Weaviate versions lower than 1.29.0") if version.is_lower_than(1, 29, 0)

    collection = collection_factory(
      ports: [8086, 50_057],
      properties: [property.new(name: "name", data_type: data_type::TEXT)],
      vector_config: [configure::MultiVectors.text2vec_jinaai(name: "vec", vectorize_collection_name: false)]
    )
    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    conf = config.vector_config["vec"].vector_index_config
    expect(conf).to be_a(c::VectorIndexConfigHNSW)
    expect(conf.multi_vector).not_to be_nil
    expect(conf.multi_vector.encoding).to be_nil
  end

  [
    -> {},
    -> { configure::Vectorizer.none },
    -> { [configure::NamedVectors.none("another")] }
  ].each_with_index do |existing_vectors, i|
    it "test_config_add_vector[existing_vectors#{i}]" do
      collection_factory(name: "dummy")
      skip("Adding vectors is not supported in Weaviate versions lower than 1.31.0") if version.is_lower_than(1, 31, 0)

      collection = collection_factory(
        vectorizer_config: existing_vectors.call,
        properties: [property.new(name: "name", data_type: data_type::TEXT)]
      )

      collection.config.add_vector(vector_config: configure::Vectors.self_provided(name: "vec"))
      config = collection.config.get
      expect(config.vector_config).not_to be_nil
      expect(config.vector_config).to include("vec")

      # Use deprecated syntax
      collection.config.add_vector(vector_config: configure::NamedVectors.none("vec2"))
      config = collection.config.get
      expect(config.vector_config).not_to be_nil
      expect(config.vector_config).to include("vec2")
    end
  end

  generative_configs = [[nil, -> {}], ["generative_config1", -> { configure::Generative.anyscale }]]
  vectorizer_configs = [
    [nil, -> {}],
    ["vectorizer_config1", -> { configure::Vectorizer.none }],
    ["vectorizer_config2", -> { configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false) }],
    ["vectorizer_config3",
     -> { [configure::NamedVectors.text2vec_contextionary("vec", vectorize_collection_name: false)] }]
  ]
  vectorizer_configs.each_with_index do |(vec_id, vectorizer_config), vi|
    generative_configs.each do |gen_id, generative_config|
      it "test_config_add_property[#{vec_id || "None"}-#{gen_id || "None"}]" do
        skip_unless_modules!(client, "text2vec-contextionary") if vi >= 2
        collection = collection_factory(
          properties: [property.new(name: "title", data_type: data_type::TEXT)],
          generative_config: generative_config.call,
          vectorizer_config: vectorizer_config.call
        )
        collection.config.add_property(property.new(name: "description", data_type: data_type::TEXT))
        config = collection.config.get
        expect(config.properties.map(&:name)).to include("description")
      end
    end
  end

  it "test_collection_config_create_with_deprecated_syntax" do
    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw,
      vectorizer_config: nil,
      multi_tenancy_config: configure.multi_tenancy(enabled: true, auto_tenant_creation: true),
      replication_config: configure.replication(factor: 1)
    )
    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vectorizer_config).to be_nil
    expect(config.vector_config).to be_nil
    expect(config.vectorizer).to eq(c::Vectorizers::NONE)
  end

  it "test_uncompressed_quantitizer" do
    collection_factory(name: "dummy")
    skip("uncompressed is not supported in Weaviate versions lower than 1.32.4") if version.is_lower_than(1, 32, 4)

    collection = collection_factory(
      vector_index_config: configure::VectorIndex.hnsw(
        vector_cache_max_objects: 5, quantizer: configure::VectorIndex::Quantizer.none
      )
    )

    config = collection.config.get
    expect(config.vector_index_type).to eq(c::VectorIndexType::HNSW)
    expect(config.vector_index_config).not_to be_nil
    expect(config.vector_index_config).to be_a(c::VectorIndexConfigHNSW)
    expect(config.vector_index_config.quantizer).to be_nil
  end

  it "test_object_ttl_creation" do
    collection_factory(name: "dummy")
    skip("object ttl is not supported in Weaviate versions lower than 1.35.0") if version.is_lower_than(1, 35, 0)

    collection = collection_factory(
      object_ttl: configure::ObjectTTL.delete_by_creation_time(30 * day, filter_expired_objects: true),
      inverted_index_config: configure.inverted_index(index_timestamps: true)
    )

    config = collection.config.get
    expect(config.object_ttl_config).not_to be_nil
    expect(config.object_ttl_config.delete_on).to eq("creationTime")
    expect(config.object_ttl_config.time_to_live).to eq(30 * day)
  end

  it "test_object_ttl_update_time" do
    collection_factory(name: "dummy")
    skip("object ttl is not supported in Weaviate versions lower than 1.35.0") if version.is_lower_than(1, 35, 0)

    collection = collection_factory(
      object_ttl: configure::ObjectTTL.delete_by_update_time(30 * day, filter_expired_objects: true),
      inverted_index_config: configure.inverted_index(index_timestamps: true)
    )

    config = collection.config.get
    expect(config.object_ttl_config).not_to be_nil
    expect(config.object_ttl_config.delete_on).to eq("updateTime")
    expect(config.object_ttl_config.filter_expired_objects).to be_truthy
    expect(config.object_ttl_config.time_to_live).to eq(30 * day)
  end

  it "test_object_ttl_custom" do
    collection_factory(name: "dummy")
    skip("object ttl is not supported in Weaviate versions lower than 1.35.0") if version.is_lower_than(1, 35, 0)

    collection = collection_factory(
      properties: [property.new(name: "customDate", data_type: data_type::DATE)],
      object_ttl: configure::ObjectTTL.delete_by_date_property("customDate", filter_expired_objects: false,
                                                                             ttl_offset: -1),
      inverted_index_config: configure.inverted_index(index_timestamps: true)
    )

    config = collection.config.get
    expect(config.object_ttl_config).not_to be_nil
    expect(config.object_ttl_config.delete_on).to eq("customDate")
    expect(config.object_ttl_config.time_to_live).to eq(-1)
    expect(config.object_ttl_config.filter_expired_objects).to be_falsey
  end

  it "test_object_ttl_update" do
    collection_factory(name: "dummy")
    skip("object ttl is not supported in Weaviate versions lower than 1.35.0") if version.is_lower_than(1, 35, 0)

    collection = collection_factory(
      properties: [property.new(name: "customDate", data_type: data_type::DATE),
                   property.new(name: "customDate2", data_type: data_type::DATE)],
      inverted_index_config: configure.inverted_index(index_timestamps: true)
    )

    conf = collection.config.get
    expect(conf.object_ttl_config).to be_nil

    collection.config.update(
      object_ttl_config: reconfigure::ObjectTTL.delete_by_date_property(
        property_name: "customDate", filter_expired_objects: true, ttl_offset: 3600
      )
    )

    conf = collection.config.get
    expect(conf.object_ttl_config).not_to be_nil
    expect(conf.object_ttl_config.delete_on).to eq("customDate")
    expect(conf.object_ttl_config.time_to_live).to eq(3600)
    expect(conf.object_ttl_config.filter_expired_objects).to be_truthy

    collection.config.update(
      object_ttl_config: reconfigure::ObjectTTL.delete_by_update_time(filter_expired_objects: false)
    )

    conf = collection.config.get
    expect(conf.object_ttl_config).not_to be_nil
    expect(conf.object_ttl_config.delete_on).to eq("updateTime")
    expect(conf.object_ttl_config.time_to_live).to eq(3600)
    expect(conf.object_ttl_config.filter_expired_objects).to be_falsey

    collection.config.update(
      object_ttl_config: reconfigure::ObjectTTL.delete_by_creation_time(time_to_live: 600)
    )

    conf = collection.config.get
    expect(conf.object_ttl_config).not_to be_nil
    expect(conf.object_ttl_config.delete_on).to eq("creationTime")
    expect(conf.object_ttl_config.time_to_live).to eq(600)
    expect(conf.object_ttl_config.filter_expired_objects).to be_falsey

    collection.config.update(object_ttl_config: reconfigure::ObjectTTL.disable)
    conf = collection.config.get
    expect(conf.object_ttl_config).to be_nil
  end

  it "test_object_ttl_roundtrip_from_dict" do
    collection_factory(name: "dummy")
    skip("object ttl is not supported in Weaviate versions lower than 1.35.0") if version.is_lower_than(1, 35, 0)

    collection = collection_factory(
      object_ttl: configure::ObjectTTL.delete_by_creation_time(60, filter_expired_objects: true)
    )
    config = collection.config.get
    expect(config.object_ttl_config).not_to be_nil

    name = "TestObjectTTLRoundtrip#{collection.name}"
    config.name = name
    with_local_client do |client|
      client.collections.delete(name)
      client.collections.create_from_dict(config.to_dict)
      new = client.collections.use(name).config.get
      expect(config).to eq(new)
      expect(config.to_dict).to eq(new.to_dict)
      client.collections.delete(name)
    end
  end

  # Test delete index works for each index type.
  %w[filterable searchable rangeFilters].each do |index_name|
    it "test_delete_property_index[#{index_name}]" do
      collection_factory(name: "dummy")
      skip("delete property index not supported before 1.36.0") if version.is_lower_than(1, 36, 0)

      if %w[filterable searchable].include?(index_name)
        dt = data_type::TEXT
        index_range_filters = false
        index_searchable = true
        index_filterable = true
      else
        dt = data_type::DATE
        index_range_filters = true
        index_searchable = false
        index_filterable = true
      end

      collection = collection_factory(
        properties: [
          property.new(name: "indexed_prop", data_type: dt, index_range_filters: index_range_filters,
                       index_searchable: index_searchable, index_filterable: index_filterable)
        ]
      )
      config = collection.config.get
      expect(config.properties[0].index_filterable).to be(index_filterable)
      expect(config.properties[0].index_searchable).to be(index_searchable)
      expect(config.properties[0].index_range_filters).to be(index_range_filters)

      expect do
        collection.config.delete_property_index("does_not_exist", index_name: index_name)
      end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

      collection.config.delete_property_index("indexed_prop", index_name: index_name)

      config = collection.config.get
      case index_name
      when "filterable"
        expect(config.properties[0].index_filterable).to be(false)
        expect(config.properties[0].index_searchable).to be(index_searchable)
        expect(config.properties[0].index_range_filters).to be(index_range_filters)
      when "searchable"
        expect(config.properties[0].index_searchable).to be(false)
        expect(config.properties[0].index_filterable).to be(index_filterable)
        expect(config.properties[0].index_range_filters).to be(index_range_filters)
      when "rangeFilters"
        expect(config.properties[0].index_range_filters).to be(false)
        expect(config.properties[0].index_searchable).to be(index_searchable)
        expect(config.properties[0].index_filterable).to be(index_filterable)
      end
    end
  end

  # On Weaviate < 1.37 the client must raise before sending the request.
  it "test_property_text_analyzer_ascii_fold_version_gate" do
    collection_factory(name: "dummy")
    skip("Version gate only applies to Weaviate < 1.37.0") if version.is_at_least(1, 37, 0)

    expect do
      collection_factory(
        vectorizer_config: configure::Vectorizer.none,
        properties: [
          property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                       text_analyzer: configure.text_analyzer(ascii_fold: true))
        ]
      )
    end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
  end

  # User-defined stopword presets apply to properties that reference them.
  #
  # Properties can reference user-defined presets via text_analyzer.stopword_preset,
  # and built-in presets can coexist with user-defined ones.
  it "test_collection_stopword_presets" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => %w[le la les] }),
      properties: [
        # User-defined French preset.
        property.new(name: "title_fr", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "fr")),
        # Built-in English preset, set per property.
        property.new(name: "title_en", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: c::StopwordsPreset::EN)),
        # No stopword override → uses the collection-level default.
        property.new(name: "plain", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD)
      ]
    )

    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })

    title_fr = config.properties.find { |p| p.name == "title_fr" }
    title_en = config.properties.find { |p| p.name == "title_en" }
    plain = config.properties.find { |p| p.name == "plain" }
    expect(title_fr.text_analyzer).not_to be_nil
    expect(title_fr.text_analyzer.stopword_preset).to eq("fr")
    expect(title_en.text_analyzer).not_to be_nil
    expect(title_en.text_analyzer.stopword_preset).to eq("en")
    expect(plain.text_analyzer).to be_nil
  end

  # Updating a stopword preset is reflected in the config.
  it "test_collection_stopword_presets_update" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => ["le"] }),
      properties: [
        property.new(name: "title_fr", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "fr"))
      ]
    )

    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => ["le"] })

    collection.config.update(inverted_index_config: reconfigure.inverted_index(stopword_presets: { "fr" => ["la"] }))

    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => ["la"] })
  end

  # The server rejects removing a stopword preset still referenced by a property.
  it "test_collection_stopword_presets_remove_in_use_is_rejected" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => %w[le la les] }),
      properties: [
        property.new(name: "title_fr", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "fr"))
      ]
    )

    expect do
      collection.config.update(inverted_index_config: reconfigure.inverted_index(stopword_presets: {}))
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

    # The original preset must still be present after the rejected update.
    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })
  end

  # On Weaviate < 1.37 the client must raise before sending the request.
  it "test_inverted_index_stopword_presets_version_gate" do
    collection_factory(name: "dummy")
    skip("Version gate only applies to Weaviate < 1.37.0") if version.is_at_least(1, 37, 0)

    expect do
      collection_factory(
        vectorizer_config: configure::Vectorizer.none,
        inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => %w[le la] })
      )
    end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
  end

  # Removing a preset that no property references must succeed.
  it "test_collection_stopword_presets_remove_unused_is_allowed" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(
        stopword_presets: { "fr" => %w[le la les], "es" => %w[el la los] }
      ),
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "fr"))
      ]
    )

    # Drop only 'es' (unused). 'fr' is still referenced by title.
    collection.config.update(
      inverted_index_config: reconfigure.inverted_index(stopword_presets: { "fr" => %w[le la les] })
    )
    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })
  end

  # A removed preset still referenced by a nested property must be rejected by the server.
  it "test_collection_stopword_presets_remove_referenced_by_nested_property_is_rejected" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => %w[le la les] }),
      properties: [
        property.new(
          name: "doc", data_type: data_type::OBJECT,
          nested_properties: [
            property.new(name: "body", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                         text_analyzer: configure.text_analyzer(stopword_preset: "fr"))
          ]
        )
      ]
    )

    expect do
      collection.config.update(inverted_index_config: reconfigure.inverted_index(stopword_presets: {}))
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

    # The original preset must still be present after the rejected update.
    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })
  end

  # A user-defined preset named 'en' is accepted and reflected in the config.
  it "test_collection_user_defined_stopword_preset_overrides_builtin" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "en" => ["hello"] }),
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "en"))
      ]
    )

    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "en" => ["hello"] })
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.stopword_preset).to eq("en")
  end

  # A single property may combine ascii_fold and stopword_preset.
  it "test_property_text_analyzer_combined_ascii_fold_and_stopword_preset" do
    collection_factory(name: "dummy")
    skip("text_analyzer requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(ascii_fold: true, stopword_preset: c::StopwordsPreset::EN))
      ]
    )

    config = collection.config.get
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(true)
    expect(title.text_analyzer.stopword_preset).to eq("en")
  end

  # The asciiFold setting is immutable on an existing property.
  #
  # Adding a new property via add_property is the only way to introduce a different
  # analyzer; the original property's analyzer cannot be mutated.
  it "test_property_text_analyzer_ascii_fold_immutable" do
    collection_factory(name: "dummy")
    skip("text_analyzer requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["é"]))
      ]
    )

    # The config exposes the original ignore list and there's no client API
    # surface to mutate text_analyzer on an existing property — it can only be
    # set at create time.
    config = collection.config.get
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])

    # Adding a *new* property with a different analyzer is allowed.
    collection.config.add_property(
      property.new(name: "title2", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                   text_analyzer: configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["ñ"]))
    )
    config = collection.config.get
    title = config.properties.find { |p| p.name == "title" }
    title2 = config.properties.find { |p| p.name == "title2" }
    # Original property's analyzer is unchanged.
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])
    # New property has its own analyzer.
    expect(title2.text_analyzer).not_to be_nil
    expect(title2.text_analyzer.ascii_fold_ignore).to eq(["ñ"])
  end

  it "test_stopwords_roundtrip_from_dict" do
    collection_factory(name: "dummy")
    skip("text_analyzer requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(
        stopwords_additions: ["a"], stopwords_preset: c::StopwordsPreset::EN, stopwords_removals: ["the"],
        stopword_presets: { "fr" => %w[le la les] }
      ),
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["é"],
                                                            stopword_preset: "fr"))
      ]
    )
    config = collection.config.get
    expect(config.inverted_index_config.stopwords.preset).to eq(c::StopwordsPreset::EN)
    expect(config.inverted_index_config.stopwords.removals).to eq(["the"])
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(true)
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])
    expect(title.text_analyzer.stopword_preset).to eq("fr")

    name = "TestStopwordsRoundtrip#{collection.name}"
    config.name = name
    with_local_client do |client|
      client.collections.delete(name)
      client.collections.create_from_dict(config.to_dict)
      new = client.collections.use(name).config.get
      expect(config).to eq(new)
      expect(config.to_dict).to eq(new.to_dict)
      client.collections.delete(name)
    end
  end

  it "test_stopword_presets_roundtrip_from_dict" do
    collection_factory(name: "dummy")
    skip("stopword_presets requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      inverted_index_config: configure.inverted_index(stopword_presets: { "fr" => %w[le la les] }),
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(stopword_preset: "fr"))
      ]
    )

    config = collection.config.get
    expect(config.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les] })
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.stopword_preset).to eq("fr")

    name = "TestPresetRoundtrip#{collection.name}"
    config.name = name
    with_local_client do |client|
      client.collections.delete(name)
      client.collections.create_from_dict(config.to_dict)
      new = client.collections.use(name).config.get
      expect(config).to eq(new)
      expect(config.to_dict).to eq(new.to_dict)
      client.collections.delete(name)
    end
  end

  it "test_text_analyzer_roundtrip_from_dict" do
    collection_factory(name: "dummy")
    skip("text_analyzer requires Weaviate >= 1.37.0") if version.is_lower_than(1, 37, 0)

    collection = collection_factory(
      vectorizer_config: configure::Vectorizer.none,
      properties: [
        property.new(name: "title", data_type: data_type::TEXT, tokenization: c::Tokenization::WORD,
                     text_analyzer: configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["é"],
                                                            stopword_preset: c::StopwordsPreset::EN))
      ]
    )

    config = collection.config.get
    title = config.properties.find { |p| p.name == "title" }
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(true)
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])
    expect(title.text_analyzer.stopword_preset).to eq("en")

    name = "TestAnalyzerRoundtrip#{collection.name}"
    config.name = name
    with_local_client do |client|
      client.collections.delete(name)
      client.collections.create_from_dict(config.to_dict)
      new = client.collections.use(name).config.get
      expect(config).to eq(new)
      expect(config.to_dict).to eq(new.to_dict)
      client.collections.delete(name)
    end
  end

  # Test that dropping the index of a named vector leaves the rest of the collection usable.
  it "test_delete_vector_index" do
    collection_factory(name: "dummy")
    skip("delete vector index not supported before 1.39.0") if version.is_lower_than(1, 39, 0)

    collection = collection_factory(
      properties: [property.new(name: "name", data_type: data_type::TEXT)],
      vector_config: [configure::Vectors.self_provided(name: "dropped"),
                      configure::Vectors.self_provided(name: "kept")]
    )
    collection.data.insert(properties: { "name" => "banana" }, vector: { "dropped" => [1, 2], "kept" => [3, 4] })

    config = collection.config.get
    expect(config.vector_config).not_to be_nil
    expect(config.vector_config["dropped"].vector_index_config).not_to be_a(c::VectorIndexConfigNone)

    expect(collection.config.delete_vector_index("dropped")).to be_nil

    vector_config = vector_config_without_index(collection, "dropped")
    # vectors that were not dropped keep their index
    expect(vector_config["kept"].vector_index_config).not_to be_a(c::VectorIndexConfigNone)

    # searching the vector that still has an index keeps working
    expect(collection.query.near_vector([3, 4], target_vector: "kept").objects.length).to eq(1)
  end
end
