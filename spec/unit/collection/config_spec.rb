# frozen_string_literal: true

# Port of test/collection/test_config.py (schema config classes; vectorizer / named-vector /
# Configure::Vectors parameter tables live in config_vectorizers_spec.rb).
RSpec.describe "collection config" do # rubocop:disable RSpec/DescribeClass
  c = Weaviate::Classes::Config

  defaults = {
    "vectorConfig" => {
      "default" => {
        "vectorIndexType" => "hnsw",
        "vectorizer" => {
          "none" => {}
        }
      }
    }
  }

  def capture_warnings(&block)
    Weaviate::Warnings.capture(&block).last
  end

  it "test_basic_config" do
    config = c::CollectionConfigCreate.new(name: "test", description: "test")
    expect(config.to_dict).to eq({ **defaults, "class" => "Test", "description" => "test" })
  end

  describe "test_config_with_vectorizer_and_properties" do
    cases = lambda do
      [
        [
          c::Configure::Vectorizer.text2vec_transformers,
          [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true,
                           vectorize_property_name: false)],
          { "text2vec-transformers" => { "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } },
          [{ "dataType" => ["text"], "name" => "text",
             "moduleConfig" => { "text2vec-transformers" => { "skip" => true, "vectorizePropertyName" => false } } }]
        ],
        [
          c::Configure::Vectorizer.text2vec_jinaai,
          [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true,
                           vectorize_property_name: false)],
          { "text2vec-jinaai" => { "vectorizeClassName" => true } },
          [{ "dataType" => ["text"], "name" => "text",
             "moduleConfig" => { "text2vec-jinaai" => { "skip" => true, "vectorizePropertyName" => false } } }]
        ],
        [
          c::Configure::Vectorizer.text2vec_transformers,
          [c::Property.new(name: "text", data_type: c::DataType::TEXT)],
          { "text2vec-transformers" => { "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } },
          [{ "dataType" => ["text"], "name" => "text",
             "moduleConfig" => { "text2vec-transformers" => { "skip" => false, "vectorizePropertyName" => true } } }]
        ]
      ]
    end

    3.times do |i|
      it "case #{i}" do
        vectorizer_config, properties, expected_mc, expected_props = cases.call[i]
        config = c::CollectionConfigCreate.new(name: "test", properties: properties,
                                               vectorizer_config: vectorizer_config)
        expect(config.to_dict).to eq(
          "vectorIndexType" => "hnsw",
          "vectorizer" => vectorizer_config.vectorizer,
          "class" => "Test",
          "properties" => expected_props,
          "moduleConfig" => expected_mc
        )
      end
    end
  end

  it "test_config_with_vector_config_warns_on_skip_vectorization" do
    config = c::CollectionConfigCreate.new(
      name: "test",
      properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true)],
      vector_config: c::Configure::Vectors.text2vec_transformers
    )
    warnings = capture_warnings { config.to_dict }
    expect(warnings).to include(a_string_including("Dep032"))
  end

  describe "test_config_property_flags_do_not_warn" do
    cases = lambda do
      [
        # flag not set at all
        { properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT)],
          vector_config: c::Configure::Vectors.text2vec_transformers },
        # legacy path maps the flag, so it does take effect
        { properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true)],
          vectorizer_config: c::Configure::Vectorizer.text2vec_transformers },
        # nothing is vectorized, so the flag is moot
        { properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true)],
          vector_config: c::Configure::Vectors.self_provided },
        { properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true)] }
      ]
    end

    4.times do |i|
      it "case #{i}" do
        config = c::CollectionConfigCreate.new(name: "test", **cases.call[i])
        expect(capture_warnings { config.to_dict }).to be_empty
      end
    end
  end

  describe "test_config_with_generative" do
    test_config_with_generative = [
      [
          c::Configure::Generative.openai(),
          {"generative-openai" => {}},
      ],
      [
          c::Configure::Generative.nvidia(),
          {"generative-nvidia" => {}},
      ],
      [
          c::Configure::Generative.nvidia(
              base_url: "https://integrate.api.nvidia.com",
              model: "model",
              temperature: 0.5,
              max_tokens: 100,
              top_p: 0.5,
          ),
          {
              "generative-nvidia" => {
                  "baseURL" => "https://integrate.api.nvidia.com",
                  "model" => "model",
                  "temperature" => 0.5,
                  "maxTokens" => 100,
                  "topP" => 0.5,
              }
          },
      ],
      [
          c::Configure::Generative.anyscale(),
          {"generative-anyscale" => {}},
      ],
      [
          c::Configure::Generative.friendliai(
              temperature: 0.5, max_tokens: 100, model: "model", base_url: "https://api.custom.ai"
          ),
          {
              "generative-friendliai" => {
                  "temperature" => 0.5,
                  "maxTokens" => 100,
                  "model" => "model",
                  "baseURL" => "https://api.custom.ai",
              }
          },
      ],
      [
          c::Configure::Generative.mistral(temperature: 0.5, max_tokens: 100, model: "model"),
          {"generative-mistral" => {"temperature" => 0.5, "maxTokens" => 100, "model" => "model"}},
      ],
      [
          c::Configure::Generative.ollama(
              model: "cool-model",
              api_endpoint: "https://123.456.789.0",
          ),
          {
              "generative-ollama" => {
                  "model" => "cool-model",
                  "apiEndpoint" => "https://123.456.789.0",
              }
          },
      ],
      [
          c::Configure::Generative.openai(
              model: "gpt-4",
              frequency_penalty: 0.5,
              max_tokens: 100,
              presence_penalty: 0.5,
              temperature: 0.5,
              top_p: 0.5,
              base_url: "https://api.openai.com",
              reasoning_effort: "high",
              verbosity: "verbose",
          ),
          {
              "generative-openai" => {
                  "model" => "gpt-4",
                  "frequencyPenalty" => 0.5,
                  "maxTokens" => 100,
                  "presencePenalty" => 0.5,
                  "temperature" => 0.5,
                  "topP" => 0.5,
                  "baseURL" => "https://api.openai.com/",
                  "reasoningEffort" => "high",
                  "verbosity" => "verbose",
              }
          },
      ],
      [c::Configure::Generative.cohere(), {"generative-cohere" => {}}],
      [
          c::Configure::Generative.cohere(
              model: "model",
              k: 10,
              max_tokens: 100,
              stop_sequences: ["stop"],
              temperature: 0.5,
              base_url: "https://api.cohere.ai",
          ),
          {
              "generative-cohere" => {
                  "model" => "model",
                  "k" => 10,
                  "maxTokens" => 100,
                  "stopSequences" => ["stop"],
                  "temperature" => 0.5,
                  "baseURL" => "https://api.cohere.ai/",
              }
          },
      ],
      [
          c::Configure::Generative.google("project"),
          {
              "generative-palm" => {
                  "projectId" => "project",
              }
          },
      ],
      [
          c::Configure::Generative.google(
              "project",
              api_endpoint: "https://api.google.com",
              max_output_tokens: 100,
              model_id: "model",
              temperature: 0.5,
              top_k: 10,
              top_p: 0.5,
          ),
          {
              "generative-palm" => {
                  "projectId" => "project",
                  "apiEndpoint" => "https://api.google.com",
                  "maxOutputTokens" => 100,
                  "modelId" => "model",
                  "temperature" => 0.5,
                  "topK" => 10,
                  "topP" => 0.5,
              }
          },
      ],
      [
          c::Configure::Generative.google_vertex("project"),
          {
              "generative-palm" => {
                  "projectId" => "project",
              }
          },
      ],
      [
          c::Configure::Generative.google_vertex(
              "project",
              api_endpoint: "https://api.google.com",
              region: "europe-west4",
              location: "europe-west4",
              max_output_tokens: 100,
              model_id: "model",
              endpoint_id: "endpoint",
              temperature: 0.5,
              top_k: 10,
              top_p: 0.5,
          ),
          {
              "generative-palm" => {
                  "projectId" => "project",
                  "apiEndpoint" => "https://api.google.com",
                  "region" => "europe-west4",
                  "location" => "europe-west4",
                  "maxOutputTokens" => 100,
                  "modelId" => "model",
                  "endpointId" => "endpoint",
                  "temperature" => 0.5,
                  "topK" => 10,
                  "topP" => 0.5,
              }
          },
      ],
      [
          c::Configure::Generative.aws(
              model: "cohere.command-light-text-v14",
              region: "us-east-1",
              service: "bedrock",
              endpoint: "custom-endpoint",
              max_tokens: 100,
          ),
          {
              "generative-aws" => {
                  "model" => "cohere.command-light-text-v14",
                  "region" => "us-east-1",
                  "service" => "bedrock",
                  "endpoint" => "custom-endpoint",
                  "maxTokens" => 100,
              }
          },
      ],
      [
          c::Configure::Generative.azure_openai("name", deployment_id: "id"),
          {
              "generative-openai" => {
                  "deploymentId" => "id",
                  "resourceName" => "name",
              }
          },
      ],
      [
          c::Configure::Generative.azure_openai(
              "name",
              deployment_id: "id",
              frequency_penalty: 0.5,
              max_tokens: 100,
              presence_penalty: 0.5,
              temperature: 0.5,
              top_p: 0.5,
              base_url: "https://api.openai.com",
              api_version: "2024-06-01",
          ),
          {
              "generative-openai" => {
                  "resourceName" => "name",
                  "deploymentId" => "id",
                  "frequencyPenalty" => 0.5,
                  "maxTokens" => 100,
                  "presencePenalty" => 0.5,
                  "temperature" => 0.5,
                  "topP" => 0.5,
                  "baseURL" => "https://api.openai.com/",
                  "apiVersion" => "2024-06-01",
              }
          },
      ],
      [
          c::Configure::Generative.anthropic(
              model: "model",
              max_tokens: 100,
              stop_sequences: ["stop"],
              temperature: 0.5,
              top_k: 10,
              top_p: 0.5,
              base_url: "https://api.anthropic.com",
          ),
          {
              "generative-anthropic" => {
                  "model" => "model",
                  "maxTokens" => 100,
                  "stopSequences" => ["stop"],
                  "temperature" => 0.5,
                  "topK" => 10,
                  "topP" => 0.5,
                  "baseURL" => "https://api.anthropic.com",
              }
          },
      ],
      [
          c::Configure::Generative.databricks(endpoint: "https://api.databricks.com"),
          {
              "generative-databricks" => {
                  "endpoint" => "https://api.databricks.com",
              }
          },
      ],
      [
          c::Configure::Generative.databricks(
              endpoint: "https://api.databricks.com",
              max_tokens: 100,
              temperature: 0.5,
              top_k: 10,
              top_p: 0.5,
          ),
          {
              "generative-databricks" => {
                  "endpoint" => "https://api.databricks.com",
                  "maxTokens" => 100,
                  "temperature" => 0.5,
                  "topK" => 10,
                  "topP" => 0.5,
              }
          },
      ],
      [
          c::Configure::Generative.deepseek(
              model: "deepseek-chat",
              max_tokens: 100,
              temperature: 0.5,
              frequency_penalty: 0.1,
              presence_penalty: 0.2,
              top_p: 0.9,
              base_url: "https://api.deepseek.com",
              stop: ["\n"],
          ),
          {
              "generative-deepseek" => {
                  "model" => "deepseek-chat",
                  "maxTokens" => 100,
                  "temperature" => 0.5,
                  "frequencyPenalty" => 0.1,
                  "presencePenalty" => 0.2,
                  "topP" => 0.9,
                  "baseURL" => "https://api.deepseek.com",
                  "stop" => ["\n"],
              }
          },
      ],
      [
          c::Configure::Generative.digitalocean(
              base_url: "https://inference.do-ai.run",
              model: "llama-4-maverick",
              temperature: 0.5,
              top_p: 0.9,
              max_tokens: 100,
              frequency_penalty: 0.1,
              presence_penalty: 0.2,
              stop: ["STOP"],
          ),
          {
              "generative-digitalocean" => {
                  "baseURL" => "https://inference.do-ai.run",
                  "model" => "llama-4-maverick",
                  "temperature" => 0.5,
                  "topP" => 0.9,
                  "maxTokens" => 100,
                  "frequencyPenalty" => 0.1,
                  "presencePenalty" => 0.2,
                  "stop" => ["STOP"],
              }
          },
      ],
      [
          c::Configure::Generative.digitalocean(),
          {"generative-digitalocean" => {}},
      ],
      [
          c::Configure::Generative.meta(
              base_url: "https://api.meta.ai",
              model: "muse-spark-1.2",
              temperature: 0.5,
              top_p: 0.9,
              max_tokens: 100,
              frequency_penalty: 0.1,
              presence_penalty: 0.2,
              reasoning_effort: "xhigh",
          ),
          {
              "generative-meta" => {
                  "baseURL" => "https://api.meta.ai",
                  "model" => "muse-spark-1.2",
                  "temperature" => 0.5,
                  "topP" => 0.9,
                  "maxTokens" => 100,
                  "frequencyPenalty" => 0.1,
                  "presencePenalty" => 0.2,
                  "reasoningEffort" => "xhigh",
              }
          },
      ],
      [
          c::Configure::Generative.meta(),
          {"generative-meta" => {}},
      ],
      [
          c::Configure::Generative.xai(
              model: "grok-2-latest",
              max_tokens: 100,
              temperature: 0.5,
              base_url: "https://api.x.ai/v1",
          ),
          {
              "generative-xai" => {
                  "model" => "grok-2-latest",
                  "maxTokens" => 100,
                  "temperature" => 0.5,
                  "baseURL" => "https://api.x.ai/v1",
              }
          },
      ],
      [
          c::Configure::Generative.contextualai(),
          {
              "generative-contextualai" => {},
          },
      ],
      [
          c::Configure::Generative.contextualai(
              model: "v2",
              temperature: 0.7,
              top_p: 0.9,
              max_new_tokens: 512,
              system_prompt: "You are a helpful assistant that provides accurate and informative responses based on the given context.",
              avoid_commentary: false,
              knowledge: ["fact1", "fact2"],
          ),
          {
              "generative-contextualai" => {
                  "model" => "v2",
                  "temperature" => 0.7,
                  "topP" => 0.9,
                  "maxNewTokens" => 512,
                  "systemPrompt" => "You are a helpful assistant that provides accurate and informative responses based on the given context.",
                  "avoidCommentary" => false,
                  "knowledge" => ["fact1", "fact2"],
              }
          },
      ],
    ]

    test_config_with_generative.each_with_index do |(generative_config, expected_mc), i|
      it "case #{i} (#{expected_mc.keys.first})" do
        config = c::CollectionConfigCreate.new(name: "test", generative_config: generative_config)
        expect(config.to_dict).to eq({ **defaults, "class" => "Test", "moduleConfig" => expected_mc })
      end
    end
  end

  describe "test_config_with_reranker" do
    test_config_with_reranker = [
      [
          c::Configure::Reranker.cohere(model: "model", base_url: "https://some.base.url/"),
          {
              "reranker-cohere" => {
                  "model" => "model",
                  "baseURL" => "https://some.base.url/",
              },
          },
      ],
      [
          c::Configure::Reranker.cohere(),
          {
              "reranker-cohere" => {},
          },
      ],
      [
          c::Configure::Reranker.voyageai(),
          {
              "reranker-voyageai" => {},
          },
      ],
      [
          c::Configure::Reranker.voyageai(model: "rerank-lite-1"),
          {
              "reranker-voyageai" => {"model" => "rerank-lite-1"},
          },
      ],
      [
          c::Configure::Reranker.jinaai(),
          {
              "reranker-jinaai" => {},
          },
      ],
      [
          c::Configure::Reranker.jinaai(model: "jina-reranker-v2-base-multilingual"),
          {
              "reranker-jinaai" => {"model" => "jina-reranker-v2-base-multilingual"},
          },
      ],
      [
          c::Configure::Reranker.nvidia(),
          {
              "reranker-nvidia" => {},
          },
      ],
      [
          c::Configure::Reranker.nvidia(
              model: "nvidia/llama-3.2-nv-rerankqa-1b-v2",
              base_url: "https://integrate.api.nvidia.com/v1",
          ),
          {
              "reranker-nvidia" => {
                  "model" => "nvidia/llama-3.2-nv-rerankqa-1b-v2",
                  "baseURL" => "https://integrate.api.nvidia.com/v1",
              },
          },
      ],
      [
          c::Configure::Reranker.transformers(),
          {
              "reranker-transformers" => {},
          },
      ],
      [
          c::Configure::Reranker.contextualai(),
          {
              "reranker-contextualai" => {},
          },
      ],
      [
          c::Configure::Reranker.contextualai(
              model: "ctxl-rerank-v2-instruct-multilingual",
              instruction: "Prioritize recent documents",
              top_n: 5,
          ),
          {
              "reranker-contextualai" => {
                  "model" => "ctxl-rerank-v2-instruct-multilingual",
                  "instruction" => "Prioritize recent documents",
                  "topN" => 5,
              }
          },
      ],
    ]

    test_config_with_reranker.each_with_index do |(reranker_config, expected_mc), i|
      it "case #{i} (#{expected_mc.keys.first})" do
        config = c::CollectionConfigCreate.new(name: "test", reranker_config: reranker_config)
        expect(config.to_dict).to eq({ **defaults, "class" => "Test", "moduleConfig" => expected_mc })
      end
    end
  end

  describe "test_config_create_with_properties" do
    vectorizer_configs = lambda do
      [
        c::Configure::Vectorizer.none,
        c::Configure::Vectorizer.text2vec_contextionary,
        [
          c::Configure::NamedVectors.text2vec_cohere("one"),
          c::Configure::NamedVectors.text2vec_openai("two")
        ]
      ]
    end

    props = [
      { "dataType" => ["text"], "name" => "text" },
      { "dataType" => ["text[]"], "name" => "text_array" },
      { "dataType" => ["int"], "name" => "int" },
      { "dataType" => ["int[]"], "name" => "int_array" },
      { "dataType" => ["number"], "name" => "number" },
      { "dataType" => ["number[]"], "name" => "number_array" },
      { "dataType" => ["boolean"], "name" => "bool" },
      { "dataType" => ["boolean[]"], "name" => "bool_array" },
      { "dataType" => ["date"], "name" => "date" },
      { "dataType" => ["date[]"], "name" => "date_array" },
      { "dataType" => ["uuid"], "name" => "uuid" },
      { "dataType" => ["uuid[]"], "name" => "uuid_array" },
      { "dataType" => ["geoCoordinates"], "name" => "geo" },
      { "dataType" => ["blob"], "name" => "blob" },
      { "dataType" => ["blobHash"], "name" => "blob_hash" },
      { "dataType" => ["phoneNumber"], "name" => "phone_number" }
    ]

    3.times do |i|
      it "case #{i}" do
        vectorizer_config = vectorizer_configs.call[i]
        config = c::CollectionConfigCreate.new(
          name: "test",
          description: "test",
          vectorizer_config: vectorizer_config,
          properties: [
            c::Property.new(name: "text", data_type: c::DataType::TEXT),
            c::Property.new(name: "text_array", data_type: c::DataType::TEXT_ARRAY),
            c::Property.new(name: "int", data_type: c::DataType::INT),
            c::Property.new(name: "int_array", data_type: c::DataType::INT_ARRAY),
            c::Property.new(name: "number", data_type: c::DataType::NUMBER),
            c::Property.new(name: "number_array", data_type: c::DataType::NUMBER_ARRAY),
            c::Property.new(name: "bool", data_type: c::DataType::BOOL),
            c::Property.new(name: "bool_array", data_type: c::DataType::BOOL_ARRAY),
            c::Property.new(name: "date", data_type: c::DataType::DATE),
            c::Property.new(name: "date_array", data_type: c::DataType::DATE_ARRAY),
            c::Property.new(name: "uuid", data_type: c::DataType::UUID),
            c::Property.new(name: "uuid_array", data_type: c::DataType::UUID_ARRAY),
            c::Property.new(name: "geo", data_type: c::DataType::GEO_COORDINATES),
            c::Property.new(name: "blob", data_type: c::DataType::BLOB),
            c::Property.new(name: "blob_hash", data_type: c::DataType::BLOB_HASH),
            c::Property.new(name: "phone_number", data_type: c::DataType::PHONE_NUMBER)
          ]
        )

        expected = props.map do |prop|
          if vectorizer_config.is_a?(c::VectorizerConfigCreate)
            next prop if vectorizer_config.vectorizer == c::Vectorizers::NONE

            next prop.merge("moduleConfig" => {
                              vectorizer_config.vectorizer => { "skip" => false, "vectorizePropertyName" => true }
                            })
          end
          prop.merge("moduleConfig" => vectorizer_config.to_h do |conf|
            [conf.vectorizer.vectorizer, { "skip" => false, "vectorizePropertyName" => true }]
          end)
        end

        out = config.to_dict
        expect(out["class"]).to eq("Test")
        expect(out["description"]).to eq("test")
        expect(out["properties"]).to eq(expected)
      end
    end
  end

  it "test_config_with_invalid_property_id" do
    expect do
      c::CollectionConfigCreate.new(name: "test", description: "test",
                                    properties: [c::Property.new(name: "id", data_type: c::DataType::TEXT)])
    end.to raise_error(Weaviate::Exceptions::WeaviateInsertInvalidPropertyError)
  end

  %w[vector].each do |name|
    it "test_config_with_invalid_property[#{name}]" do
      expect do
        c::CollectionConfigCreate.new(name: "test", description: "test",
                                      properties: [c::Property.new(name: name, data_type: c::DataType::TEXT)])
      end.to raise_error(ArgumentError)
    end
  end

  %w[id vector].each do |name|
    it "test_config_with_invalid_reference_property[#{name}]" do
      expect do
        c::CollectionConfigCreate.new(name: "test", description: "test",
                                      properties: [c::ReferenceProperty.new(name: name, to: "Test")])
      end.to raise_error(ArgumentError)
      expect do
        c::ReferenceProperty.new(name: name, target_collection: "Test")
      end.to raise_error(c::ValidationError)
    end
  end

  it "test_vector_config_hnsw_bq" do
    vector_index = c::Configure::VectorIndex.hnsw(
      ef_construction: 128, quantizer: c::Configure::VectorIndex::Quantizer.bq(rescore_limit: 123)
    )
    vi_dict = vector_index.to_dict
    expect(vi_dict["efConstruction"]).to eq(128)
    expect(vi_dict["bq"]["rescoreLimit"]).to eq(123)
  end

  it "test_vector_config_hnsw_sq" do
    vector_index = c::Configure::VectorIndex.hnsw(
      ef_construction: 128,
      quantizer: c::Configure::VectorIndex::Quantizer.sq(rescore_limit: 123, training_limit: 5012)
    )
    vi_dict = vector_index.to_dict
    expect(vi_dict["efConstruction"]).to eq(128)
    expect(vi_dict["sq"]["rescoreLimit"]).to eq(123)
    expect(vi_dict["sq"]["trainingLimit"]).to eq(5012)
  end

  it "test_vector_config_hnsw_rq" do
    vector_index = c::Configure::VectorIndex.hnsw(
      ef_construction: 128,
      quantizer: c::Configure::VectorIndex::Quantizer.rq(bits: 8, rescore_limit: 123)
    )
    vi_dict = vector_index.to_dict
    expect(vi_dict["efConstruction"]).to eq(128)
    expect(vi_dict["rq"]["bits"]).to eq(8)
    expect(vi_dict["rq"]["rescoreLimit"]).to eq(123)
  end

  it "test_vector_config_hnsw_rq4c" do
    vector_index = c::Configure::VectorIndex.hnsw(
      ef_construction: 128,
      quantizer: c::Configure::VectorIndex::Quantizer.rq(bits: 4, centering: true, rescore_limit: 123,
                                                         training_limit: 5012)
    )
    vi_dict = vector_index.to_dict
    expect(vi_dict["efConstruction"]).to eq(128)
    expect(vi_dict["rq"]["bits"]).to eq(4)
    expect(vi_dict["rq"]["centering"]).to be(true)
    expect(vi_dict["rq"]["rescoreLimit"]).to eq(123)
    expect(vi_dict["rq"]["trainingLimit"]).to eq(5012)
  end

  it "test_vector_config_hnsw_pathseer_filter_strategy" do
    vector_index = c::Configure::VectorIndex.hnsw(filter_strategy: c::VectorFilterStrategy::PATHSEER)
    expect(vector_index.to_dict["filterStrategy"]).to eq("pathseer")
  end

  it "test_vector_config_flat_pq" do
    vector_index = c::Configure::VectorIndex.flat(
      distance_metric: c::VectorDistances::DOT,
      vector_cache_max_objects: 456,
      quantizer: c::Configure::VectorIndex::Quantizer.pq(segments: 789)
    )
    vi_dict = vector_index.to_dict
    expect(vi_dict["distance"]).to eq("dot")
    expect(vi_dict["vectorCacheMaxObjects"]).to eq(456)
    expect(vi_dict["pq"]).not_to have_key("bitCompression")
    expect(vi_dict["pq"]["segments"]).to eq(789)
  end

  describe "test_configure_with_replication" do
    cases, = Weaviate::Warnings.capture do
      [
      [c::Configure.replication(), {}],
      [
          c::Configure.replication(
              factor: 3,
              async_enabled: true,
              deletion_strategy: c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT,
          ),
          {
              "factor" => 3,
              "asyncEnabled" => true,
              "deletionStrategy" => "DeleteOnConflict",
          },
      ],
      [
          c::Configure.replication(
              async_config: c::Configure::Replication.async_config(
                  max_workers: 10,
                  hashtree_height: 5,
                  frequency: 60,
                  frequency_while_propagating: 30,
                  alive_nodes_checking_frequency: 120,
                  logging_frequency: 15,
                  diff_batch_size: 100,
                  diff_per_node_timeout: 10,
                  pre_propagation_timeout: 20,
                  propagation_timeout: 300,
                  propagation_limit: 1000,
                  propagation_delay: 5,
                  propagation_concurrency: 4,
                  propagation_batch_size: 50,
              )
          ),
          {
              "asyncConfig" => {
                  "maxWorkers" => 10,
                  "hashtreeHeight" => 5,
                  "frequency" => 60,
                  "frequencyWhilePropagating" => 30,
                  "aliveNodesCheckingFrequency" => 120,
                  "loggingFrequency" => 15,
                  "diffBatchSize" => 100,
                  "diffPerNodeTimeout" => 10,
                  "prePropagationTimeout" => 20,
                  "propagationTimeout" => 300,
                  "propagationLimit" => 1000,
                  "propagationDelay" => 5,
                  "propagationConcurrency" => 4,
                  "propagationBatchSize" => 50,
              }
          },
      ],
    ]
    end

    cases.each_with_index do |(config, expected), i|
      it "case #{i}" do
        expect(config.to_dict).to eq(expected)
      end
    end
  end

  describe "test_reconfigure_with_replication" do
    cases, = Weaviate::Warnings.capture do
      [
      [
          c::Reconfigure.replication(),
          {
              "factor" => nil,
              "asyncEnabled" => nil,
              "deletionStrategy" => nil,
              "asyncConfig" => nil,
          },
      ],
      [
          c::Reconfigure.replication(
              factor: 3,
              async_enabled: true,
              deletion_strategy: c::ReplicationDeletionStrategy::DELETE_ON_CONFLICT,
          ),
          {
              "factor" => 3,
              "asyncEnabled" => true,
              "deletionStrategy" => "DeleteOnConflict",
              "asyncConfig" => nil,
          },
      ],
      [
          c::Reconfigure.replication(
              async_config: c::Reconfigure::Replication.async_config(
                  max_workers: 10,
                  hashtree_height: 5,
                  frequency: 60,
                  frequency_while_propagating: 30,
                  alive_nodes_checking_frequency: 120,
                  logging_frequency: 15,
                  diff_batch_size: 100,
                  diff_per_node_timeout: 10,
                  pre_propagation_timeout: 20,
                  propagation_timeout: 300,
                  propagation_limit: 1000,
                  propagation_delay: 5,
                  propagation_concurrency: 4,
                  propagation_batch_size: 50,
              )
          ),
          {
              "factor" => nil,
              "asyncEnabled" => nil,
              "deletionStrategy" => nil,
              "asyncConfig" => {
                  "maxWorkers" => 10,
                  "hashtreeHeight" => 5,
                  "frequency" => 60,
                  "frequencyWhilePropagating" => 30,
                  "aliveNodesCheckingFrequency" => 120,
                  "loggingFrequency" => 15,
                  "diffBatchSize" => 100,
                  "diffPerNodeTimeout" => 10,
                  "prePropagationTimeout" => 20,
                  "propagationTimeout" => 300,
                  "propagationLimit" => 1000,
                  "propagationDelay" => 5,
                  "propagationConcurrency" => 4,
                  "propagationBatchSize" => 50,
              },
          },
      ],
    ]
    end

    cases.each_with_index do |(config, expected), i|
      it "case #{i}" do
        expect(config.model_dump).to eq(expected)
      end
    end
  end

  it "test_replication_config_to_dict_with_async_config" do
    config = c::ReplicationConfig.new(
      factor: 3,
      async_enabled: true,
      deletion_strategy: c::ReplicationDeletionStrategy::TIME_BASED_RESOLUTION,
      async_config: c::AsyncReplicationConfig.new(
        max_workers: 8,
        hashtree_height: 20,
        frequency: nil,
        frequency_while_propagating: nil,
        alive_nodes_checking_frequency: 3,
        logging_frequency: nil,
        diff_batch_size: nil,
        diff_per_node_timeout: nil,
        pre_propagation_timeout: nil,
        propagation_timeout: nil,
        propagation_limit: nil,
        propagation_delay: nil,
        propagation_concurrency: nil,
        propagation_batch_size: nil
      )
    )
    d = config.to_dict
    expect(d["factor"]).to eq(3)
    expect(d["asyncEnabled"]).to be(true)
    expect(d["deletionStrategy"]).to eq("TimeBasedResolution")
    expect(d["asyncConfig"]["maxWorkers"]).to eq(8)
    expect(d["asyncConfig"]["hashtreeHeight"]).to eq(20)
    expect(d["asyncConfig"]["aliveNodesCheckingFrequency"]).to eq(3)
  end

  it "test_replication_config_to_dict_without_async_config" do
    config = c::ReplicationConfig.new(
      factor: 1,
      async_enabled: false,
      deletion_strategy: c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION,
      async_config: nil
    )
    d = config.to_dict
    expect(d["factor"]).to eq(1)
    expect(d["asyncEnabled"]).to be(false)
    expect(d).not_to have_key("asyncConfig")
  end

  it "test_replication_config_update_merge_with_missing_async_config" do
    update = c::Reconfigure.replication(
      async_config: c::Reconfigure::Replication.async_config(max_workers: 12, propagation_concurrency: 4)
    )
    existing_schema = { "factor" => 3, "asyncEnabled" => true, "deletionStrategy" => "NoAutomatedResolution" }
    result = update.merge_with_existing(existing_schema)
    expect(result["asyncConfig"]["maxWorkers"]).to eq(12)
    expect(result["asyncConfig"]["propagationConcurrency"]).to eq(4)
    expect(result["factor"]).to eq(3)
  end

  %i[Configure Reconfigure].each do |factory|
    [true, false].each do |async_enabled|
      it "test_replication_async_enabled_emits_deprecation_warning[#{factory}-#{async_enabled}]" do
        warnings = capture_warnings { c.const_get(factory).replication(async_enabled: async_enabled) }
        expect(warnings).to include(a_string_including("Dep030"))
      end
    end

    it "test_replication_without_async_enabled_does_not_warn[#{factory}]" do
      expect(capture_warnings { c.const_get(factory).replication(factor: 3) }).to be_empty
    end
  end

  it "test_nested_property_with_id_name_is_allowed" do
    prop = c::Property.new(
      name: "nested_property",
      data_type: c::DataType::OBJECT,
      nested_properties: [c::Property.new(name: "id", data_type: c::DataType::TEXT)]
    )
    expect(prop.nestedProperties[0].name).to eq("id")
  end

  describe "Test_TextAnalyzerConfigCreate" do
    it "test_property_without_text_analyzer_omits_key" do
      prop = c::Property.new(name: "title", data_type: c::DataType::TEXT)
      expect(prop.to_dict).not_to have_key("textAnalyzer")
    end

    it "test_property_with_ascii_fold_only" do
      prop = c::Property.new(name: "title", data_type: c::DataType::TEXT,
                             text_analyzer: c::Configure.text_analyzer(ascii_fold: true))
      expect(prop.to_dict["textAnalyzer"]).to eq({ "asciiFold" => true })
    end

    it "test_property_with_ascii_fold_and_ignore" do
      prop = c::Property.new(
        name: "title",
        data_type: c::DataType::TEXT,
        tokenization: c::Tokenization::WORD,
        text_analyzer: c::Configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: %w[é ñ])
      )
      out = prop.to_dict
      expect(out["textAnalyzer"]).to eq({ "asciiFold" => true, "asciiFoldIgnore" => %w[é ñ] })
      expect(out["tokenization"]).to eq("word")
    end

    it "test_text_analyzer_rejects_ignore_without_ascii_fold" do
      expect { c::TextAnalyzerConfigCreate.new(ascii_fold_ignore: ["é"]) }.to raise_error(c::ValidationError)
    end

    it "test_nested_property_with_text_analyzer" do
      prop = c::Property.new(
        name: "meta",
        data_type: c::DataType::OBJECT,
        nested_properties: [
          c::Property.new(name: "title", data_type: c::DataType::TEXT,
                          text_analyzer: c::Configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["ñ"]))
        ]
      )
      out = prop.to_dict
      expect(out["nestedProperties"][0]["textAnalyzer"]).to eq({ "asciiFold" => true, "asciiFoldIgnore" => ["ñ"] })
    end

    it "test_text_analyzer_rejects_wrong_types" do
      expect { c::TextAnalyzerConfigCreate.new(ascii_fold: "yes") }.to raise_error(c::ValidationError)
      expect { c::TextAnalyzerConfigCreate.new(ascii_fold_ignore: "é") }.to raise_error(c::ValidationError)
    end

    it "test_text_analyzer_stopword_preset_builtin_enum" do
      prop = c::Property.new(name: "title", data_type: c::DataType::TEXT, tokenization: c::Tokenization::WORD,
                             text_analyzer: c::Configure.text_analyzer(stopword_preset: c::StopwordsPreset::EN))
      expect(prop.to_dict["textAnalyzer"]).to eq({ "stopwordPreset" => "en" })
    end

    it "test_text_analyzer_stopword_preset_user_defined_string" do
      prop = c::Property.new(name: "title_fr", data_type: c::DataType::TEXT, tokenization: c::Tokenization::WORD,
                             text_analyzer: c::Configure.text_analyzer(stopword_preset: "fr"))
      expect(prop.to_dict["textAnalyzer"]).to eq({ "stopwordPreset" => "fr" })
    end

    it "test_text_analyzer_combined_ascii_fold_and_stopword_preset" do
      prop = c::Property.new(
        name: "title", data_type: c::DataType::TEXT, tokenization: c::Tokenization::WORD,
        text_analyzer: c::Configure.text_analyzer(ascii_fold: true, ascii_fold_ignore: ["é"], stopword_preset: "fr")
      )
      expect(prop.to_dict["textAnalyzer"]).to eq(
        { "asciiFold" => true, "asciiFoldIgnore" => ["é"], "stopwordPreset" => "fr" }
      )
    end

    it "test_text_analyzer_stopword_preset_only_omits_other_keys" do
      prop = c::Property.new(name: "title", data_type: c::DataType::TEXT, tokenization: c::Tokenization::WORD,
                             text_analyzer: c::Configure.text_analyzer(stopword_preset: "fr"))
      out = prop.to_dict
      expect(out["textAnalyzer"]).not_to have_key("asciiFold")
      expect(out["textAnalyzer"]).not_to have_key("asciiFoldIgnore")
    end
  end

  describe "TestInvertedIndexStopwordPresets" do
    it "test_configure_inverted_index_with_stopword_presets" do
      ic = c::Configure.inverted_index(stopword_presets: { "fr" => %w[le la les], "es" => %w[el la los] })
      expect(ic.to_dict["stopwordPresets"]).to eq({ "fr" => %w[le la les], "es" => %w[el la los] })
    end

    it "test_configure_inverted_index_without_stopword_presets_omits_key" do
      expect(c::Configure.inverted_index.to_dict).not_to have_key("stopwordPresets")
    end

    it "test_reconfigure_inverted_index_merges_stopword_presets" do
      rc = c::Reconfigure.inverted_index(stopword_presets: { "fr" => %w[le la] })
      existing = {
        "stopwords" => { "preset" => "en", "additions" => nil, "removals" => nil },
        "bm25" => { "b" => 0.75, "k1" => 1.2 },
        "cleanupIntervalSeconds" => 60
      }
      merged = rc.merge_with_existing(existing)
      expect(merged["stopwordPresets"]).to eq({ "fr" => %w[le la] })
      # other fields untouched
      expect(merged["stopwords"]["preset"]).to eq("en")
      expect(merged["bm25"]["b"]).to eq(0.75)
    end

    it "test_reconfigure_inverted_index_replaces_existing_stopword_presets" do
      rc = c::Reconfigure.inverted_index(stopword_presets: { "fr" => ["le"] })
      existing = {
        "stopwords" => { "preset" => "en", "additions" => nil, "removals" => nil },
        "stopwordPresets" => { "fr" => %w[le la les], "es" => ["el"] }
      }
      merged = rc.merge_with_existing(existing)
      # The new value fully replaces the prior dict (server-side PUT semantics).
      expect(merged["stopwordPresets"]).to eq({ "fr" => ["le"] })
    end

    it "test_reconfigure_inverted_index_without_stopword_presets_leaves_existing" do
      rc = c::Reconfigure.inverted_index(bm25_b: 0.7, bm25_k1: 1.1)
      existing = {
        "stopwords" => { "preset" => "en", "additions" => nil, "removals" => nil },
        "bm25" => { "b" => 0.75, "k1" => 1.2 },
        "stopwordPresets" => { "fr" => %w[le la] }
      }
      merged = rc.merge_with_existing(existing)
      expect(merged["stopwordPresets"]).to eq({ "fr" => %w[le la] })
    end
  end
end
