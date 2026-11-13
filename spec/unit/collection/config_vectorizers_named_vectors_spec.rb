# frozen_string_literal: true

require "spec_helper"

# Port of TEST_CONFIG_WITH_NAMED_VECTORIZER_PARAMETERS and TEST_CONFIG_WITH_VECTORS_PARAMETERS
# from weaviate-python-client test/collection/test_config.py.
module ConfigVectorizersSpecData
  include Weaviate::Classes::Config

  TEST_CONFIG_WITH_NAMED_VECTORIZER_PARAMETERS = [
    [ # test_config.py:1685
      -> { [Configure::NamedVectors.text2vec_contextionary("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-contextionary" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1699
      -> { [Configure::NamedVectors.text2vec_azure_openai("test", resource_name: "resource", deployment_id: "deployment", source_properties: ["prop"], dimensions: 512)] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "resourceName" => "resource", "deploymentId" => "deployment", "vectorizeClassName" => true, "properties" => ["prop"], "dimensions" => 512, "isAzure" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1725
      -> { [Configure::NamedVectors.text2vec_cohere("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-cohere" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1739
      -> { [Configure::NamedVectors.multi2vec_cohere("test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-cohere" => { "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1752
      -> { [Configure::NamedVectors.multi2vec_voyageai("test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-voyageai" => { "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1765
      -> { [Configure::NamedVectors.multi2vec_nvidia("test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-nvidia" => { "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1778
      -> { [Configure::NamedVectors.multi2vec_jinaai("test", dimensions: 256, text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-jinaai" => { "dimensions" => 256, "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1796
      -> { [Configure::NamedVectors.text2vec_gpt4all("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-gpt4all" => { "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1810
      -> { [Configure::NamedVectors.text2vec_huggingface("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-huggingface" => { "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1824
      -> { [Configure::NamedVectors.text2vec_aws("test", region: "us-east-1", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-aws" => { "properties" => ["prop"], "vectorizeClassName" => true, "region" => "us-east-1", "service" => "bedrock" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1844
      -> { [Configure::NamedVectors.text2vec_databricks("test", endpoint: "http://api.custom.com", instruction: "instruction")] },
      { "test" => { "vectorizer" => { "text2vec-databricks" => { "vectorizeClassName" => true, "instruction" => "instruction", "endpoint" => "http://api.custom.com" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1863
      -> { [Configure::NamedVectors.text2vec_ollama("test", source_properties: ["prop"], api_endpoint: "https://123.0.0.4", model: "cool-model")] },
      { "test" => { "vectorizer" => { "text2vec-ollama" => { "properties" => ["prop"], "vectorizeClassName" => true, "apiEndpoint" => "https://123.0.0.4", "model" => "cool-model" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1886
      -> { [Configure::NamedVectors.text2vec_openai("test", source_properties: ["prop"], base_url: "https://api.openai.com/")] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "properties" => ["prop"], "vectorizeClassName" => true, "baseURL" => "https://api.openai.com/", "isAzure" => false } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1906
      -> { [Configure::NamedVectors.text2vec_openai("test", source_properties: ["prop"], endpoint: "/api/v3/embeddings")] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "properties" => ["prop"], "vectorizeClassName" => true, "endpoint" => "/api/v3/embeddings", "isAzure" => false } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1928
      -> { [Configure::NamedVectors.text2vec_mistral("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-mistral" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1942
      -> { [Configure::NamedVectors.text2vec_google("test", project_id: "project", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-google" => { "projectId" => "project", "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1963
      -> { [Configure::NamedVectors.text2vec_google_aistudio("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1983
      -> { [Configure::NamedVectors.text2vec_transformers("test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-transformers" => { "properties" => ["prop"], "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:1998
      -> { [Configure::NamedVectors.text2vec_voyageai("test", source_properties: ["prop"], truncate: true)] },
      { "test" => { "vectorizer" => { "text2vec-voyageai" => { "properties" => ["prop"], "vectorizeClassName" => true, "truncate" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2017
      -> { [Configure::NamedVectors.text2vec_nvidia("test", source_properties: ["prop"], truncate: true)] },
      { "test" => { "vectorizer" => { "text2vec-nvidia" => { "properties" => ["prop"], "vectorizeClassName" => true, "truncate" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2036
      -> { [Configure::NamedVectors.text2vec_weaviate("test", source_properties: ["prop"], base_url: "https://api.embedding.weaviate.io", dimensions: 768)] },
      { "test" => { "vectorizer" => { "text2vec-weaviate" => { "properties" => ["prop"], "vectorizeClassName" => true, "baseURL" => "https://api.embedding.weaviate.io", "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2059
      -> { [Configure::NamedVectors.img2vec_neural("test", image_fields: ["test"])] },
      { "test" => { "vectorizer" => { "img2vec-neural" => { "imageFields" => ["test"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2077
      -> { [Configure::NamedVectors.multi2vec_clip("test", image_fields: ["image"], text_fields: ["text"])] },
      { "test" => { "vectorizer" => { "multi2vec-clip" => { "imageFields" => ["image"], "textFields" => ["text"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2097
      -> { [Configure::NamedVectors.multi2vec_google("test", image_fields: ["image"], text_fields: ["text"], project_id: "project", location: "us-central1")] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "projectId" => "project", "location" => "us-central1" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2121
      -> { [Configure::NamedVectors.multi2vec_google("test", audio_fields: ["audio"], image_fields: ["image"], text_fields: ["text"], project_id: "project", location: "us-central1")] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "audioFields" => ["audio"], "imageFields" => ["image"], "textFields" => ["text"], "projectId" => "project", "location" => "us-central1" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2147
      -> { [Configure::NamedVectors.multi2vec_bind("test", audio_fields: ["audio"], depth_fields: ["depth"], image_fields: ["image"], imu_fields: ["imu"], text_fields: ["text"], thermal_fields: ["thermal"])] },
      { "test" => { "vectorizer" => { "multi2vec-bind" => { "audioFields" => ["audio"], "depthFields" => ["depth"], "imageFields" => ["image"], "IMUFields" => ["imu"], "textFields" => ["text"], "thermalFields" => ["thermal"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2175
      -> { [Configure::NamedVectors.ref2vec_centroid("test", reference_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "ref2vec-centroid" => { "referenceProperties" => ["prop"], "method" => "mean" } }, "vectorIndexType" => "hnsw" } },
    ],
  ].freeze

  TEST_CONFIG_WITH_VECTORS_PARAMETERS = [
    [ # test_config.py:2201
      -> { [Configure::Vectors.text2vec_contextionary(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-contextionary" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2215
      -> { [Configure::Vectors.text2vec_azure_openai(name: "test", resource_name: "resource", deployment_id: "deployment", source_properties: ["prop"], dimensions: 512)] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "resourceName" => "resource", "deploymentId" => "deployment", "vectorizeClassName" => true, "properties" => ["prop"], "dimensions" => 512, "isAzure" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2241
      -> { [Configure::Vectors.multi2vec_aws_bedrock(name: "test", dimensions: 512, model: "model", text_fields: ["prop"], image_fields: ["img"])] },
      { "test" => { "vectorizer" => { "multi2vec-aws" => { "textFields" => ["prop"], "imageFields" => ["img"], "model" => "model", "dimensions" => 512 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2265
      -> { [Configure::Vectors.text2vec_cohere(name: "test", source_properties: ["prop"], dimensions: 512)] },
      { "test" => { "vectorizer" => { "text2vec-cohere" => { "vectorizeClassName" => true, "properties" => ["prop"], "dimensions" => 512 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2284
      -> { [Configure::Vectors.multi2vec_cohere(name: "test", text_fields: ["prop"], dimensions: 512)] },
      { "test" => { "vectorizer" => { "multi2vec-cohere" => { "textFields" => ["prop"], "dimensions" => 512 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2298
      -> { [Configure::Vectors.multi2vec_voyageai(name: "test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-voyageai" => { "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2311
      -> { [Configure::Vectors.multi2vec_nvidia(name: "test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-nvidia" => { "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2324
      -> { [Configure::Vectors.multi2vec_twelvelabs(name: "test", image_fields: ["image"], text_fields: ["prop"], model: "marengo3.0")] },
      { "test" => { "vectorizer" => { "multi2vec-twelvelabs" => { "imageFields" => ["image"], "textFields" => ["prop"], "model" => "marengo3.0" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2346
      -> { [Configure::Vectors.multi2vec_jinaai(name: "test", dimensions: 256, text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2vec-jinaai" => { "dimensions" => 256, "textFields" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2360
      -> { [Configure::MultiVectors.multi2vec_jinaai(name: "test", text_fields: ["prop"])] },
      { "test" => { "vectorizer" => { "multi2multivec-jinaai" => { "textFields" => ["prop"] } }, "vectorIndexConfig" => { "multivector" => { "enabled" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2378
      -> { [Configure::MultiVectors.multi2vec_weaviate(name: "test", image_field: "prop")] },
      { "test" => { "vectorizer" => { "multi2multivec-weaviate" => { "imageFields" => ["prop"] } }, "vectorIndexConfig" => { "multivector" => { "enabled" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2396
      -> { [Configure::Vectors.text2vec_gpt4all(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-gpt4all" => { "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2410
      -> { [Configure::Vectors.text2vec_huggingface(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-huggingface" => { "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2424
      -> { [Configure::Vectors.text2vec_aws(name: "test", region: "us-east-1", source_properties: ["prop"], model: "model")] },
      { "test" => { "vectorizer" => { "text2vec-aws" => { "properties" => ["prop"], "vectorizeClassName" => true, "region" => "us-east-1", "service" => "bedrock", "model" => "model" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2445
      -> { [Configure::Vectors.text2vec_databricks(name: "test", endpoint: "http://api.custom.com", instruction: "instruction")] },
      { "test" => { "vectorizer" => { "text2vec-databricks" => { "vectorizeClassName" => true, "instruction" => "instruction", "endpoint" => "http://api.custom.com" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2464
      -> { [Configure::Vectors.text2vec_ollama(name: "test", source_properties: ["prop"], api_endpoint: "https://123.0.0.4", model: "cool-model")] },
      { "test" => { "vectorizer" => { "text2vec-ollama" => { "properties" => ["prop"], "vectorizeClassName" => true, "apiEndpoint" => "https://123.0.0.4", "model" => "cool-model" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2487
      -> { [Configure::Vectors.text2vec_openai(name: "test", source_properties: ["prop"], base_url: "https://api.openai.com/")] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "properties" => ["prop"], "vectorizeClassName" => true, "baseURL" => "https://api.openai.com/", "isAzure" => false } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2507
      -> { [Configure::Vectors.text2vec_openai(name: "test", source_properties: ["prop"], endpoint: "/api/v3/embeddings")] },
      { "test" => { "vectorizer" => { "text2vec-openai" => { "properties" => ["prop"], "vectorizeClassName" => true, "endpoint" => "/api/v3/embeddings", "isAzure" => false } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2529
      -> { [Configure::Vectors.text2vec_mistral(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-mistral" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2543
      -> { [Configure::Vectors.text2vec_digitalocean(name: "test", source_properties: ["prop"], model: "qwen2")] },
      { "test" => { "vectorizer" => { "text2vec-digitalocean" => { "vectorizeClassName" => true, "properties" => ["prop"], "model" => "qwen2" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2562
      -> { [Configure::Vectors.text2vec_morph(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-morph" => { "vectorizeClassName" => true, "properties" => ["prop"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2576
      -> { [Configure::Vectors.text2vec_morph(name: "test", source_properties: ["prop"], endpoint: "/api/v3/embeddings")] },
      { "test" => { "vectorizer" => { "text2vec-morph" => { "vectorizeClassName" => true, "properties" => ["prop"], "endpoint" => "/api/v3/embeddings" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2597
      -> { [Configure::Vectors.text2vec_google(name: "test", project_id: "project", source_properties: ["prop"], dimensions: 768)] },
      { "test" => { "vectorizer" => { "text2vec-google" => { "projectId" => "project", "properties" => ["prop"], "vectorizeClassName" => true, "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2620
      -> { [Configure::Vectors.text2vec_google_vertex(name: "test", project_id: "project", source_properties: ["prop"], dimensions: 768, location: "europe-west1")] },
      { "test" => { "vectorizer" => { "text2vec-google" => { "projectId" => "project", "location" => "europe-west1", "properties" => ["prop"], "vectorizeClassName" => true, "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2645
      -> { [Configure::Vectors.text2vec_google_gemini(name: "test", source_properties: ["prop"], dimensions: 768)] },
      { "test" => { "vectorizer" => { "text2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "properties" => ["prop"], "vectorizeClassName" => true, "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2667
      -> { [Configure::Vectors.text2vec_transformers(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-transformers" => { "properties" => ["prop"], "vectorizeClassName" => true, "poolingStrategy" => "masked_mean" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2682
      -> { [Configure::Vectors.text2vec_model2vec(name: "test", source_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "text2vec-model2vec" => { "properties" => ["prop"], "vectorizeClassName" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2696
      -> { [Configure::Vectors.text2vec_voyageai(name: "test", source_properties: ["prop"], truncate: true, dimensions: 256)] },
      { "test" => { "vectorizer" => { "text2vec-voyageai" => { "properties" => ["prop"], "vectorizeClassName" => true, "truncate" => true, "dimensions" => 256 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2716
      -> { [Configure::Vectors.text2vec_nvidia(name: "test", source_properties: ["prop"], truncate: true)] },
      { "test" => { "vectorizer" => { "text2vec-nvidia" => { "properties" => ["prop"], "vectorizeClassName" => true, "truncate" => true } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2731
      -> { [Configure::Vectors.text2vec_weaviate(name: "test", source_properties: ["prop"], base_url: "https://api.embedding.weaviate.io", dimensions: 768)] },
      { "test" => { "vectorizer" => { "text2vec-weaviate" => { "properties" => ["prop"], "vectorizeClassName" => true, "baseURL" => "https://api.embedding.weaviate.io", "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2754
      -> { [Configure::Vectors.img2vec_neural(name: "test", image_fields: ["test"])] },
      { "test" => { "vectorizer" => { "img2vec-neural" => { "imageFields" => ["test"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2772
      -> { [Configure::Vectors.multi2vec_voyageai(name: "test", model: "voyage-multimodal-3.5", truncation: true, base_url: "https://api.voyageai.com")] },
      { "test" => { "vectorizer" => { "multi2vec-voyageai" => { "model" => "voyage-multimodal-3.5", "truncation" => true, "baseURL" => "https://api.voyageai.com/" } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2794
      -> { [Configure::Vectors.multi2vec_voyageai(name: "test", model: "voyage-multimodal-3.5", truncation: true, text_fields: [Multi2VecField.new(name: "text", weight: 0.2)], image_fields: [Multi2VecField.new(name: "image", weight: 0.3)], video_fields: [Multi2VecField.new(name: "video", weight: 0.5)])] },
      { "test" => { "vectorizer" => { "multi2vec-voyageai" => { "model" => "voyage-multimodal-3.5", "truncation" => true, "textFields" => ["text"], "imageFields" => ["image"], "videoFields" => ["video"], "weights" => { "textFields" => [0.2], "imageFields" => [0.3], "videoFields" => [0.5] } } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2825
      -> { [Configure::Vectors.multi2vec_voyageai(name: "test", model: "voyage-multimodal-3.5", dimensions: 512, text_fields: ["text"], video_fields: ["video"])] },
      { "test" => { "vectorizer" => { "multi2vec-voyageai" => { "model" => "voyage-multimodal-3.5", "dimensions" => 512, "textFields" => ["text"], "videoFields" => ["video"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2849
      -> { [Configure::Vectors.multi2vec_clip(name: "test", image_fields: ["image"], text_fields: ["text"])] },
      { "test" => { "vectorizer" => { "multi2vec-clip" => { "imageFields" => ["image"], "textFields" => ["text"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2869
      -> { [Configure::Vectors.multi2vec_google(name: "test", image_fields: ["image"], text_fields: ["text"], project_id: "project", location: "us-central1", dimensions: 768)] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "imageFields" => ["image"], "textFields" => ["text"], "projectId" => "project", "location" => "us-central1", "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2895
      -> { [Configure::Vectors.multi2vec_google_gemini(name: "test", image_fields: ["image"], text_fields: ["text"], dimensions: 768)] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "imageFields" => ["image"], "textFields" => ["text"], "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2918
      -> { [Configure::Vectors.multi2vec_google(name: "test", audio_fields: ["audio"], image_fields: ["image"], text_fields: ["text"], project_id: "project", location: "us-central1", dimensions: 768)] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "audioFields" => ["audio"], "imageFields" => ["image"], "textFields" => ["text"], "projectId" => "project", "location" => "us-central1", "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2946
      -> { [Configure::Vectors.multi2vec_google_gemini(name: "test", audio_fields: ["audio"], image_fields: ["image"], text_fields: ["text"], dimensions: 768)] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "audioFields" => ["audio"], "imageFields" => ["image"], "textFields" => ["text"], "dimensions" => 768 } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:2971
      -> { [Configure::Vectors.multi2vec_google_gemini(name: "test", audio_fields: [Multi2VecField.new(name: "audio", weight: 0.5)], image_fields: [Multi2VecField.new(name: "image", weight: 0.5)], text_fields: [Multi2VecField.new(name: "text", weight: 0.5)], dimensions: 768)] },
      { "test" => { "vectorizer" => { "multi2vec-google" => { "apiEndpoint" => "generativelanguage.googleapis.com", "audioFields" => ["audio"], "imageFields" => ["image"], "textFields" => ["text"], "dimensions" => 768, "weights" => { "audioFields" => [0.5], "imageFields" => [0.5], "textFields" => [0.5] } } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:3001
      -> { [Configure::Vectors.multi2vec_bind(name: "test", audio_fields: ["audio"], depth_fields: ["depth"], image_fields: ["image"], imu_fields: ["imu"], text_fields: ["text"], thermal_fields: ["thermal"])] },
      { "test" => { "vectorizer" => { "multi2vec-bind" => { "audioFields" => ["audio"], "depthFields" => ["depth"], "imageFields" => ["image"], "IMUFields" => ["imu"], "textFields" => ["text"], "thermalFields" => ["thermal"] } }, "vectorIndexType" => "hnsw" } },
    ],
    [ # test_config.py:3029
      -> { [Configure::Vectors.ref2vec_centroid(name: "test", reference_properties: ["prop"])] },
      { "test" => { "vectorizer" => { "ref2vec-centroid" => { "referenceProperties" => ["prop"], "method" => "mean" } }, "vectorIndexType" => "hnsw" } },
    ],
  ].freeze

end

RSpec.describe "test_config.py: named vectors and Configure.Vectors" do
  let(:c) { Weaviate::Classes::Config }

  ConfigVectorizersSpecData::TEST_CONFIG_WITH_NAMED_VECTORIZER_PARAMETERS.each_with_index do |(factory, expected), i|
    it "test_config_with_named_vectors[#{i}] #{expected.keys.join(",")}" do
      config = c::CollectionConfigCreate.new(name: "test", vectorizer_config: factory.call)
      expect(config.to_dict).to eq("class" => "Test", "vectorConfig" => expected)
    end
  end

  ConfigVectorizersSpecData::TEST_CONFIG_WITH_VECTORS_PARAMETERS.each_with_index do |(factory, expected), i|
    it "test_config_with_vectors[#{i}] #{expected.keys.join(",")}" do
      config = c::CollectionConfigCreate.new(name: "test", vector_config: factory.call)
      expect(config.to_dict).to eq("class" => "Test", "vectorConfig" => expected)
    end
  end
end

RSpec.describe "NamedVectors factories: vector name" do
  nv = Weaviate::Classes::Config::Configure::NamedVectors

  it "accepts the name positionally or as name: (Python allows both)" do
    positional = nv.text2vec_contextionary("all", vectorize_collection_name: false)
    keyword = nv.text2vec_contextionary(name: "all", vectorize_collection_name: false)
    expect(keyword.name).to eq("all")
    expect(keyword.to_dict).to eq(positional.to_dict)
    expect(nv.none(name: "x").name).to eq("x")
    expect(nv.custom(name: "c", module_name: "m").name).to eq("c")
  end

  it "still requires a name" do
    expect { nv.none }.to raise_error(Weaviate::Classes::Config::ValidationError, /name must be a String/)
  end
end
