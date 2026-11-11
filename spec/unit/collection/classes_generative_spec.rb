# frozen_string_literal: true

require "pathname"

# Port of test/collection/test_classes_generative.py
RSpec.describe Weaviate::Classes::Generate::GenerativeConfig do
  gen = Weaviate::Classes::Generate
  v1 = Weaviate::V1
  logo = File.join(__dir__, "weaviate-logo.png")
  logo_encoded = "iVBORw0KGgoAAAANSUhEUgAAAZAAAAE5CAYAAAC+rHbqAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyhpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuNi1jMTQ1IDc5LjE2MzQ5OSwgMjAxOC8wOC8xMy0xNjo0MDoyMiAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENDIDIwMTkgKE1hY2ludG9zaCkiIHhtcE1NOkluc3RhbmNlSUQ9InhtcC5paWQ6Rjc3MkEzQzdGM0QxMTFFODlBRTRBNjMyNUE2MTk3NzgiIHhtcE1NOkRvY3VtZW50SUQ9InhtcC5kaWQ6Rjc3MkEzQzhGM0QxMTFFODlBRTRBNjMyNUE2MTk3NzgiPiA8eG1wTU06RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDpGNzcyQTNDNUYzRDExMUU4OUFFNEE2MzI1QTYxOTc3OCIgc3RSZWY6ZG9jdW1lbnRJRD0ieG1wLmRpZDpGNzcyQTNDNkYzRDExMUU4OUFFNEE2MzI1QTYxOTc3OCIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PnOiDKoAABWzSURBVHja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"
  opts = ->(**kw) { gen::GenerativeConfigRuntimeOptions.new(**kw) }
  images_opts = -> { opts.call(return_metadata: true, images: [logo_encoded], image_properties: ["image"]) }
  text_array = ->(*values) { v1::TextArray.new(values: values) }

  {
    "grouped_task list" => ->(image) { gen::GenerativeParameters.grouped_task("whatever", images: [image]) },
    "single_prompt list" => ->(image) { gen::GenerativeParameters.single_prompt("whatever", images: [image]) },
    "grouped_task single" => ->(image) { gen::GenerativeParameters.grouped_task("whatever", images: image) },
    "single_prompt single" => ->(image) { gen::GenerativeParameters.single_prompt("whatever", images: image) }
  }.each do |name, provider|
    it "test_generative_parameters_images_parsing[#{name}]" do
      # image as a path string
      p = provider.call(logo)
      expect(p.images.to_a).to eq([logo_encoded])
      # image as a Pathname
      p = provider.call(Pathname.new(logo))
      expect(p.images.to_a).to eq([logo_encoded])
      # image as an open file
      File.open(logo, "rb") do |f|
        p = provider.call(f)
        expect(p.images.to_a).to eq([logo_encoded])
      end
    end
  end

  cases = {
    "anthropic" => lambda {
      [
        described_class.anthropic(base_url: "http://localhost:8080", model: "text-to-image", max_tokens: 100,
                                  stop_sequences: ["\n"], temperature: 0.5, top_k: 50, top_p: 0.9).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          anthropic: v1::GenerativeAnthropic.new(
            base_url: "http://localhost:8080", model: "text-to-image", max_tokens: 100,
            stop_sequences: text_array.call("\n"), temperature: 0.5, top_k: 50, top_p: 0.9,
            images: text_array.call(logo_encoded), image_properties: text_array.call("image")
          )
        )
      ]
    },
    "anyscale" => lambda {
      [
        described_class.anyscale(base_url: "http://localhost:8080", model: "text-to-image", temperature: 0.5)
                       .to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          anyscale: v1::GenerativeAnyscale.new(base_url: "http://localhost:8080", model: "text-to-image",
                                               temperature: 0.5)
        )
      ]
    },
    "aws_sagemaker" => lambda {
      [
        described_class.aws_sagemaker(
          endpoint: "http://localhost:8080", region: "us-west-2",
          target_model: "arn:aws:sagemaker:us-west-2:123456789012:model/text-to-image", target_variant: "variant-1",
          temperature: 0.5, stop_sequences: ["\n"]
        ).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          aws: v1::GenerativeAWS.new(
            endpoint: "http://localhost:8080", region: "us-west-2", service: "sagemaker",
            target_model: "arn:aws:sagemaker:us-west-2:123456789012:model/text-to-image", target_variant: "variant-1",
            temperature: 0.5, stop_sequences: text_array.call("\n"), images: text_array.call(logo_encoded),
            image_properties: text_array.call("image")
          )
        )
      ]
    },
    "cohere" => lambda {
      [
        described_class.cohere(base_url: "http://localhost:8080", frequency_penalty: 0.4, k: 5, max_tokens: 100,
                               model: "text-to-image", p: 0.9, presence_penalty: 0.5, stop_sequences: ["\n"],
                               temperature: 0.5).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          cohere: v1::GenerativeCohere.new(base_url: "http://localhost:8080", frequency_penalty: 0.4, k: 5,
                                           max_tokens: 100, model: "text-to-image", p: 0.9, presence_penalty: 0.5,
                                           stop_sequences: text_array.call("\n"), temperature: 0.5)
        )
      ]
    },
    "databricks" => lambda {
      [
        described_class.databricks(endpoint: "http://localhost:8080", frequency_penalty: 0.5, log_probs: true,
                                   max_tokens: 100, model: "text-to-image", n: 5, presence_penalty: 0.5,
                                   stop: ["\n"], temperature: 0.5, top_log_probs: 5, top_p: 0.9)
                       .to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          databricks: v1::GenerativeDatabricks.new(endpoint: "http://localhost:8080", frequency_penalty: 0.5,
                                                   log_probs: true, max_tokens: 100, model: "text-to-image", n: 5,
                                                   presence_penalty: 0.5, stop: text_array.call("\n"),
                                                   temperature: 0.5, top_log_probs: 5, top_p: 0.9)
        )
      ]
    },
    "deepseek" => lambda {
      [
        described_class.deepseek(base_url: "http://localhost:8080", model: "deepseek-chat", temperature: 0.5,
                                 max_tokens: 100, frequency_penalty: 0.1, presence_penalty: 0.2, top_p: 0.9,
                                 stop: ["\n"]).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          deepseek: v1::GenerativeDeepseek.new(base_url: "http://localhost:8080", model: "deepseek-chat",
                                               temperature: 0.5, max_tokens: 100, frequency_penalty: 0.1,
                                               presence_penalty: 0.2, top_p: 0.9, stop: text_array.call("\n"))
        )
      ]
    },
    "digitalocean" => lambda {
      [
        described_class.digitalocean(base_url: "https://inference.do-ai.run", model: "llama-4-maverick",
                                     temperature: 0.5, top_p: 0.9, max_tokens: 100, frequency_penalty: 0.1,
                                     presence_penalty: 0.2, stop: ["STOP"]).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          digitalocean: v1::GenerativeDigitalOcean.new(base_url: "https://inference.do-ai.run",
                                                       model: "llama-4-maverick", temperature: 0.5, top_p: 0.9,
                                                       max_tokens: 100, frequency_penalty: 0.1,
                                                       presence_penalty: 0.2, stop: text_array.call("STOP"))
        )
      ]
    },
    "dummy" => lambda {
      [
        described_class.dummy.to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(return_metadata: true, dummy: v1::GenerativeDummy.new)
      ]
    },
    "friendliai" => lambda {
      [
        described_class.friendliai(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image", n: 5,
                                   temperature: 0.5, top_p: 0.9).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          friendliai: v1::GenerativeFriendliAI.new(base_url: "http://localhost:8080", max_tokens: 100,
                                                   model: "text-to-image", n: 5, temperature: 0.5, top_p: 0.9)
        )
      ]
    },
    "google" => lambda {
      [
        described_class.google(api_endpoint: "http://localhost:8080", endpoint_id: "12345678901234567890123456789012",
                               frequency_penalty: 0.5, max_tokens: 100, model: "text-to-image", presence_penalty: 0.5,
                               project_id: "my-project", region: "us-west1", stop_sequences: ["\n"], temperature: 0.5,
                               top_k: 50, top_p: 0.9).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          google: v1::GenerativeGoogle.new(
            api_endpoint: "localhost:8080", endpoint_id: "12345678901234567890123456789012", frequency_penalty: 0.5,
            max_tokens: 100, model: "text-to-image", presence_penalty: 0.5, project_id: "my-project",
            region: "us-west1", stop_sequences: text_array.call("\n"), temperature: 0.5, top_k: 50, top_p: 0.9,
            images: text_array.call(logo_encoded), image_properties: text_array.call("image")
          )
        )
      ]
    },
    "google_vertex" => lambda {
      [
        described_class.google_vertex(
          api_endpoint: "http://localhost:8080", project_id: "my-project",
          endpoint_id: "12345678901234567890123456789012", region: "us-west1", frequency_penalty: 0.5,
          max_tokens: 100, model: "text-to-image", presence_penalty: 0.5, temperature: 0.5, top_k: 50, top_p: 0.9,
          stop_sequences: ["\n"], location: "us-central1"
        ).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          google: v1::GenerativeGoogle.new(
            api_endpoint: "localhost:8080", endpoint_id: "12345678901234567890123456789012", frequency_penalty: 0.5,
            max_tokens: 100, model: "text-to-image", presence_penalty: 0.5, project_id: "my-project",
            region: "us-west1", location: "us-central1", stop_sequences: text_array.call("\n"), temperature: 0.5,
            top_k: 50, top_p: 0.9, images: text_array.call(logo_encoded), image_properties: text_array.call("image")
          )
        )
      ]
    },
    "meta" => lambda {
      [
        described_class.meta(base_url: "https://api.meta.ai", model: "muse-spark-1.2", temperature: 0.5, top_p: 0.9,
                             max_tokens: 100, frequency_penalty: 0.1, presence_penalty: 0.2,
                             reasoning_effort: "xhigh").to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          meta: v1::GenerativeMeta.new(
            base_url: "https://api.meta.ai", model: "muse-spark-1.2", temperature: 0.5, top_p: 0.9, max_tokens: 100,
            frequency_penalty: 0.1, presence_penalty: 0.2, reasoning_effort: :REASONING_EFFORT_XHIGH,
            images: text_array.call(logo_encoded), image_properties: text_array.call("image")
          )
        )
      ]
    },
    "mistral" => lambda {
      [
        described_class.mistral(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image",
                                temperature: 0.5, top_p: 0.9).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          mistral: v1::GenerativeMistral.new(base_url: "http://localhost:8080", max_tokens: 100,
                                             model: "text-to-image", temperature: 0.5, top_p: 0.9)
        )
      ]
    },
    "nvidia" => lambda {
      [
        described_class.nvidia(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image",
                               temperature: 0.5, top_p: 0.9).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          nvidia: v1::GenerativeNvidia.new(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image",
                                           temperature: 0.5, top_p: 0.9)
        )
      ]
    },
    "ollama" => lambda {
      [
        described_class.ollama(api_endpoint: "http://localhost:8080", model: "text-to-image", temperature: 0.5)
                       .to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          ollama: v1::GenerativeOllama.new(api_endpoint: "http://localhost:8080", model: "text-to-image",
                                           temperature: 0.5, images: text_array.call(logo_encoded),
                                           image_properties: text_array.call("image"))
        )
      ]
    },
    "openai" => lambda {
      [
        described_class.openai(
          api_version: "2020-05-03", base_url: "http://localhost:8080",
          deployment_id: "12345678901234567890123456789012", frequency_penalty: 0.5, max_tokens: 100,
          model: "text-to-image", presence_penalty: 0.5,
          resource_name: "projects/my-project/locations/us-west1/endpoints/12345678901234567890123456789012",
          stop: ["\n"], temperature: 0.5, top_p: 50, reasoning_effort: "high", verbosity: "low"
        ).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          openai: v1::GenerativeOpenAI.new(
            api_version: "2020-05-03", base_url: "http://localhost:8080",
            deployment_id: "12345678901234567890123456789012", frequency_penalty: 0.5, max_tokens: 100,
            model: "text-to-image", presence_penalty: 0.5,
            resource_name: "projects/my-project/locations/us-west1/endpoints/12345678901234567890123456789012",
            stop: text_array.call("\n"), temperature: 0.5, top_p: 50, images: text_array.call(logo_encoded),
            image_properties: text_array.call("image"), is_azure: false,
            reasoning_effort: :REASONING_EFFORT_HIGH, verbosity: :VERBOSITY_LOW
          )
        )
      ]
    },
    "azure_openai" => lambda {
      [
        described_class.azure_openai(
          api_version: "2020-05-03", base_url: "http://localhost:8080",
          deployment_id: "12345678901234567890123456789012", frequency_penalty: 0.5, max_tokens: 100,
          model: "text-to-image", presence_penalty: 0.5,
          resource_name: "projects/my-project/locations/us-west1/endpoints/12345678901234567890123456789012",
          stop: ["\n"], temperature: 0.5, top_p: 50
        ).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          openai: v1::GenerativeOpenAI.new(
            api_version: "2020-05-03", base_url: "http://localhost:8080",
            deployment_id: "12345678901234567890123456789012", frequency_penalty: 0.5, max_tokens: 100,
            model: "text-to-image", presence_penalty: 0.5,
            resource_name: "projects/my-project/locations/us-west1/endpoints/12345678901234567890123456789012",
            stop: text_array.call("\n"), temperature: 0.5, top_p: 50, images: text_array.call(logo_encoded),
            image_properties: text_array.call("image"), is_azure: true
          )
        )
      ]
    },
    "xai" => lambda {
      [
        described_class.xai(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image",
                            temperature: 0.5, top_p: 50).to_grpc(images_opts.call),
        v1::GenerativeProvider.new(
          return_metadata: true,
          xai: v1::GenerativeXAI.new(base_url: "http://localhost:8080", max_tokens: 100, model: "text-to-image",
                                     temperature: 0.5, top_p: 50, images: text_array.call(logo_encoded),
                                     image_properties: text_array.call("image"))
        )
      ]
    },
    "contextualai" => lambda {
      prompt = "You are a helpful assistant that provides accurate and informative responses based on the given context."
      [
        described_class.contextualai(model: "v2", max_new_tokens: 100, temperature: 0.5, top_p: 0.9,
                                     system_prompt: prompt, avoid_commentary: false,
                                     knowledge: %w[knowledge1 knowledge2]).to_grpc(opts.call(return_metadata: true)),
        v1::GenerativeProvider.new(
          return_metadata: true,
          contextualai: v1::GenerativeContextualAI.new(model: "v2", max_new_tokens: 100, temperature: 0.5,
                                                       top_p: 0.9, system_prompt: prompt, avoid_commentary: false,
                                                       knowledge: text_array.call("knowledge1", "knowledge2"))
        )
      ]
    }
  }

  cases.each do |name, build|
    it "test_generative_provider_to_grpc[#{name}]" do
      actual, expected = build.call
      expect(actual).to eq(expected)
    end
  end

  it "rejects images for providers without multi-modal support" do
    expect { described_class.mistral.to_grpc(images_opts.call) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /generative-mistral/)
  end

  it "rejects invalid URLs and enum values" do
    expect { described_class.openai(base_url: "not a url") }.to raise_error(ArgumentError)
    expect { described_class.openai(verbosity: "loud").to_grpc(opts.call) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /verbosity/)
  end
end
