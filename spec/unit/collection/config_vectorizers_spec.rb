# frozen_string_literal: true

require "spec_helper"

# Port of the vectorizer / named-vector / Configure.Vectors tests in
# weaviate-python-client test/collection/test_config.py. Each parameter row is
# [factory lambda, ..., expected]; lambdas defer construction so a single bad row
# fails only its own example.
module ConfigVectorizersSpecData
  include Weaviate::Classes::Config

  TEST_CONFIG_WITH_VECTORIZER_PARAMETERS = [
    [ # test_config.py:61
      -> { Configure::Vectorizer.text2vec_contextionary },
      { "text2vec-contextionary" => { "vectorizeClassName" => true } },
    ],
    [ # test_config.py:69
      -> { Configure::Vectorizer.text2vec_azure_openai("resource", deployment_id: "deployment", base_url: "https://api.openai.com", dimensions: 356) },
      { "text2vec-openai" => { "resourceName" => "resource", "deploymentId" => "deployment", "vectorizeClassName" => true, "baseURL" => "https://api.openai.com/", "dimensions" => 356, "isAzure" => true } },
    ],
    [ # test_config.py:87
      -> { Configure::Vectorizer.text2vec_cohere },
      { "text2vec-cohere" => { "vectorizeClassName" => true } },
    ],
    [ # test_config.py:95
      -> { Configure::Vectorizer.text2vec_cohere(model: "embed-multilingual-v2.0", truncate: "NONE", vectorize_collection_name: false, base_url: "https://api.cohere.ai") },
      { "text2vec-cohere" => { "model" => "embed-multilingual-v2.0", "truncate" => "NONE", "vectorizeClassName" => false, "baseURL" => "https://api.cohere.ai/" } },
    ],
    [ # test_config.py:111
      -> { Configure::Vectorizer.multi2vec_cohere(model: "embed-multilingual-v2.0", truncate: "NONE", vectorize_collection_name: false, base_url: "https://api.cohere.ai") },
      { "multi2vec-cohere" => { "model" => "embed-multilingual-v2.0", "truncate" => "NONE", "baseURL" => "https://api.cohere.ai/" } },
    ],
    [ # test_config.py:126
      -> { Configure::Vectorizer.multi2vec_voyageai(model: "voyage-multimodal-3", truncation: false, output_encoding: "base64", vectorize_collection_name: false, base_url: "https://api.voyageai.com") },
      { "multi2vec-voyageai" => { "model" => "voyage-multimodal-3", "truncation" => false, "baseURL" => "https://api.voyageai.com/" } },
    ],
    [ # test_config.py:142
      -> { Configure::Vectorizer.multi2vec_nvidia(model: "nvidia/nvclip", truncation: false, vectorize_collection_name: false, base_url: "https://integrate.api.nvidia.com") },
      { "multi2vec-nvidia" => { "model" => "nvidia/nvclip", "truncation" => false, "baseURL" => "https://integrate.api.nvidia.com/" } },
    ],
    [ # test_config.py:157
      -> { Configure::Vectorizer.text2vec_gpt4all },
      { "text2vec-gpt4all" => { "vectorizeClassName" => true } },
    ],
    [ # test_config.py:165
      -> { Configure::Vectorizer.text2vec_gpt4all(vectorize_collection_name: false) },
      { "text2vec-gpt4all" => { "vectorizeClassName" => false } },
    ],
    [ # test_config.py:175
      -> { Configure::Vectorizer.text2vec_huggingface(model: "model", wait_for_model: false, use_gpu: false, use_cache: false) },
      { "text2vec-huggingface" => { "options" => { "waitForModel" => false, "useGPU" => false, "useCache" => false }, "model" => "model", "vectorizeClassName" => true } },
    ],
    [ # test_config.py:191
      -> { Configure::Vectorizer.text2vec_huggingface(passage_model: "passageModel", query_model: "queryModel", wait_for_model: true, use_gpu: true, use_cache: true, vectorize_collection_name: false) },
      { "text2vec-huggingface" => { "options" => { "waitForModel" => true, "useGPU" => true, "useCache" => true }, "passageModel" => "passageModel", "queryModel" => "queryModel", "vectorizeClassName" => false } },
    ],
    [ # test_config.py:213
      -> { Configure::Vectorizer.text2vec_huggingface(endpoint_url: "https://api.huggingface.co") },
      { "text2vec-huggingface" => { "endpointURL" => "https://api.huggingface.co/", "vectorizeClassName" => true } },
    ],
    [ # test_config.py:224
      -> { Configure::Vectorizer.text2vec_aws(vectorize_collection_name: false, model: "cohere.embed-english-v3", region: "us-east-1") },
      { "text2vec-aws" => { "vectorizeClassName" => false, "model" => "cohere.embed-english-v3", "region" => "us-east-1", "service" => "bedrock" } },
    ],
    [ # test_config.py:237
      -> { Configure::Vectorizer.text2vec_aws(vectorize_collection_name: false, model: "cohere.embed-english-v3", region: "us-east-1", service: "bedrock", dimensions: 512) },
      { "text2vec-aws" => { "vectorizeClassName" => false, "model" => "cohere.embed-english-v3", "region" => "us-east-1", "service" => "bedrock", "dimensions" => 512 } },
    ],
    [ # test_config.py:255
      -> { Configure::Vectorizer.text2vec_aws(vectorize_collection_name: false, endpoint: "something", region: "us-east-1", service: "sagemaker") },
      { "text2vec-aws" => { "vectorizeClassName" => false, "endpoint" => "something", "region" => "us-east-1", "service" => "sagemaker" } },
    ],
    [ # test_config.py:271
      -> { Configure::Vectorizer.text2vec_databricks(vectorize_collection_name: false, endpoint: "http://api.custom.com", instruction: "instruction") },
      { "text2vec-databricks" => { "vectorizeClassName" => false, "endpoint" => "http://api.custom.com", "instruction" => "instruction" } },
    ],
    [ # test_config.py:285
      -> { Configure::Vectorizer.text2vec_ollama(vectorize_collection_name: false, model: "cool-model", api_endpoint: "https://123.0.0.4") },
      { "text2vec-ollama" => { "vectorizeClassName" => false, "model" => "cool-model", "apiEndpoint" => "https://123.0.0.4" } },
    ],
    [ # test_config.py:299
      -> { Configure::Vectorizer.text2vec_openai },
      { "text2vec-openai" => { "vectorizeClassName" => true, "isAzure" => false } },
    ],
    [ # test_config.py:303
      -> { Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false, model: "ada", model_version: "002", type_: "text", base_url: "https://api.openai.com", dimensions: 100) },
      { "text2vec-openai" => { "vectorizeClassName" => false, "model" => "ada", "modelVersion" => "002", "type" => "text", "baseURL" => "https://api.openai.com/", "dimensions" => 100, "isAzure" => false } },
    ],
    [ # test_config.py:324
      -> { Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false, model: "ada", endpoint: "/api/v3/embeddings") },
      { "text2vec-openai" => { "vectorizeClassName" => false, "model" => "ada", "endpoint" => "/api/v3/embeddings", "isAzure" => false } },
    ],
    [ # test_config.py:339
      -> { Configure::Vectorizer.text2vec_mistral(vectorize_collection_name: false, model: "cool-model") },
      { "text2vec-mistral" => { "vectorizeClassName" => false, "model" => "cool-model" } },
    ],
    [ # test_config.py:351
      -> { Configure::Vectorizer.text2vec_google("project") },
      { "text2vec-google" => { "projectId" => "project", "vectorizeClassName" => true } },
    ],
    [ # test_config.py:362
      -> { Configure::Vectorizer.text2vec_google_aistudio },
      { "text2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "vectorizeClassName" => true } },
    ],
    [ # test_config.py:371
      -> { Configure::Vectorizer.text2vec_google("project", api_endpoint: "api.google.com", model_id: "model", vectorize_collection_name: false) },
      { "text2vec-google" => { "projectId" => "project", "apiEndpoint" => "api.google.com", "modelId" => "model", "vectorizeClassName" => false } },
    ],
    [ # test_config.py:387
      -> { Configure::Vectorizer.text2vec_transformers },
      { "text2vec-transformers" => { "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } },
    ],
    [ # test_config.py:396
      -> { Configure::Vectorizer.text2vec_transformers(pooling_strategy: "cls", vectorize_collection_name: false, inference_url: "https://api.transformers.com") },
      { "text2vec-transformers" => { "vectorizeClassName" => false, "poolingStrategy" => "cls", "inferenceUrl" => "https://api.transformers.com" } },
    ],
    [ # test_config.py:410
      -> { Configure::Vectorizer.text2vec_jinaai(model: "jina-embeddings-v4", vectorize_collection_name: false, dimensions: 512) },
      { "text2vec-jinaai" => { "model" => "jina-embeddings-v4", "vectorizeClassName" => false, "dimensions" => 512 } },
    ],
    [ # test_config.py:424
      -> { Configure::Vectorizer.multi2vec_jinaai(model: "jina-embeddings-v4", dimensions: 512, vectorize_collection_name: false) },
      { "multi2vec-jinaai" => { "model" => "jina-embeddings-v4", "dimensions" => 512 } },
    ],
    [ # test_config.py:437
      -> { Configure::Vectorizer.text2vec_voyageai(vectorize_collection_name: false, model: "voyage-large-2", truncate: false, base_url: "https://voyage.made-up.com") },
      { "text2vec-voyageai" => { "vectorizeClassName" => false, "model" => "voyage-large-2", "baseURL" => "https://voyage.made-up.com", "truncate" => false } },
    ],
    [ # test_config.py:453
      -> { Configure::Vectorizer.text2vec_nvidia(vectorize_collection_name: false, model: "nvidia/nv-embed-v1", truncate: false, base_url: "https://integrate.api.nvidia.com") },
      { "text2vec-nvidia" => { "vectorizeClassName" => false, "model" => "nvidia/nv-embed-v1", "baseURL" => "https://integrate.api.nvidia.com", "truncate" => false } },
    ],
    [ # test_config.py:469
      -> { Configure::Vectorizer.text2vec_weaviate(vectorize_collection_name: false, model: "Snowflake/snowflake-arctic-embed-l-v2.0", base_url: "https://api.embedding.weaviate.io", dimensions: 1024) },
      { "text2vec-weaviate" => { "vectorizeClassName" => false, "model" => "Snowflake/snowflake-arctic-embed-l-v2.0", "baseURL" => "https://api.embedding.weaviate.io", "dimensions" => 1024 } },
    ],
    [ # test_config.py:485
      -> { Configure::Vectorizer.text2vec_weaviate(vectorize_collection_name: false, model: "Snowflake/snowflake-arctic-embed-m-v1.5", base_url: "https://api.embedding.weaviate.io", dimensions: 768) },
      { "text2vec-weaviate" => { "vectorizeClassName" => false, "model" => "Snowflake/snowflake-arctic-embed-m-v1.5", "baseURL" => "https://api.embedding.weaviate.io", "dimensions" => 768 } },
    ],
    [ # test_config.py:501
      -> { Configure::Vectorizer.img2vec_neural(["test"]) },
      { "img2vec-neural" => { "imageFields" => ["test"] } },
    ],
    [ # test_config.py:511
      -> { Configure::Vectorizer.multi2vec_clip(image_fields: ["image"], text_fields: ["text"]) },
      { "multi2vec-clip" => { "imageFields" => ["image"], "textFields" => ["text"] } },
    ],
    [ # test_config.py:523
      -> { Configure::Vectorizer.multi2vec_google(image_fields: ["image"], text_fields: ["text"], video_fields: ["video"], project_id: "project", video_interval_seconds: 1, location: "us-central1") },
      { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "videoFields" => ["video"], "projectId" => "project", "location" => "us-central1", "videoIntervalSeconds" => 1 } },
    ],
    [ # test_config.py:543
      -> { Configure::Vectorizer.multi2vec_google(image_fields: ["image"], text_fields: ["text"], video_fields: ["video"], project_id: "project", location: "us-central1") },
      { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "videoFields" => ["video"], "projectId" => "project", "location" => "us-central1" } },
    ],
    [ # test_config.py:561
      -> { Configure::Vectorizer.multi2vec_google(image_fields: [Multi2VecField.new(name: "image")], text_fields: [Multi2VecField.new(name: "text")], video_fields: [Multi2VecField.new(name: "video")], project_id: "project", location: "us-central1") },
      { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "videoFields" => ["video"], "projectId" => "project", "location" => "us-central1" } },
    ],
    [ # test_config.py:579
      -> { Configure::Vectorizer.multi2vec_google(image_fields: [Multi2VecField.new(name: "image", weight: 0.5)], text_fields: [Multi2VecField.new(name: "text", weight: 0.5)], video_fields: [Multi2VecField.new(name: "video", weight: 0.5)], project_id: "project", location: "us-central1", vectorize_collection_name: false) },
      { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "videoFields" => ["video"], "projectId" => "project", "location" => "us-central1", "weights" => { "imageFields" => [0.5], "textFields" => [0.5], "videoFields" => [0.5] } } },
    ],
    [ # test_config.py:603
      -> { Configure::Vectorizer.multi2vec_clip(image_fields: [Multi2VecField.new(name: "image")], text_fields: [Multi2VecField.new(name: "text")]) },
      { "multi2vec-clip" => { "imageFields" => ["image"], "textFields" => ["text"] } },
    ],
    [ # test_config.py:615
      -> { Configure::Vectorizer.multi2vec_clip(image_fields: [Multi2VecField.new(name: "image", weight: 0.5)], text_fields: [Multi2VecField.new(name: "text", weight: 0.5)], vectorize_collection_name: false) },
      { "multi2vec-clip" => { "imageFields" => ["image"], "textFields" => ["text"], "weights" => { "imageFields" => [0.5], "textFields" => [0.5] } } },
    ],
    [ # test_config.py:632
      -> { Configure::Vectorizer.multi2vec_bind(audio_fields: ["audio"], depth_fields: ["depth"], image_fields: ["image"], imu_fields: ["imu"], text_fields: ["text"], thermal_fields: ["thermal"]) },
      { "multi2vec-bind" => { "audioFields" => ["audio"], "depthFields" => ["depth"], "imageFields" => ["image"], "IMUFields" => ["imu"], "textFields" => ["text"], "thermalFields" => ["thermal"] } },
    ],
    [ # test_config.py:652
      -> { Configure::Vectorizer.multi2vec_bind(audio_fields: [Multi2VecField.new(name: "audio")], depth_fields: [Multi2VecField.new(name: "depth")], image_fields: [Multi2VecField.new(name: "image")], imu_fields: [Multi2VecField.new(name: "imu")], text_fields: [Multi2VecField.new(name: "text")], thermal_fields: [Multi2VecField.new(name: "thermal")]) },
      { "multi2vec-bind" => { "audioFields" => ["audio"], "depthFields" => ["depth"], "imageFields" => ["image"], "IMUFields" => ["imu"], "textFields" => ["text"], "thermalFields" => ["thermal"] } },
    ],
    [ # test_config.py:672
      -> { Configure::Vectorizer.multi2vec_bind(audio_fields: [Multi2VecField.new(name: "audio", weight: 0.5)], depth_fields: [Multi2VecField.new(name: "depth", weight: 0.5)], image_fields: [Multi2VecField.new(name: "image", weight: 0.5)], imu_fields: [Multi2VecField.new(name: "imu", weight: 0.5)], text_fields: [Multi2VecField.new(name: "text", weight: 0.5)], thermal_fields: [Multi2VecField.new(name: "thermal", weight: 0.5)], vectorize_collection_name: false) },
      { "multi2vec-bind" => { "audioFields" => ["audio"], "depthFields" => ["depth"], "imageFields" => ["image"], "IMUFields" => ["imu"], "textFields" => ["text"], "thermalFields" => ["thermal"], "weights" => { "audioFields" => [0.5], "depthFields" => [0.5], "imageFields" => [0.5], "IMUFields" => [0.5], "textFields" => [0.5], "thermalFields" => [0.5] } } },
    ],
    [ # test_config.py:701
      -> { Configure::Vectorizer.ref2vec_centroid(["prop"]) },
      { "ref2vec-centroid" => { "referenceProperties" => ["prop"], "method" => "mean" } },
    ],
  ].freeze

  TEST_CONFIG_WITH_VECTORIZER_AND_PROPERTIES_PARAMETERS = [
    [ # test_config.py:722
      -> { Configure::Vectorizer.text2vec_transformers },
      -> { [Property.new(name: "text", data_type: DataType::TEXT, skip_vectorization: true, vectorize_property_name: false)] },
      { "text2vec-transformers" => { "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } },
      [{ "dataType" => ["text"], "name" => "text", "moduleConfig" => { "text2vec-transformers" => { "skip" => true, "vectorizePropertyName" => false } } }],
    ],
    [ # test_config.py:751
      -> { Configure::Vectorizer.text2vec_jinaai },
      -> { [Property.new(name: "text", data_type: DataType::TEXT, skip_vectorization: true, vectorize_property_name: false)] },
      { "text2vec-jinaai" => { "vectorizeClassName" => true } },
      [{ "dataType" => ["text"], "name" => "text", "moduleConfig" => { "text2vec-jinaai" => { "skip" => true, "vectorizePropertyName" => false } } }],
    ],
    [ # test_config.py:779
      -> { Configure::Vectorizer.text2vec_transformers },
      -> { [Property.new(name: "text", data_type: DataType::TEXT)] },
      { "text2vec-transformers" => { "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } },
      [{ "dataType" => ["text"], "name" => "text", "moduleConfig" => { "text2vec-transformers" => { "skip" => false, "vectorizePropertyName" => true } } }],
    ],
  ].freeze

end

RSpec.describe "test_config.py: vectorizers" do
  let(:c) { Weaviate::Classes::Config }

  ConfigVectorizersSpecData::TEST_CONFIG_WITH_VECTORIZER_PARAMETERS.each_with_index do |(factory, expected), i|
    it "test_config_with_default_vectorizer[#{i}] #{expected.keys.first}" do
      vectorizer_config = factory.call
      config = c::CollectionConfigCreate.new(name: "test", vectorizer_config: vectorizer_config)
      expect(config.to_dict).to eq(
        "vectorIndexType" => "hnsw",
        "vectorizer" => vectorizer_config.vectorizer.to_s,
        "class" => "Test",
        "moduleConfig" => expected
      )
    end
  end

  ConfigVectorizersSpecData::TEST_CONFIG_WITH_VECTORIZER_AND_PROPERTIES_PARAMETERS.each_with_index do |row, i|
    factory, properties, expected_mc, expected_props = row
    it "test_config_with_vectorizer_and_properties[#{i}]" do
      vectorizer_config = factory.call
      config = c::CollectionConfigCreate.new(
        name: "test", properties: properties.call, vectorizer_config: vectorizer_config
      )
      expect(config.to_dict).to eq(
        "vectorIndexType" => "hnsw",
        "vectorizer" => vectorizer_config.vectorizer.to_s,
        "class" => "Test",
        "properties" => expected_props,
        "moduleConfig" => expected_mc
      )
    end
  end

  it "test_config_with_vector_config_warns_on_skip_vectorization" do
    config = c::CollectionConfigCreate.new(
      name: "test",
      properties: [c::Property.new(name: "text", data_type: c::DataType::TEXT, skip_vectorization: true)],
      vector_config: c::Configure::Vectors.text2vec_transformers
    )
    _, warnings = Weaviate::Warnings.capture { config.to_dict }
    expect(warnings).to include(a_string_matching(/Dep032/))
  end

  {
    "flag not set at all" => lambda { |cfg|
      { properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)],
        vector_config: cfg::Configure::Vectors.text2vec_transformers }
    },
    "legacy path maps the flag, so it does take effect" => lambda { |cfg|
      { properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT, skip_vectorization: true)],
        vectorizer_config: cfg::Configure::Vectorizer.text2vec_transformers }
    },
    "nothing is vectorized, so the flag is moot" => lambda { |cfg|
      { properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT, skip_vectorization: true)],
        vector_config: cfg::Configure::Vectors.self_provided }
    },
    "no vector config" => lambda { |cfg|
      { properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT, skip_vectorization: true)] }
    }
  }.each do |desc, kwargs|
    it "test_config_property_flags_do_not_warn (#{desc})" do
      config = c::CollectionConfigCreate.new(name: "test", **kwargs.call(c))
      _, warnings = Weaviate::Warnings.capture { config.to_dict }
      expect(warnings).to be_empty
    end
  end
end

# Ruby-side checks of the validators / deprecations mirrored from config_vectorizers.py
# and config_vectors.py (not individually covered by test_config.py).
RSpec.describe "Weaviate::Classes::Config vectorizer models" do
  let(:c) { Weaviate::Classes::Config }

  it "rejects an empty AWS region" do
    expect { c::Vectorizer.text2vec_aws(model: "m") }.to raise_error(ArgumentError, /region is a required argument/)
  end

  it "normalises AnyHttpUrl fields like pydantic and rejects non-http URLs" do
    expect(c::Vectorizer.text2vec_openai(base_url: "https://api.x.ai/v1").to_dict["baseURL"]).to eq("https://api.x.ai/v1")
    expect(c::Vectorizer.text2vec_openai(base_url: "HTTPS://API.X.AI:443").to_dict["baseURL"]).to eq("https://api.x.ai/")
    expect(c::Vectorizer.text2vec_openai(base_url: "http://localhost:8080").to_dict["baseURL"]).to eq("http://localhost:8080/")
    expect { c::Vectorizer.text2vec_openai(base_url: "ftp://x.com") }.to raise_error(ArgumentError)
    expect { c::Vectorizer.text2vec_openai(base_url: "not a url") }.to raise_error(ArgumentError)
  end

  it "validates literal and typed fields (pydantic strict mode)" do
    expect { c::Vectorizer.text2vec_cohere(truncate: "MIDDLE") }.to raise_error(ArgumentError)
    expect { c::Vectorizer.text2vec_openai(type_: "image") }.to raise_error(ArgumentError)
    expect { c::Vectorizer.text2vec_openai(dimensions: "12") }.to raise_error(ArgumentError)
    expect { c::Vectorizer.img2vec_neural("image") }.to raise_error(ArgumentError)
    expect(c::Vectorizer.text2vec_openai(type_: "code").to_dict).to eq("type" => "code", "vectorizeClassName" => true, "isAzure" => false)
  end

  it "handles the deprecated interference_url of multi2vec_clip" do
    expect { c::Vectorizer.multi2vec_clip(interference_url: "a", inference_url: "b") }.to raise_error(ArgumentError)
    result, warnings = Weaviate::Warnings.capture { c::Vectorizer.multi2vec_clip(interference_url: "a") }
    expect(warnings.first).to match(/Please use `inference_url` instead/)
    expect(result.to_dict).to eq({})
  end

  it "creates custom and none vectorizers" do
    custom = c::Vectorizer.custom("my-module", module_config: { "a" => 1 })
    expect(custom.vectorizer.to_s).to eq("my-module")
    expect(custom.to_dict).to eq("a" => 1)
    expect(c::Vectorizer.custom("my-module").to_dict).to eq({})
    expect(c::Vectorizer.none.vectorizer).to eq(c::Vectorizers::NONE)
    expect(c::Vectorizer.none.to_dict).to eq({})
  end

  it "emits deprecation warnings for deprecated Configure.Vectors methods" do
    %i[text2vec_contextionary text2vec_gpt4all text2vec_google_aistudio].each do |meth|
      _, warnings = Weaviate::Warnings.capture { c::Vectors.public_send(meth) }
      expect(warnings.size).to eq(1), meth.to_s
    end
    _, warnings = Weaviate::Warnings.capture { c::Vectors.text2vec_aws(model: "m", region: "r") }
    expect(warnings.first).to match(/text2vec_aws_bedrock/)
    _, warnings = Weaviate::Warnings.capture { c::Vectors.text2vec_aws_bedrock(model: "m", region: "r") }
    expect(warnings).to be_empty
  end

  it "rejects an empty source_properties list" do
    expect { c::NamedVectors.text2vec_openai("v", source_properties: []) }.to raise_error(ArgumentError)
    expect { c::Vectors.text2vec_openai(source_properties: []) }.to raise_error(ArgumentError)
  end

  it "builds update models for named vectors / vectors" do
    vic = Object.new
    expect(c::NamedVectorsUpdate.update("v", vector_index_config: vic).vectorIndexConfig).to equal(vic)
    expect(c::VectorsUpdate.update(vector_index_config: vic).name).to eq("default")
    expect(c::VectorsUpdate.update(name: "x", vector_index_config: vic).name).to eq("x")
  end
end
