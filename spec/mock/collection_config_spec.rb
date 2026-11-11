# frozen_string_literal: true

require "spec_helper"

# Port of the collections / collection.config tests in mock_tests/test_collection.py
RSpec.describe "collection config (mock)" do
  include_context "mock weaviate"

  let(:c) { Weaviate::Classes::Config }

  # Python `with weaviate.connect_to_local(...) as client:`
  def with_client
    client = connect_mock_client(skip_init_checks: true)
    yield client
  ensure
    client&.close
  end

  def sharding_and_friends
    {
      "properties" => [],
      "invertedIndexConfig" => {
        "bm25" => { "b" => 0.75, "k1" => 1.2 },
        "cleanupIntervalSeconds" => 60,
        "stopwords" => { "preset" => "en", "additions" => nil, "removals" => nil }
      },
      "multiTenancyConfig" => { "enabled" => false },
      "replicationConfig" => { "factor" => 1, "deletionStrategy" => "NoAutomatedResolution" },
      "shardingConfig" => {
        "virtualPerPhysical" => 128,
        "desiredCount" => 1,
        "actualCount" => 1,
        "desiredVirtualCount" => 128,
        "actualVirtualCount" => 128,
        "key" => "_id",
        "strategy" => "hash",
        "function" => "murmur3"
      }
    }
  end

  it "test_insufficient_permissions" do
    httpserver.expect_request("/v1/schema/Test")
              .respond_with_json({ "error" => [{ "message" => "this is an error" }] }, status: 403)

    client = connect_mock_client(skip_init_checks: true)
    collection = client.collections.use("Test")

    expect { collection.config.get }.to raise_error(Weaviate::Exceptions::InsufficientPermissionsError) { |e|
      expect(e.message).to include("this is an error")
    }
    expect { collection.config.get }.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError) { |e|
      expect(e.status_code).to eq(403)
    }

    httpserver.check_assertions
  ensure
    client&.close
  end

  it "test_closed_connection" do
    auth_mock!
    client = Weaviate::Client.new(
      connection_params: Weaviate::Connect::ConnectionParams.new(
        grpc: Weaviate::Connect::ProtocolParams.new(host: MockContext::MOCK_IP, port: MockContext::MOCK_PORT_GRPC,
                                                    secure: false),
        http: Weaviate::Connect::ProtocolParams.new(host: MockContext::MOCK_IP, port: MockContext::MOCK_PORT,
                                                    secure: false)
      )
    )
    # (the query / data parts of the Python test live in the query and data specs)
    expect { client.collections.list_all }.to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
  end

  it "test_missing_multi_tenancy_config" do
    vic = c::VectorIndexConfigFlat.new(quantizer: nil, distance_metric: c::VectorDistances::COSINE,
                                       vector_cache_max_objects: 10, multi_vector: nil)
    response_json = c::CollectionConfig.new(
      name: "Test",
      description: "",
      generative_config: nil,
      reranker_config: nil,
      vectorizer_config: nil,
      vector_config: nil,
      object_ttl_config: nil,
      inverted_index_config: c::InvertedIndexConfig.new(
        bm25: c::BM25Config.new(b: 0, k1: 0),
        cleanup_interval_seconds: 0,
        index_null_state: false,
        index_property_length: false,
        index_timestamps: false,
        stopwords: c::StopwordsConfig.new(preset: c::StopwordsPreset::NONE, additions: [], removals: [])
      ),
      multi_tenancy_config: c::MultiTenancyConfig.new(enabled: true, auto_tenant_creation: false,
                                                       auto_tenant_activation: false),
      sharding_config: c::ShardingConfig.new(virtual_per_physical: 0, desired_count: 0, actual_count: 0,
                                             desired_virtual_count: 0, actual_virtual_count: 0, key: "",
                                             strategy: "", function: ""),
      properties: [],
      references: [],
      replication_config: c::ReplicationConfig.new(
        factor: 0, async_enabled: false,
        deletion_strategy: c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION
      ),
      vector_index_config: vic,
      vector_index_type: c::VectorIndexType::FLAT,
      vectorizer: c::Vectorizers::NONE
    ).to_dict
    # Python sets `vic.distance = vic.distance_metric` so the server-side key is present
    response_json["vectorIndexConfig"]["distance"] ||= response_json["vectorIndexConfig"]["distanceMetric"]

    httpserver.expect_request("/v1/schema/TestTrue").respond_with_json(response_json, status: 200)
    client = connect_mock_client(skip_init_checks: true)
    conf = client.collections.use("TestTrue").config.get
    expect(conf.multi_tenancy_config.enabled).to be(true)

    # Delete the missing configuration for multi tenancy
    response_json = response_json.merge("name" => "TestFalse")
    response_json.delete("multiTenancyConfig")
    httpserver.expect_request("/v1/schema/TestFalse").respond_with_json(response_json, status: 200)
    client2 = connect_mock_client(skip_init_checks: true)
    conf = client2.collections.use("TestFalse").config.get
    expect(conf.multi_tenancy_config.enabled).to be(false)
  ensure
    client&.close
    client2&.close
  end

  it "test_return_from_bind_module" do
    auth_mock!
    # point of this test is to check if the return from the bind module is correctly parsed.
    # There is no skip and vectorizePropertyName present
    prop_modconf = { "multi2vec-bind" => {} }

    hnsw_config = {
      "cleanupIntervalSeconds" => 1, "distance" => "cosine", "dynamicEfFactor" => 1, "dynamicEfMax" => 1,
      "dynamicEfMin" => 1, "ef" => 1, "efConstruction" => 1, "flatSearchCutoff" => 1, "maxConnections" => 1,
      "vectorCacheMaxObjects" => 1, "skip" => true
    }
    ii_config = {
      "bm25" => { "b" => 1, "k1" => 1 }, "cleanupIntervalSeconds" => 1, "indexTimestamps" => true,
      "indexPropertyLength" => true, "indexNullState" => true,
      "stopwords" => { "preset" => "en", "additions" => [], "removals" => [] }
    }
    schema = {
      "class" => "TestBindCollection",
      "properties" => [
        { "dataType" => ["text"], "name" => "name", "indexFilterable" => false, "indexSearchable" => false,
          "moduleConfig" => prop_modconf }
      ],
      "vectorIndexConfig" => hnsw_config,
      "vectorIndexType" => "hnsw",
      "invertedIndexConfig" => ii_config,
      "multiTenancyConfig" => { "enabled" => true },
      "vectorizer" => "multi2vec-bind",
      "replicationConfig" => { "factor" => 2, "asyncEnabled" => false },
      "moduleConfig" => { "multi2vec-bind" => {} }
    }
    httpserver.expect_request("/v1/schema/TestBindCollection").respond_with_json(schema, status: 200)
    client = connect_mock_client(skip_init_checks: true)
    conf = client.collections.use("TestBindCollection").config.get

    expect(conf.properties[0].vectorizer_config).not_to be_nil
    expect(conf.properties[0].vectorizer_config.skip).to be(false)
    expect(conf.properties[0].vectorizer_config.vectorize_property_name).to be(false)
  ensure
    client&.close
  end

  [
    [-> { Weaviate::Integrations.cohere(api_key: "key") }, { "X-Cohere-Api-Key" => "key" }],
    [
      -> { Weaviate::Integrations.cohere(api_key: "key", requests_per_minute_embeddings: 50, base_url: "http://some-url.com") },
      { "X-Cohere-Api-Key" => "key", "X-Cohere-Ratelimit-RequestPM-Embedding" => "50",
        "X-Cohere-Baseurl" => "http://some-url.com" }
    ],
    [-> { [Weaviate::Integrations.cohere(api_key: "key")] }, { "X-Cohere-Api-Key" => "key" }],
    [
      -> { [Weaviate::Integrations.cohere(api_key: "key"), Weaviate::Integrations.openai(api_key: "key2")] },
      { "X-Cohere-Api-Key" => "key", "X-Openai-Api-Key" => "key2" }
    ],
    [
      lambda {
        [Weaviate::Integrations.voyageai(api_key: "key", base_url: "http://some-url.com",
                                         requests_per_minute_embeddings: 50)]
      },
      { "X-Voyageai-Api-Key" => "key", "X-Voyageai-Ratelimit-RequestPM-Embedding" => "50",
        "X-Voyageai-Baseurl" => "http://some-url.com" }
    ],
    [
      lambda {
        [Weaviate::Integrations.jinaai(api_key: "key", base_url: "http://some-url.com",
                                       requests_per_minute_embeddings: 50)]
      },
      { "X-Jinaai-Api-Key" => "key", "X-Jinaai-Ratelimit-RequestPM-Embedding" => "50",
        "X-Jinaai-Baseurl" => "http://some-url.com" }
    ]
  ].each_with_index do |(integrations, headers), i|
    it "test_integration_config[#{i}]" do
      no_auth_mock!
      client = connect_mock_client
      client.integrations.configure(integrations.call)

      httpserver.expect_request("/v1/schema", headers: headers).respond_with_json({ "classes" => [] }, status: 200)

      client.collections.list_all # return is irrelevant
      httpserver.check_assertions
    ensure
      client&.close
    end
  end

  it "test_collection_exists" do
    non_existing = "NonExistingCollection"
    erroring = "ErroringCollection"
    httpserver.expect_request("/v1/schema/#{non_existing}")
              .respond_with_json({ "error" => [{ "message" => "collection not found" }] }, status: 404)
    httpserver.expect_request("/v1/schema/#{erroring}")
              .respond_with_json({ "error" => [{ "message" => "this is an error" }] }, status: 500)

    with_client do |client|
      expect(client.collections.exists(non_existing)).to be(false)
      expect { client.collections.exists("") }.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
      expect { client.collections.exists(erroring) }
        .to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError) { |e| expect(e.status_code).to eq(500) }
    end
  end

  it "test_delete_vector_index" do
    # the collection name is capitalized by the client before it hits the path
    httpserver.expect_request("/v1/schema/Test/vectors/vec/index", method: "DELETE").respond_with_json({}, status: 200)
    httpserver.expect_request("/v1/schema/Test/vectors/missing/index", method: "DELETE")
              .respond_with_json({ "error" => [{ "message" => "vector index missing not found" }] }, status: 422)
    httpserver.expect_request("/v1/schema/Test/vectors/disabled/index", method: "DELETE")
              .respond_with_json(
                { "error" => [{ "message" => "alter schema drop vector index endpoint is experimental and disabled by default" }] },
                status: 500
              )

    with_client do |client|
      expect(client.collections.use("test").config.delete_vector_index("vec")).to be_nil

      # a non-OK answer (e.g. unknown vector name) surfaces as UnexpectedStatusCodeError
      expect { client.collections.use("test").config.delete_vector_index("missing") }
        .to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError) { |e| expect(e.status_code).to eq(422) }

      # a disabled experimental endpoint answers 500; the server message must reach the exception
      expect { client.collections.use("test").config.delete_vector_index("disabled") }
        .to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError) { |e|
          expect(e.status_code).to eq(500)
          expect(e.message).to include("experimental and disabled by default")
        }

      expect { client.collections.use("test").config.delete_vector_index(42) }
        .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    end
  end

  it "test_get_shards_parses_all_statuses" do
    httpserver.expect_request("/v1/schema/Test/shards", method: "GET").respond_with_json(
      [
        { "name" => "shard1", "status" => "UNAVAILABLE", "vectorQueueSize" => 0,
          "per_node_status" => { "node1" => "READY", "node2" => "UNAVAILABLE" } },
        { "name" => "shard2", "status" => "RECOVERING", "vectorQueueSize" => 3 }
      ],
      status: 200
    )

    shards = with_client { |client| client.collections.use("test").config.get_shards }

    expect(shards).to eq(
      [
        c::ShardStatus.new(name: "shard1", status: "UNAVAILABLE", vector_queue_size: 0,
                           per_node_status: { "node1" => "READY", "node2" => "UNAVAILABLE" }),
        c::ShardStatus.new(name: "shard2", status: "RECOVERING", vector_queue_size: 3, per_node_status: nil)
      ]
    )
  end

  it "test_create_from_dict_skips_dropped_vectors" do
    bodies = []
    httpserver.expect_request("/v1/schema", method: "POST").respond_with_handler do |req|
      body = req.json
      bodies << body
      [200, { "content-type" => "application/json" }, JSON.generate({ "class" => body["class"] })]
    end

    hnsw_entry = { "vectorizer" => { "none" => {} }, "vectorIndexType" => "hnsw", "vectorIndexConfig" => {} }
    dropped_entry = { "vectorizer" => { "none" => {} }, "vectorIndexType" => "none" }

    with_client do |client|
      _, warnings = Weaviate::Warnings.capture do
        client.collections.create_from_dict(
          { "class" => "TestDropped", "vectorConfig" => { "dropped" => dropped_entry, "kept" => hnsw_entry } }
        )
      end
      expect(warnings.join("\n")).to match(/Col001.*dropped/)
      expect(bodies[-1]["vectorConfig"]).to eq({ "kept" => hnsw_entry })

      # a create whose vectorConfig would end up empty is rejected
      requests_before = bodies.length
      expect do
        client.collections.create_from_dict({ "class" => "TestAllDropped", "vectorConfig" => { "only" => dropped_entry } })
      end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /legacy/)
      expect(bodies.length).to eq(requests_before)

      # once the drops finished, the export carries no vectorConfig; create_from_config must reject it
      cleaned_up_export = Weaviate::Collections::Config::ConfigMethods.collection_config_from_json(
        { "class" => "TestAllDroppedCleanedUp" }.merge(sharding_and_friends)
      )
      expect { client.collections.create_from_config(cleaned_up_export) }
        .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /legacy/)
      expect(bodies.length).to eq(requests_before)
    end
  end

  # --- additional Ruby coverage for the collections / config namespaces -----------------

  it "creates, lists, deletes collections and adds a property" do
    created = []
    httpserver.expect_request("/v1/schema", method: "POST").respond_with_handler do |req|
      created << req.json
      [200, { "content-type" => "application/json" }, JSON.generate({ "class" => req.json["class"] })]
    end
    schema = { "class" => "Things", "vectorizer" => "none", "moduleConfig" => {} }.merge(sharding_and_friends)
    httpserver.expect_request("/v1/schema", method: "GET").respond_with_json(
      { "classes" => [schema.merge("class" => "Zeta"), schema] }
    )
    httpserver.expect_request("/v1/schema/Things", method: "GET").respond_with_json(schema)
    added = []
    httpserver.expect_request("/v1/schema/Things/properties", method: "POST").respond_with_handler do |req|
      added << req.json
      [200, { "content-type" => "application/json" }, "{}"]
    end
    deleted = []
    httpserver.expect_request(%r{\A/v1/schema/\w+\z}, method: "DELETE").respond_with_handler do |req|
      deleted << req.path
      [200, { "content-type" => "application/json" }, "{}"]
    end

    with_client do |client|
      collection = client.collections.create_from_dict({ "class" => "things" })
      expect(collection).to be_a(Weaviate::Collections::Collection)
      expect(collection.name).to eq("Things")

      all = client.collections.list_all
      expect(all.keys).to eq(%w[Things Zeta])
      expect(all["Things"]).to be_a(c::CollectionConfigSimple)
      expect(client.collections.list_all(simple: false)["Zeta"]).to be_a(c::CollectionConfig)
      expect(client.collections.export_config("things").name).to eq("Things")

      client.collections.use("things").config.add_property(c::Property.new(name: "title", data_type: c::DataType::TEXT))
      expect(added.last).to include("name" => "title", "dataType" => ["text"])

      client.collections.delete(%w[a b])
      client.collections.delete_all
      expect(deleted).to eq(%w[/v1/schema/A /v1/schema/B /v1/schema/Things /v1/schema/Zeta])
      expect { client.collections.list_all(simple: 1) }.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    end
  end
end
