# frozen_string_literal: true

require "spec_helper"

# Port of test/collection/test_config_methods.py
RSpec.describe Weaviate::Collections::Config::ConfigMethods do
  let(:cm) { described_class }
  let(:c) { Weaviate::Classes::Config }

  def hnsw_config
    {
      "skip" => false,
      "cleanupIntervalSeconds" => 300,
      "maxConnections" => 64,
      "efConstruction" => 128,
      "ef" => -1,
      "dynamicEfMin" => 100,
      "dynamicEfMax" => 500,
      "dynamicEfFactor" => 8,
      "vectorCacheMaxObjects" => 1_000_000_000_000,
      "flatSearchCutoff" => 40_000,
      "distance" => "cosine"
    }
  end

  def hfresh_config
    {
      "distance" => "cosine",
      "maxPostingSizeKB" => 48,
      "replicas" => 4,
      "searchProbe" => 256,
      "rq" => { "enabled" => true, "bits" => 1, "rescoreLimit" => 350, "trainingLimit" => 0 }
    }
  end

  def common_schema_parts
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

  # Build a minimal collection schema, as returned by Weaviate, around the given vectorConfig.
  def schema_with_vector_config(vector_config)
    { "class" => "TestCollection", "vectorConfig" => vector_config }.merge(common_schema_parts)
  end

  # Schema of a named-vector collection whose vectors were all dropped.
  def schema_without_any_vector
    { "class" => "TestCollection" }.merge(common_schema_parts)
  end

  it "test_collection_config_from_json_with_dropped_vector_index" do
    schema = schema_with_vector_config(
      "dropped" => { "vectorizer" => { "none" => {} }, "vectorIndexType" => "none" },
      "kept" => { "vectorizer" => { "none" => {} }, "vectorIndexType" => "hnsw", "vectorIndexConfig" => hnsw_config }
    )

    config = cm.collection_config_from_json(schema)

    expect(config.vector_config).not_to be_nil
    expect(config.vector_config["dropped"].vector_index_config).to be_a(c::VectorIndexConfigNone)
    expect(config.vector_config["dropped"].vector_index_config.vector_index_type).to eq("none")
    expect(config.vector_config["kept"].vector_index_config).not_to be_a(c::VectorIndexConfigNone)

    as_dict = config.to_dict
    expect(as_dict["vectorConfig"]["dropped"]["vectorIndexType"]).to eq(c::VectorIndexType::NONE)
    expect(as_dict["vectorConfig"]["dropped"]).not_to have_key("vectorIndexConfig")
    expect(as_dict["vectorConfig"]["kept"]["vectorIndexType"]).to eq(c::VectorIndexType::HNSW)
  end

  [
    { "enabled" => true, "aggregation" => "maxSim" },
    {
      "enabled" => true,
      "aggregation" => "maxSim",
      "muvera" => { "enabled" => true, "ksim" => 4, "dprojections" => 16, "repetitions" => 10 }
    }
  ].each_with_index do |multivector, i|
    it "test_collection_config_to_dict_keeps_multivector[#{i}]" do
      schema = schema_with_vector_config(
        "colbert" => {
          "vectorizer" => { "none" => {} },
          "vectorIndexType" => "hnsw",
          "vectorIndexConfig" => hnsw_config.merge("multivector" => multivector)
        },
        "regular" => { "vectorizer" => { "none" => {} }, "vectorIndexType" => "hnsw",
                       "vectorIndexConfig" => hnsw_config }
      )

      as_dict = cm.collection_config_from_json(schema).to_dict

      expect(as_dict["vectorConfig"]["colbert"]["vectorIndexConfig"]["multivector"]).to eq(multivector)
      expect(as_dict["vectorConfig"]["colbert"]["vectorIndexConfig"]).not_to have_key("multiVector")
      expect(as_dict["vectorConfig"]["regular"]["vectorIndexConfig"]).not_to have_key("multivector")
    end
  end

  [
    [
      { "enabled" => true, "aggregation" => "",
        "muvera" => { "enabled" => true, "ksim" => 4, "dprojections" => 16, "repetitions" => 10 } },
      lambda {
        c::MultiVectorConfig.new(aggregation: "",
                                 encoding: c::MuveraConfig.new(enabled: true, ksim: 4, dprojections: 16, repetitions: 10))
      }
    ],
    [
      { "enabled" => true, "aggregation" => "",
        "muvera" => { "enabled" => false, "ksim" => 4, "dprojections" => 16, "repetitions" => 10 } },
      -> { c::MultiVectorConfig.new(aggregation: "", encoding: nil) }
    ],
    [
      { "enabled" => false, "aggregation" => "",
        "muvera" => { "enabled" => false, "ksim" => 4, "dprojections" => 16, "repetitions" => 10 } },
      -> {}
    ],
    # servers before 1.40 omit the multivector block for HFresh
    [nil, -> {}]
  ].each_with_index do |(multivector, expected), i|
    it "test_collection_config_from_json_hfresh_multi_vector[#{i}]" do
      index_config = hfresh_config
      index_config["multivector"] = multivector unless multivector.nil?
      schema = schema_with_vector_config(
        "mv" => { "vectorizer" => { "none" => {} }, "vectorIndexType" => "hfresh", "vectorIndexConfig" => index_config }
      )

      config = cm.collection_config_from_json(schema)

      expect(config.vector_config).not_to be_nil
      vic = config.vector_config["mv"].vector_index_config
      expect(vic).to be_a(c::VectorIndexConfigHFresh)
      expect(vic.multi_vector).to eq(instance_exec(&expected))
      expect(vic.max_posting_size_kb).to eq(48)
      expect(vic.search_probe).to eq(256)
    end
  end

  it "test_collection_config_from_json_missing_vector_index_config_raises" do
    schema = schema_with_vector_config("broken" => { "vectorizer" => { "none" => {} }, "vectorIndexType" => "hnsw" })

    expect { cm.collection_config_from_json(schema) }
      .to raise_error(Weaviate::Exceptions::SchemaValidationError, /broken/)
  end

  it "test_collection_config_from_json_unknown_vector_index_type_raises" do
    schema = schema_with_vector_config(
      "future" => {
        "vectorizer" => { "none" => {} },
        "vectorIndexType" => "spann",
        "vectorIndexConfig" => { "distance" => "cosine", "searchListSize" => 100 }
      }
    )

    expect { cm.collection_config_from_json(schema) }
      .to raise_error(Weaviate::Exceptions::SchemaValidationError, /unknown vectorIndexType/)
  end

  it "test_collection_config_from_json_all_vectors_dropped" do
    config = cm.collection_config_from_json(schema_without_any_vector)

    expect(config.vectorizer).to be_nil
    expect(config.vector_index_type).to be_nil
    expect(config.vector_config).to be_nil
  end

  it "test_collection_config_simple_from_json_all_vectors_dropped" do
    config = cm.collection_config_simple_from_json(schema_without_any_vector)

    expect(config.vectorizer).to be_nil
    expect(config.vector_config).to be_nil
  end

  it "test_collection_config_simple_from_json_with_none_vectorizer_config" do
    schema = {
      "classes" => [
        common_schema_parts.except("multiTenancyConfig").merge(
          "class" => "TestCollection",
          "vectorConfig" => {
            "default" => {
              "vectorizer" => { "text2vec-transformers" => nil },
              "vectorIndexType" => "hnsw",
              "vectorIndexConfig" => hnsw_config
            }
          },
          "vectorIndexType" => "hnsw",
          "vectorIndexConfig" => hnsw_config
        )
      ]
    }

    configs = cm.collection_configs_simple_from_json(schema)
    expect(configs).to have_key("TestCollection")
    vec_config = configs["TestCollection"].vector_config
    expect(vec_config).not_to be_nil
    expect(vec_config).to have_key("default")
    expect(vec_config["default"].vectorizer.model).to eq({})
    expect(vec_config["default"].vectorizer.source_properties).to be_nil
  end

  def make_text_prop(name, **extra)
    {
      "name" => name,
      "dataType" => ["text"],
      "indexFilterable" => true,
      "indexSearchable" => true,
      "indexRangeFilters" => false,
      "tokenization" => "word"
    }.merge(extra.transform_keys(&:to_s))
  end

  it "test_properties_from_config_parses_text_analyzer" do
    schema = {
      "vectorizer" => "none",
      "properties" => [
        make_text_prop("title", textAnalyzer: { "asciiFold" => true, "asciiFoldIgnore" => ["é"] }),
        make_text_prop("body")
      ]
    }
    props = cm.properties_from_config(schema)
    title = props.find { |p| p.name == "title" }
    body = props.find { |p| p.name == "body" }

    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(true)
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])

    expect(body.text_analyzer).to be_nil

    # The dataclass round-trips back to the wire format.
    expect(title.to_dict["textAnalyzer"]).to eq({ "asciiFold" => true, "asciiFoldIgnore" => ["é"] })
    expect(body.to_dict).not_to have_key("textAnalyzer")
  end

  it "test_properties_from_config_text_analyzer_omitted_when_no_ascii_fold" do
    schema = {
      "vectorizer" => "none",
      "properties" => [make_text_prop("title", textAnalyzer: { "asciiFoldIgnore" => ["é"] })]
    }
    title = cm.properties_from_config(schema)[0]
    expect(title.text_analyzer).to be_nil
  end

  it "test_nested_properties_from_config_parses_text_analyzer" do
    nested = cm.nested_properties_from_config(
      [make_text_prop("title", textAnalyzer: { "asciiFold" => true, "asciiFoldIgnore" => ["ñ"] })]
    )
    expect(nested[0].text_analyzer).not_to be_nil
    expect(nested[0].text_analyzer.ascii_fold).to be(true)
    expect(nested[0].text_analyzer.ascii_fold_ignore).to eq(["ñ"])
    expect(nested[0].to_dict["textAnalyzer"]).to eq({ "asciiFold" => true, "asciiFoldIgnore" => ["ñ"] })
  end

  it "test_properties_from_config_parses_stopword_preset_only" do
    schema = {
      "vectorizer" => "none",
      "properties" => [make_text_prop("title", textAnalyzer: { "stopwordPreset" => "fr" })]
    }
    title = cm.properties_from_config(schema)[0]
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(false)
    expect(title.text_analyzer.ascii_fold_ignore).to be_nil
    expect(title.text_analyzer.stopword_preset).to eq("fr")
  end

  it "test_properties_from_config_parses_combined_text_analyzer" do
    schema = {
      "vectorizer" => "none",
      "properties" => [
        make_text_prop("title",
                       textAnalyzer: { "asciiFold" => true, "asciiFoldIgnore" => ["é"], "stopwordPreset" => "fr" })
      ]
    }
    title = cm.properties_from_config(schema)[0]
    expect(title.text_analyzer).not_to be_nil
    expect(title.text_analyzer.ascii_fold).to be(true)
    expect(title.text_analyzer.ascii_fold_ignore).to eq(["é"])
    expect(title.text_analyzer.stopword_preset).to eq("fr")
  end

  def full_schema(class_name, **inverted_overrides)
    inverted = {
      "bm25" => { "b" => 0.75, "k1" => 1.2 },
      "cleanupIntervalSeconds" => 60,
      "stopwords" => { "preset" => "en", "additions" => nil, "removals" => nil }
    }.merge(inverted_overrides.transform_keys(&:to_s))
    common_schema_parts.except("multiTenancyConfig").merge(
      "class" => class_name,
      "vectorizer" => "none",
      "invertedIndexConfig" => inverted,
      "vectorIndexType" => "hnsw",
      "vectorIndexConfig" => hnsw_config
    )
  end

  it "test_collection_config_parses_stopword_presets" do
    schema = full_schema("TestStopwordPresets",
                         stopwordPresets: { "fr" => %w[le la les], "es" => %w[el la los] })
    full = cm.collection_config_from_json(schema)
    expect(full.inverted_index_config.stopword_presets).to eq({ "fr" => %w[le la les], "es" => %w[el la los] })
  end

  it "test_collection_config_stopword_presets_absent" do
    full = cm.collection_config_from_json(full_schema("TestNoStopwordPresets"))
    expect(full.inverted_index_config.stopword_presets).to be_nil
  end
end
