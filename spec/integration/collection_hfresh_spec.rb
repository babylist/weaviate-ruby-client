# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_hfresh.py
RSpec.describe "collection hfresh", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }

  def skip_unless_hfresh!
    collection_factory(name: "dummy")
    if server_version.is_lower_than(1, 36, 0)
      skip("Hfresh index is not supported in Weaviate versions lower than 1.36.0")
    end
  end

  it "test_collection_config_hfresh" do
    skip_unless_hfresh!

    collection = collection_factory(
      vector_index_config: cfg::Configure::VectorIndex.hfresh(
        distance_metric: cfg::VectorDistances::COSINE, max_posting_size_kb: 1024, replicas: 2, search_probe: 50
      )
    )

    config = collection.config.get

    expect(config.vector_index_type).to eq(cfg::VectorIndexType::HFRESH)
    expect(config.vector_index_config).to be_a(cfg::VectorIndexConfigHFresh)
    expect(config.vector_index_config.distance_metric).to eq(cfg::VectorDistances::COSINE)
    expect(config.vector_index_config.max_posting_size_kb).to eq(1024)
    expect(config.vector_index_config.replicas).to eq(2)
    expect(config.vector_index_config.search_probe).to eq(50)
  end

  it "test_collection_named_vectors_hfresh" do
    skip_unless_hfresh!

    collection = collection_factory(
      vector_config: [
        cfg::Configure::Vectors.self_provided(
          name: "title_vec",
          vector_index_config: cfg::Configure::VectorIndex.hfresh(
            distance_metric: cfg::VectorDistances::COSINE, max_posting_size_kb: 512, replicas: 1, search_probe: 25
          )
        )
      ]
    )

    config = collection.config.get

    expect(config.vector_config).not_to be_nil
    expect(config.vector_config).to have_key("title_vec")

    title_config = config.vector_config["title_vec"]
    expect(title_config.vectorizer.vectorizer).to eq(cfg::Vectorizers::NONE)
    expect(title_config.vector_index_config).to be_a(cfg::VectorIndexConfigHFresh)
    expect(title_config.vector_index_config.distance_metric).to eq(cfg::VectorDistances::COSINE)
    expect(title_config.vector_index_config.max_posting_size_kb).to eq(512)
    expect(title_config.vector_index_config.replicas).to eq(1)
    expect(title_config.vector_index_config.search_probe).to eq(25)
  end

  it "test_collection_update_hfresh" do
    skip_unless_hfresh!

    collection = collection_factory(
      vector_index_config: cfg::Configure::VectorIndex.hfresh(
        distance_metric: cfg::VectorDistances::COSINE, max_posting_size_kb: 512, replicas: 1, search_probe: 25
      )
    )

    config = collection.config.get
    expect(config.vector_index_config).to be_a(cfg::VectorIndexConfigHFresh)
    expect(config.vector_index_config.max_posting_size_kb).to eq(512)
    expect(config.vector_index_config.replicas).to eq(1)
    expect(config.vector_index_config.search_probe).to eq(25)

    collection.config.update(vectorizer_config: cfg::Reconfigure::VectorIndex.hfresh(search_probe: 100))

    config = collection.config.get
    expect(config.vector_index_config).to be_a(cfg::VectorIndexConfigHFresh)
    expect(config.vector_index_config.max_posting_size_kb).to eq(512)
    expect(config.vector_index_config.replicas).to eq(1)
    expect(config.vector_index_config.search_probe).to eq(100)
  end

  it "test_collection_hfresh_export_and_reimport" do
    skip_unless_hfresh!

    collection = collection_factory(
      vector_index_config: cfg::Configure::VectorIndex.hfresh(
        distance_metric: cfg::VectorDistances::COSINE, max_posting_size_kb: 1024, replicas: 2, search_probe: 50
      )
    )

    config = collection.config.get

    name = "TestHFreshExportAndReimport_#{collection.name}"
    config.name = name
    # Python opens a second `weaviate.connect_to_local()` client; the shared client points at the same instance.
    client = client_factory
    client.collections.delete(name)
    begin
      client.collections.create_from_dict(config.to_dict)
      new = client.collections.use(name).config.get
      expect(config).to eq(new)
      expect(config.to_dict).to eq(new.to_dict)
    ensure
      client.collections.delete(name)
    end
  end

  it "test_collection_hfresh_multi_vector_muvera" do
    collection_factory(name: "dummy")
    if server_version.is_lower_than(1, 40, 0)
      skip("Multi-vector HFresh is not supported in Weaviate versions lower than 1.40.0")
    end

    collection = collection_factory(
      vector_config: [
        cfg::Configure::MultiVectors.self_provided(
          name: "colbert",
          encoding: cfg::Configure::VectorIndex::MultiVector::Encoding.muvera(ksim: 4, dprojections: 16,
                                                                               repetitions: 10),
          vector_index_config: cfg::Configure::VectorIndex.hfresh
        )
      ]
    )

    config = collection.config.get

    expect(config.vector_config).not_to be_nil
    index_config = config.vector_config["colbert"].vector_index_config
    expect(index_config).to be_a(cfg::VectorIndexConfigHFresh)
    expect(index_config.multi_vector).not_to be_nil
    expect(index_config.multi_vector.encoding).to be_a(cfg::MuveraConfig)
    expect(index_config.multi_vector.encoding.ksim).to eq(4)
    expect(index_config.multi_vector.encoding.dprojections).to eq(16)
    expect(index_config.multi_vector.encoding.repetitions).to eq(10)
  end
end
