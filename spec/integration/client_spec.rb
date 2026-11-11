# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_client.py.
#
# Not ported: the async-client tests (test_async_client_connect_and_close,
# test_async_client_as_context_manager, test_async_client_with_extra_options,
# test_async_client_is_ready, test_async_client_is_live, test_async_client_inside_sync_client,
# test_sync_client_inside_async_client, test_async_client_connects_even_if_pypi_fails) - the async
# client is out of scope for the Ruby port.
module Batch5Specs
  RSpec.describe "client", :integration do
    include Batch5Helpers

    wcs_host = "piblpmmdsiknacjnm1ltla.c1.europe-west3.gcp.weaviate.cloud"
    wcs_url = "https://#{wcs_host}"
    wcs_grpc_host = "grpc-#{wcs_host}"
    wcs_creds = Weaviate::Classes::Init::Auth.api_key("cy4ua772mBlMdfw3YnclqAWzFhQt0RLIN0sl")

    let(:wcs_host) { wcs_host }
    let(:wcs_url) { wcs_url }
    let(:wcs_grpc_host) { wcs_grpc_host }
    let(:wcs_creds) { wcs_creds }

    # Python's module-scoped `client` fixture (connects to the default instance with init checks).
    let(:client) { client_factory }

    # Tests that talk to the Weaviate Cloud test cluster need internet access; the native setup is offline.
    def skip_without_wcs!
      skip_if_native!("needs network access to the Weaviate Cloud test cluster")
    end

    it "test_fail_to_connect_to_inactive_grpc_port" do
      expect do
        Weaviate::WeaviateClient.new(
          connection_params: Weaviate::Connect::ConnectionParams.from_url("http://localhost:#{default_port}", 12_345),
          skip_init_checks: false
        ).connect
      end.to raise_error(Weaviate::Exceptions::WeaviateGRPCUnavailableError)
    end

    it "test_fail_to_connect_with_bad_wcs_url" do
      skip_without_wcs!
      expect do
        Weaviate.connect_to_wcs(cluster_url: "#{wcs_url}bad", auth_credentials: wcs_creds).connect
      end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
    end

    [
      { http_secure: false, http_host: wcs_host, http_port: 443, grpc_secure: true, grpc_host: wcs_grpc_host,
        grpc_port: 443 },
      { http_secure: true, http_host: wcs_host, http_port: 80, grpc_secure: true, grpc_host: wcs_grpc_host,
        grpc_port: 443 },
      { http_secure: true, http_host: "#{wcs_host}bad", http_port: 443, grpc_secure: true, grpc_host: wcs_grpc_host,
        grpc_port: 443 }
    ].each_with_index do |bad_config, i|
      it "test_fail_to_connect_with_bad_custom_wcs_setup_rest[bad_config#{i}]" do
        skip_without_wcs!
        expect do
          Weaviate.connect_to_custom(**bad_config, auth_credentials: wcs_creds)
        end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
      end
    end

    [
      { http_secure: true, http_host: wcs_host, http_port: 443, grpc_secure: false, grpc_host: wcs_grpc_host,
        grpc_port: 443 },
      { http_secure: true, http_host: wcs_host, http_port: 443, grpc_secure: true, grpc_host: "#{wcs_grpc_host}bad",
        grpc_port: 443 },
      { http_secure: true, http_host: wcs_host, http_port: 443, grpc_secure: true, grpc_host: wcs_grpc_host,
        grpc_port: 80 }
    ].each_with_index do |bad_config, i|
      it "test_fail_to_connect_with_bad_custom_wcs_setup_grpc[bad_config#{i}]" do
        skip_without_wcs!
        expect do
          Weaviate.connect_to_custom(**bad_config, auth_credentials: wcs_creds)
        end.to raise_error(Weaviate::Exceptions::WeaviateGRPCUnavailableError)
      end
    end

    it "test_fail_to_connect_with_bad_custom_wcs_setup_rest_and_grpc" do
      skip_without_wcs!
      # REST checks take precedence over gRPC checks.
      expect do
        Weaviate.connect_to_custom(
          http_secure: true, http_host: "#{wcs_host}bad", http_port: 443,
          grpc_secure: true, grpc_host: "#{wcs_grpc_host}bad", grpc_port: 443,
          auth_credentials: wcs_creds
        )
      end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
    end

    it "test_connect_to_wcs" do
      skip_without_wcs!
      Weaviate.connect_to_wcs(cluster_url: wcs_url, auth_credentials: wcs_creds, &:get_meta)
    end

    it "test_create_get_and_delete" do
      name = node_name
      client.collections.delete(name)

      col = client.collections.create(name, vectorizer_config: Config::Configure::Vectorizer.none)
      expect(client.collections.exists(name)).to be true
      expect(col).to be_a(Weaviate::Collections::Collection)

      col = client.collections.use(name)
      expect(col).to be_a(Weaviate::Collections::Collection)

      client.collections.delete(name)
      expect(client.collections.exists(name)).to be false
    end

    it "test_delete_multiple" do
      name1 = node_name
      name2 = "#{node_name}2"
      client.collections.delete([name1, name2])

      client.collections.create(name1, vectorizer_config: Config::Configure::Vectorizer.none)
      client.collections.create(name2, vectorizer_config: Config::Configure::Vectorizer.none)
      expect(client.collections.exists(name1)).to be true
      expect(client.collections.exists(name2)).to be true

      client.collections.delete([name1, name2])
      expect(client.collections.exists(name1)).to be false
      expect(client.collections.exists(name2)).to be false
    end

    it "test_create_raw_get_and_delete" do
      name = node_name
      col = client.collections.create_from_dict(
        { "class" => name, "properties" => [{ "name" => "Name", "dataType" => ["text"] }], "vectorizer" => "none" }
      )
      expect(client.collections.exists(name)).to be true
      expect(col).to be_a(Weaviate::Collections::Collection)

      col = client.collections.use(name)
      expect(col).to be_a(Weaviate::Collections::Collection)

      client.collections.delete(name)
      expect(client.collections.exists(name)).to be false
    end

    it "test_create_export_and_recreate" do
      skip_if_native!("needs the text2vec-contextionary module")
      name1 = node_name
      name2 = "#{node_name}2"
      client.collections.delete([name1, name2])

      col = client.collections.create(
        name1,
        vectorizer_config: Config::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false),
        generative_config: Config::Configure::Generative.cohere(model: "command-r-plus", k: 10),
        properties: [
          Config::Property.new(name: "name", data_type: Config::DataType::TEXT, description: "desc",
                               index_filterable: true, index_searchable: true, skip_vectorization: true,
                               vectorize_property_name: true),
          Config::Property.new(name: "name_vectorized", data_type: Config::DataType::TEXT, description: "desc",
                               index_filterable: true, index_searchable: true, skip_vectorization: false,
                               vectorize_property_name: false)
        ],
        references: [Config::ReferenceProperty.new(name: "ref", target_collection: name1)]
      )
      expect(client.collections.exists(name1)).to be true
      expect(col).to be_a(Weaviate::Collections::Collection)

      export = client.collections.export_config(name1)
      expect(export).to be_a(Weaviate::Classes::Config::CollectionConfig)
      export.name = name2

      col = client.collections.create_from_config(export)
      expect(client.collections.exists(name2)).to be true
      expect(col).to be_a(Weaviate::Collections::Collection)
      export = client.collections.export_config(name2)
      expect(export.properties.length).to eq(2)
      expect(export.properties[0].description).to eq("desc")
      expect(export.references.length).to eq(1)
      expect(export.properties[0].index_searchable).to be_truthy
      expect(export.vectorizer_config).not_to be_nil
      expect(export.vectorizer_config.vectorizer).to eq(Config::Vectorizers::TEXT2VEC_CONTEXTIONARY)
      expect(export.vectorizer_config.vectorize_collection_name).to be_falsey

      expect(export.generative_config).not_to be_nil
      expect(export.generative_config.generative).to eq(Config::GenerativeSearches::COHERE)
      expect(export.generative_config.model["model"]).to eq("command-r-plus")
      expect(export.generative_config.model["k"]).to eq(10)

      client.collections.delete([name1, name2])
      expect(client.collections.exists(name1)).to be false
      expect(client.collections.exists(name2)).to be false
    end

    it "test_create_export_and_recreate_named_vectors" do
      skip_if_native!("needs the text2vec-contextionary module")
      name1 = node_name
      name2 = "#{node_name}2"
      client.collections.delete([name1, name2])

      col = client.collections.create(
        name1,
        properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT,
                                          vectorize_property_name: true)],
        vectorizer_config: [
          Config::Configure::NamedVectors.text2vec_contextionary("name", source_properties: ["name"],
                                                                         vectorize_collection_name: false),
          Config::Configure::NamedVectors.none("custom", vector_index_config: Config::Configure::VectorIndex.flat)
        ]
      )
      conf = col.config.get
      conf.name = name2

      col2 = client.collections.create_from_config(conf)

      conf2 = col2.config.get
      expect(conf2.vector_config).to eq(conf.vector_config)

      client.collections.delete([name1, name2])
    end

    it "test_collection_name_capitalization" do
      name_small = "collectionCapitalizationTest"
      name_big = "CollectionCapitalizationTest"
      begin
        collection = client.collections.create(name_small, vectorizer_config: Config::Configure::Vectorizer.none)
        expect(collection.name).to eq(name_big)
        client.collections.delete(name_small)
        expect(client.collections.exists(name_small)).to be false
        expect(client.collections.exists(name_big)).to be false
      ensure
        client.collections.delete(name_big)
      end
    end

    it "test_client_cluster_without_lazy_shard_loading" do
      collection = client.collections.create(node_name, vectorizer_config: Config::Configure::Vectorizer.none)

      nodes = client.cluster.nodes(collection.name, output: "verbose")
      expect(nodes.length).to eq(1)
      expect(nodes[0].shards.length).to eq(1)
      expect(nodes[0].shards[0].collection).to eq(collection.name)
      expect(nodes[0].shards[0].object_count).to eq(0)
      expect(%w[READONLY INDEXING READY LAZY_LOADING]).to include(nodes[0].shards[0].vector_indexing_status)
      expect(nodes[0].shards[0].vector_queue_length).to eq(0)
      expect(nodes[0].shards[0].compressed).to be false
      expect(nodes[0].shards[0].loaded).to be true
    ensure
      client.collections.delete(node_name)
    end

    it "test_client_cluster_multitenant" do
      collection = client.collections.create(
        node_name,
        multi_tenancy_config: Config::Configure.multi_tenancy(enabled: true),
        vectorizer_config: Config::Configure::Vectorizer.none
      )

      nodes = client.cluster.nodes(collection.name, output: "verbose")
      expect(nodes.length).to eq(1)
      expect(nodes[0].shards.length).to eq(0)
    ensure
      client.collections.delete(node_name)
    end

    it "test_client_cluster_minimal" do
      collection = client.collections.create(node_name, vectorizer_config: Config::Configure::Vectorizer.none)

      nodes = client.cluster.nodes(collection.name, output: "minimal")
      expect(nodes.length).to eq(1)
      expect(nodes[0].shards).to be_nil
    ensure
      client.collections.delete(node_name)
    end

    it "test_client_cluster_statistics" do
      # GET /v1/cluster/statistics - RAFT cluster statistics.
      stats = client.cluster.statistics
      expect(stats).to respond_to(:statistics)
      expect(stats).to respond_to(:synchronized)
      expect(stats.statistics).to be_a(Array)
      expect([true, false]).to include(stats.synchronized)
      stats.statistics.each do |node|
        expect(node).to respond_to(:name)
        expect(node).to respond_to(:status)
        expect(node).to respond_to(:raft)
        expect(node.raft).to respond_to(:state)
        expect(["Leader", "Follower", "Candidate", ""]).to include(node.raft.state)
      end
    end

    it "test_client_connect_and_close" do
      client = Weaviate::WeaviateClient.new(connection_params: default_connection_params, skip_init_checks: false)
      client.connect
      expect(client.is_connected).to be true
      client.get_meta
      expect(client.is_live).to be true

      client.close
      expect(client.is_connected).to be false
      expect { client.get_meta }.to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
    end

    it "test_client_as_context_manager" do
      # Python `with WeaviateClient(...) as client:` connects and closes; Ruby: connect + ensure close.
      client = Weaviate::WeaviateClient.new(connection_params: default_connection_params, skip_init_checks: false)
      begin
        client.connect
        expect(client.is_connected).to be true
        client.get_meta
        expect(client.is_live).to be true
      ensure
        client.close
      end

      expect(client.is_connected).to be false
      expect { client.get_meta }.to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
    end

    it "test_connect_to_wrong_wcs" do
      expect do
        Weaviate.connect_to_wcs(cluster_url: "does-not-exist", auth_credentials: wcs_creds, skip_init_checks: true)
      end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
    end

    it "test_connect_to_wrong_local" do
      expect do
        Weaviate.connect_to_local(host: "does-not-exist", skip_init_checks: true)
      end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
    end

    it "test_connect_to_wrong_custom" do
      expect do
        Weaviate.connect_to_custom(
          http_host: "does-not-exist", http_port: 1234, http_secure: false,
          grpc_host: "does-not-exist", grpc_port: 2345, grpc_secure: false, skip_init_checks: true
        )
      end.to raise_error(Weaviate::Exceptions::WeaviateStartUpError)
    end

    it "test_rest_call_without_connect" do
      client = Weaviate::WeaviateClient.new(connection_params: default_connection_params)
      expect { client.get_meta }.to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
    end

    it "test_grpc_call_without_connect" do
      client = Weaviate::WeaviateClient.new(connection_params: default_connection_params)
      expect do
        client.collections.use("does-not-exist").query.fetch_objects
      end.to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
    end

    it "test_client_with_skip_init_check" do
      connect_to_default_local(skip_init_checks: true) do |client|
        client.collections.delete(node_name)
        col = client.collections.create(
          node_name,
          vectorizer_config: Config::Configure::Vectorizer.none,
          properties: [
            Config::Property.new(name: "name", data_type: Config::DataType::TEXT),
            Config::Property.new(name: "age", data_type: Config::DataType::INT)
          ]
        )

        col.data.insert({ "name" => "Name" })

        obj = col.query.fetch_objects.objects[0]
        expect(obj.properties["name"]).to eq("Name")
        client.collections.delete(node_name)
      end
    end

    [[1, 2], Weaviate::Config::Timeout.new(query: 1, insert: 2, init: 2)].each_with_index do |timeout, i|
      it "test_client_with_extra_options[timeout#{i}]" do
        skip_without_wcs!
        additional_config = Weaviate::Classes::Init::AdditionalConfig.new(timeout: timeout, trust_env: true)

        [
          -> { Weaviate.connect_to_wcs(cluster_url: wcs_url, auth_credentials: wcs_creds, additional_config: additional_config) },
          lambda {
            Weaviate.connect_to_weaviate_cloud(cluster_url: wcs_url, auth_credentials: wcs_creds,
                                               additional_config: additional_config)
          },
          -> { connect_to_default_local(additional_config: additional_config) },
          lambda {
            Weaviate.connect_to_custom(http_secure: true, http_host: wcs_host, http_port: 443, grpc_secure: true,
                                       grpc_host: wcs_grpc_host, grpc_port: 443, auth_credentials: wcs_creds,
                                       additional_config: additional_config)
          }
        ].each do |make|
          client = make.call
          expect(client.connection.timeout_config).to eq(Weaviate::Config::Timeout.new(query: 1, insert: 2, init: 2))
          client.close
        end
      end
    end

    it "test_client_error_for_wcs_without_auth" do
      skip_without_wcs!
      expect do
        Weaviate.connect_to_wcs(cluster_url: wcs_url, auth_credentials: nil)
      end.to raise_error(Weaviate::Exceptions::AuthenticationFailedError)
    end

    it "test_client_is_not_ready" do
      expect(
        Weaviate::WeaviateClient.new(connection_params: default_connection_params, skip_init_checks: true).is_ready
      ).to be false
    end

    it "test_client_is_ready" do
      skip_without_wcs!
      Weaviate.connect_to_wcs(cluster_url: wcs_url, auth_credentials: wcs_creds, skip_init_checks: true) do |client|
        expect(client.is_ready).to be true
      end
    end

    it "test_client_is_not_live" do
      expect(
        Weaviate::WeaviateClient.new(connection_params: default_connection_params, skip_init_checks: true).is_live
      ).to be false
    end

    it "test_client_is_live" do
      skip_without_wcs!
      Weaviate.connect_to_wcs(cluster_url: wcs_url, auth_credentials: wcs_creds, skip_init_checks: true) do |client|
        expect(client.is_live).to be true
      end
    end

    it "test_client_is_not_live_with_wrong_rest_port" do
      connect_to_default_local(skip_init_checks: true) do |client|
        # Simulate a wrong REST port after connecting.
        client.connection.instance_variable_set(:@url, "http://localhost:9000")
        expect(client.is_live).to be false
      end
    end

    it "test_client_is_not_live_with_wrong_grpc_port" do
      connect_to_default_local(skip_init_checks: true) do |client|
        # Simulate a wrong gRPC port after connecting (the health stub is built per ping).
        client.connection.connection_params.grpc.port = 90_000
        client.connection.instance_variable_set(:@grpc_stub, nil)
        expect(client.is_live).to be false
      end
    end

    it "test_local_proxies" do
      skip_if_native!("needs the docker-compose proxy containers on :8075/:10000")
      connect_to_default_local(
        additional_config: Weaviate::Classes::Init::AdditionalConfig.new(
          proxies: Weaviate::Classes::Init::Proxies.new(http: "http://localhost:8075", grpc: "http://localhost:10000")
        )
      ) do |client|
        client.collections.delete("TestLocalProxies")
        collection = client.collections.create(
          "TestLocalProxies",
          properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)],
          vectorizer_config: Config::Configure::Vectorizer.none
        )
        collection.data.insert({ "name" => "Test" })
        expect(collection.query.fetch_objects.objects[0].properties["name"]).to eq("Test")
      end
    end

    it "test_sync_client_connects_even_if_pypi_fails" do
      previous = ENV.fetch("PYPI_PACKAGE_URL", nil)
      ENV["PYPI_PACKAGE_URL"] = "http://does-not-exist"
      connect_to_default_local { |client| expect(client.is_ready).to be true }
    ensure
      ENV["PYPI_PACKAGE_URL"] = previous
    end
  end
end
