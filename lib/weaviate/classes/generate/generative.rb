# frozen_string_literal: true

require "pathname"
require "uri"

module Weaviate
  module Classes
    # Port of weaviate.classes.generate / weaviate.collections.classes.generative
    module Generate
      # Python _to_text_array
      def self.to_text_array(values)
        values.nil? ? nil : ::Weaviate::V1::TextArray.new(values: values.to_a.map(&:to_s))
      end

      # Python _parse_anyhttpurl: validates an http(s) URL and strips surrounding slashes.
      def self.parse_url(url)
        return nil if url.nil?

        uri = URI.parse(url.to_s)
        unless %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
          raise ArgumentError, "Input should be a valid URL with an http or https scheme, got #{url.inspect}"
        end

        url.to_s.gsub(%r{\A/+|/+\z}, "")
      rescue URI::InvalidURIError
        raise ArgumentError, "Input should be a valid URL, got #{url.inspect}"
      end

      # Python _GenerativeConfigRuntimeOptions
      class GenerativeConfigRuntimeOptions < ::Weaviate::Model
        attribute :return_metadata, default: false
        attribute :images, default: nil
        attribute :image_properties, default: nil
      end

      # Base of the runtime generative providers created via GenerativeConfig (Python _GenerativeConfigRuntime).
      class GenerativeConfigRuntime < ::Weaviate::Model
        class << self
          # module name, e.g. "generative-openai"; the protobuf field on GenerativeProvider; the proto class
          def provider(generative, field, proto)
            const_set(:GENERATIVE, generative)
            const_set(:FIELD, field)
            const_set(:PROTO, proto)
          end
        end

        def generative = self.class::GENERATIVE

        # Python `_to_grpc(opts)`
        def to_grpc(opts)
          validate_multi_modal(opts) unless multi_modal?
          ::Weaviate::V1::GenerativeProvider.new(
            return_metadata: opts.return_metadata,
            self.class::FIELD => self.class::PROTO.new(**grpc_fields(opts))
          )
        end

        private

        def multi_modal? = false

        def image_fields(opts)
          { images: Generate.to_text_array(opts.images), image_properties: Generate.to_text_array(opts.image_properties) }
        end

        def validate_multi_modal(opts)
          return if opts.images.nil? && opts.image_properties.nil?

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "The #{generative} module does not support the `images` or `image_properties` options."
        end
      end

      class GenerativeAnthropic < GenerativeConfigRuntime
        provider "generative-anthropic", :anthropic, ::Weaviate::V1::GenerativeAnthropic
        attributes :base_url, :max_tokens, :model, :temperature, :top_k, :top_p, :stop_sequences

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { base_url: Generate.parse_url(base_url), max_tokens: max_tokens, model: model, temperature: temperature,
            top_k: top_k, top_p: top_p, stop_sequences: Generate.to_text_array(stop_sequences),
            **image_fields(opts) }
        end
      end

      class GenerativeAnyscale < GenerativeConfigRuntime
        provider "generative-anyscale", :anyscale, ::Weaviate::V1::GenerativeAnyscale
        attributes :base_url, :model, :temperature

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), model: model, temperature: temperature }
        end
      end

      class GenerativeAWS < GenerativeConfigRuntime
        provider "generative-aws", :aws, ::Weaviate::V1::GenerativeAWS
        attributes :max_tokens, :model, :region, :endpoint, :service, :target_model, :target_variant, :temperature,
                   :top_k, :top_p, :stop_sequences

        private

        def multi_modal? = true

        # top_k & top_p are not yet part of the server-side proto (same as the Python client)
        def grpc_fields(opts)
          { model: model, region: region, endpoint: Generate.parse_url(endpoint), service: service,
            target_model: target_model, target_variant: target_variant, temperature: temperature,
            max_tokens: max_tokens, stop_sequences: Generate.to_text_array(stop_sequences), **image_fields(opts) }
        end
      end

      class GenerativeCohere < GenerativeConfigRuntime
        provider "generative-cohere", :cohere, ::Weaviate::V1::GenerativeCohere
        attributes :base_url, :frequency_penalty, :k, :max_tokens, :model, :p, :presence_penalty, :stop_sequences,
                   :temperature

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { base_url: Generate.parse_url(base_url), frequency_penalty: frequency_penalty, k: k, max_tokens: max_tokens,
            model: model, p: p, presence_penalty: presence_penalty,
            stop_sequences: Generate.to_text_array(stop_sequences), temperature: temperature, **image_fields(opts) }
        end
      end

      class GenerativeDatabricks < GenerativeConfigRuntime
        provider "generative-databricks", :databricks, ::Weaviate::V1::GenerativeDatabricks
        attribute :endpoint
        attributes :frequency_penalty, :log_probs, :max_tokens, :model, :n, :presence_penalty, :stop, :temperature,
                   :top_log_probs, :top_p

        private

        def grpc_fields(_opts)
          { endpoint: Generate.parse_url(endpoint), frequency_penalty: frequency_penalty, log_probs: log_probs || false,
            max_tokens: max_tokens, model: model, n: n, presence_penalty: presence_penalty,
            stop: Generate.to_text_array(stop), temperature: temperature, top_log_probs: top_log_probs, top_p: top_p }
        end
      end

      class GenerativeDeepseek < GenerativeConfigRuntime
        provider "generative-deepseek", :deepseek, ::Weaviate::V1::GenerativeDeepseek
        attributes :base_url, :model, :temperature, :max_tokens, :frequency_penalty, :presence_penalty, :top_p, :stop

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), model: model, temperature: temperature, max_tokens: max_tokens,
            frequency_penalty: frequency_penalty, presence_penalty: presence_penalty, top_p: top_p,
            stop: Generate.to_text_array(stop) }
        end
      end

      class GenerativeDigitalOcean < GenerativeConfigRuntime
        provider "generative-digitalocean", :digitalocean, ::Weaviate::V1::GenerativeDigitalOcean
        attributes :base_url, :model, :temperature, :top_p, :max_tokens, :frequency_penalty, :presence_penalty, :stop

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), model: model, temperature: temperature, top_p: top_p,
            max_tokens: max_tokens, frequency_penalty: frequency_penalty, presence_penalty: presence_penalty,
            stop: Generate.to_text_array(stop) }
        end
      end

      class GenerativeDummy < GenerativeConfigRuntime
        provider "generative-dummy", :dummy, ::Weaviate::V1::GenerativeDummy

        private

        def grpc_fields(_opts) = {}
      end

      class GenerativeFriendliai < GenerativeConfigRuntime
        provider "generative-friendliai", :friendliai, ::Weaviate::V1::GenerativeFriendliAI
        attributes :base_url, :max_tokens, :model, :n, :temperature, :top_p

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), max_tokens: max_tokens, model: model, n: n,
            temperature: temperature, top_p: top_p }
        end
      end

      class GenerativeMeta < GenerativeConfigRuntime
        provider "generative-meta", :meta, ::Weaviate::V1::GenerativeMeta
        attributes :base_url, :model, :temperature, :top_p, :max_tokens, :frequency_penalty, :presence_penalty,
                   :reasoning_effort

        REASONING_EFFORTS = {
          "none" => :REASONING_EFFORT_NONE, "minimal" => :REASONING_EFFORT_MINIMAL, "low" => :REASONING_EFFORT_LOW,
          "medium" => :REASONING_EFFORT_MEDIUM, "high" => :REASONING_EFFORT_HIGH, "xhigh" => :REASONING_EFFORT_XHIGH
        }.freeze

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { base_url: Generate.parse_url(base_url), model: model, temperature: temperature, top_p: top_p,
            max_tokens: max_tokens, frequency_penalty: frequency_penalty, presence_penalty: presence_penalty,
            reasoning_effort: grpc_reasoning_effort, **image_fields(opts) }
        end

        def grpc_reasoning_effort
          return nil if reasoning_effort.nil?

          REASONING_EFFORTS.fetch(reasoning_effort.to_s) do
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid reasoning_effort value: #{reasoning_effort}"
          end
        end
      end

      class GenerativeMistral < GenerativeConfigRuntime
        provider "generative-mistral", :mistral, ::Weaviate::V1::GenerativeMistral
        attributes :base_url, :max_tokens, :model, :temperature, :top_p

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), max_tokens: max_tokens, model: model, temperature: temperature,
            top_p: top_p }
        end
      end

      class GenerativeNvidia < GenerativeConfigRuntime
        provider "generative-nvidia", :nvidia, ::Weaviate::V1::GenerativeNvidia
        attributes :base_url, :max_tokens, :model, :temperature, :top_p

        private

        def grpc_fields(_opts)
          { base_url: Generate.parse_url(base_url), max_tokens: max_tokens, model: model, temperature: temperature,
            top_p: top_p }
        end
      end

      class GenerativeOllama < GenerativeConfigRuntime
        provider "generative-ollama", :ollama, ::Weaviate::V1::GenerativeOllama
        attributes :api_endpoint, :model, :temperature

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { api_endpoint: Generate.parse_url(api_endpoint), model: model, temperature: temperature,
            **image_fields(opts) }
        end
      end

      class GenerativeOpenAI < GenerativeConfigRuntime
        provider "generative-openai", :openai, ::Weaviate::V1::GenerativeOpenAI
        attributes :api_version, :base_url, :deployment_id, :frequency_penalty, :max_tokens, :model, :n,
                   :presence_penalty, :resource_name, :stop, :temperature, :top_p, :verbosity, :reasoning_effort
        attribute :is_azure, default: false

        VERBOSITIES = { "low" => :VERBOSITY_LOW, "medium" => :VERBOSITY_MEDIUM, "high" => :VERBOSITY_HIGH }.freeze
        REASONING_EFFORTS = {
          "minimal" => :REASONING_EFFORT_MINIMAL, "low" => :REASONING_EFFORT_LOW,
          "medium" => :REASONING_EFFORT_MEDIUM, "high" => :REASONING_EFFORT_HIGH
        }.freeze

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { api_version: api_version, base_url: Generate.parse_url(base_url), deployment_id: deployment_id,
            frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model, n: n,
            presence_penalty: presence_penalty, resource_name: resource_name, stop: Generate.to_text_array(stop),
            temperature: temperature, top_p: top_p, is_azure: is_azure, **image_fields(opts),
            verbosity: lookup(VERBOSITIES, verbosity, "verbosity"),
            reasoning_effort: lookup(REASONING_EFFORTS, reasoning_effort, "reasoning_effort") }
        end

        def lookup(table, value, name)
          return nil if value.nil?

          table.fetch(value.to_s) { raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid #{name} value: #{value}" }
        end
      end

      class GenerativeGoogle < GenerativeConfigRuntime
        provider "generative-palm", :google, ::Weaviate::V1::GenerativeGoogle
        attributes :api_endpoint, :endpoint_id, :frequency_penalty, :max_tokens, :model, :presence_penalty,
                   :project_id, :region, :location, :stop_sequences, :temperature, :top_k, :top_p

        private

        def multi_modal? = true

        def parse_api_endpoint(url)
          u = Generate.parse_url(url)
          u&.sub("https://", "")&.sub("http://", "")
        end

        def grpc_fields(opts)
          { api_endpoint: parse_api_endpoint(api_endpoint), endpoint_id: endpoint_id,
            frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model,
            presence_penalty: presence_penalty, project_id: project_id, region: region, location: location,
            stop_sequences: Generate.to_text_array(stop_sequences), temperature: temperature, top_k: top_k,
            top_p: top_p, **image_fields(opts) }
        end
      end

      class GenerativeXAI < GenerativeConfigRuntime
        provider "generative-xai", :xai, ::Weaviate::V1::GenerativeXAI
        attributes :base_url, :max_tokens, :model, :temperature, :top_p

        private

        def multi_modal? = true

        def grpc_fields(opts)
          { base_url: Generate.parse_url(base_url), max_tokens: max_tokens, model: model, temperature: temperature,
            top_p: top_p, **image_fields(opts) }
        end
      end

      class GenerativeContextualAI < GenerativeConfigRuntime
        provider "generative-contextualai", :contextualai, ::Weaviate::V1::GenerativeContextualAI
        attributes :model, :temperature, :top_p, :max_new_tokens, :system_prompt, :avoid_commentary, :knowledge

        private

        def grpc_fields(_opts)
          { model: model, temperature: temperature, top_p: top_p, max_new_tokens: max_new_tokens,
            system_prompt: system_prompt, avoid_commentary: avoid_commentary || false,
            knowledge: Generate.to_text_array(knowledge) }
        end
      end

      # Factory for the `generative_provider` argument of the `.generate` search methods.
      class GenerativeConfig
        class << self
          def anthropic(base_url: nil, model: nil, max_tokens: nil, stop_sequences: nil, temperature: nil, top_k: nil,
                        top_p: nil)
            GenerativeAnthropic.new(base_url: url(base_url), model: model, max_tokens: max_tokens,
                                    stop_sequences: stop_sequences, temperature: temperature, top_k: top_k, top_p: top_p)
          end

          def anyscale(base_url: nil, model: nil, temperature: nil)
            GenerativeAnyscale.new(base_url: url(base_url), model: model, temperature: temperature)
          end

          # @deprecated Use a service-specific method instead, such as `aws_bedrock`.
          def aws(endpoint: nil, max_tokens: nil, model: nil, region: nil, service: nil, target_model: nil,
                  target_variant: nil, temperature: nil)
            GenerativeAWS.new(model: model, max_tokens: max_tokens, region: region, service: service,
                              endpoint: url(endpoint), target_model: target_model, target_variant: target_variant,
                              temperature: temperature, top_k: nil, top_p: nil, stop_sequences: nil)
          end

          def aws_bedrock(endpoint: nil, max_tokens: nil, model: nil, region: nil, temperature: nil, top_k: nil,
                          top_p: nil, stop_sequences: nil)
            GenerativeAWS.new(model: model, max_tokens: max_tokens, region: region, service: "bedrock",
                              endpoint: url(endpoint), target_model: nil, target_variant: nil,
                              temperature: temperature, top_k: top_k, top_p: top_p, stop_sequences: stop_sequences)
          end

          def aws_sagemaker(endpoint: nil, max_tokens: nil, region: nil, target_model: nil, target_variant: nil,
                            temperature: nil, top_k: nil, top_p: nil, stop_sequences: nil)
            GenerativeAWS.new(model: nil, max_tokens: max_tokens, region: region, service: "sagemaker",
                              endpoint: url(endpoint), target_model: target_model, target_variant: target_variant,
                              temperature: temperature, top_k: top_k, top_p: top_p, stop_sequences: stop_sequences)
          end

          def cohere(base_url: nil, frequency_penalty: nil, k: nil, max_tokens: nil, model: nil, p: nil,
                     presence_penalty: nil, stop_sequences: nil, temperature: nil)
            GenerativeCohere.new(base_url: url(base_url), frequency_penalty: frequency_penalty, k: k,
                                 max_tokens: max_tokens, model: model, p: p, presence_penalty: presence_penalty,
                                 stop_sequences: stop_sequences, temperature: temperature)
          end

          def contextualai(model: nil, max_new_tokens: nil, temperature: nil, top_p: nil, system_prompt: nil,
                           avoid_commentary: nil, knowledge: nil)
            GenerativeContextualAI.new(model: model, temperature: temperature, top_p: top_p,
                                       max_new_tokens: max_new_tokens, system_prompt: system_prompt,
                                       avoid_commentary: avoid_commentary, knowledge: knowledge)
          end

          def databricks(endpoint:, frequency_penalty: nil, log_probs: nil, max_tokens: nil, model: nil, n: nil,
                         presence_penalty: nil, stop: nil, temperature: nil, top_log_probs: nil, top_p: nil)
            GenerativeDatabricks.new(endpoint: url(endpoint), frequency_penalty: frequency_penalty,
                                     log_probs: log_probs, max_tokens: max_tokens, model: model, n: n,
                                     presence_penalty: presence_penalty, stop: stop, temperature: temperature,
                                     top_log_probs: top_log_probs, top_p: top_p)
          end

          def deepseek(base_url: nil, model: nil, temperature: nil, max_tokens: nil, frequency_penalty: nil,
                       presence_penalty: nil, top_p: nil, stop: nil)
            GenerativeDeepseek.new(base_url: url(base_url), model: model, temperature: temperature,
                                   max_tokens: max_tokens, frequency_penalty: frequency_penalty,
                                   presence_penalty: presence_penalty, top_p: top_p, stop: stop)
          end

          def digitalocean(base_url: nil, model: nil, temperature: nil, top_p: nil, max_tokens: nil,
                           frequency_penalty: nil, presence_penalty: nil, stop: nil)
            GenerativeDigitalOcean.new(base_url: url(base_url), model: model, temperature: temperature, top_p: top_p,
                                       max_tokens: max_tokens, frequency_penalty: frequency_penalty,
                                       presence_penalty: presence_penalty, stop: stop)
          end

          def dummy = GenerativeDummy.new

          def friendliai(base_url: nil, max_tokens: nil, model: nil, n: nil, temperature: nil, top_p: nil)
            GenerativeFriendliai.new(base_url: url(base_url), max_tokens: max_tokens, model: model, n: n,
                                     temperature: temperature, top_p: top_p)
          end

          # @deprecated Use a service-specific method instead, such as `google_vertex` or `google_gemini`.
          def google(api_endpoint: nil, endpoint_id: nil, frequency_penalty: nil, max_tokens: nil, model: nil,
                     presence_penalty: nil, project_id: nil, region: nil, stop_sequences: nil, temperature: nil,
                     top_k: nil, top_p: nil)
            GenerativeGoogle.new(api_endpoint: url(api_endpoint), endpoint_id: endpoint_id,
                                 frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model,
                                 presence_penalty: presence_penalty, project_id: project_id, region: region,
                                 location: nil, stop_sequences: stop_sequences, temperature: temperature,
                                 top_k: top_k, top_p: top_p)
          end

          def google_vertex(api_endpoint: nil, project_id: nil, endpoint_id: nil, region: nil, frequency_penalty: nil,
                            max_tokens: nil, model: nil, presence_penalty: nil, temperature: nil, top_k: nil,
                            top_p: nil, stop_sequences: nil, location: nil)
            GenerativeGoogle.new(api_endpoint: url(api_endpoint), endpoint_id: endpoint_id,
                                 frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model,
                                 presence_penalty: presence_penalty, project_id: project_id, region: region,
                                 location: location, stop_sequences: stop_sequences, temperature: temperature,
                                 top_k: top_k, top_p: top_p)
          end

          def google_gemini(frequency_penalty: nil, max_tokens: nil, model: nil, presence_penalty: nil,
                            temperature: nil, top_k: nil, top_p: nil, stop_sequences: nil)
            GenerativeGoogle.new(api_endpoint: url("https://generativelanguage.googleapis.com"), endpoint_id: nil,
                                 frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model,
                                 presence_penalty: presence_penalty, project_id: nil, region: nil, location: nil,
                                 stop_sequences: stop_sequences, temperature: temperature, top_k: top_k, top_p: top_p)
          end

          def meta(base_url: nil, model: nil, temperature: nil, top_p: nil, max_tokens: nil, frequency_penalty: nil,
                   presence_penalty: nil, reasoning_effort: nil)
            GenerativeMeta.new(base_url: url(base_url), model: model, temperature: temperature, top_p: top_p,
                               max_tokens: max_tokens, frequency_penalty: frequency_penalty,
                               presence_penalty: presence_penalty, reasoning_effort: reasoning_effort)
          end

          def mistral(base_url: nil, max_tokens: nil, model: nil, temperature: nil, top_p: nil)
            GenerativeMistral.new(base_url: url(base_url), max_tokens: max_tokens, model: model,
                                  temperature: temperature, top_p: top_p)
          end

          def nvidia(base_url: nil, max_tokens: nil, model: nil, temperature: nil, top_p: nil)
            GenerativeNvidia.new(base_url: url(base_url), max_tokens: max_tokens, model: model,
                                 temperature: temperature, top_p: top_p)
          end

          def ollama(api_endpoint: nil, model: nil, temperature: nil)
            GenerativeOllama.new(api_endpoint: url(api_endpoint), model: model, temperature: temperature)
          end

          def openai(api_version: nil, base_url: nil, deployment_id: nil, frequency_penalty: nil, max_tokens: nil,
                     model: nil, n: nil, presence_penalty: nil, reasoning_effort: nil, resource_name: nil, stop: nil,
                     temperature: nil, top_p: nil, verbosity: nil)
            GenerativeOpenAI.new(api_version: api_version, base_url: url(base_url), deployment_id: deployment_id,
                                 frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model, n: n,
                                 presence_penalty: presence_penalty, resource_name: resource_name, stop: stop,
                                 temperature: temperature, top_p: top_p, is_azure: false, verbosity: verbosity,
                                 reasoning_effort: reasoning_effort)
          end

          def azure_openai(api_version: nil, base_url: nil, deployment_id: nil, frequency_penalty: nil,
                           max_tokens: nil, model: nil, n: nil, presence_penalty: nil, resource_name: nil, stop: nil,
                           temperature: nil, top_p: nil)
            GenerativeOpenAI.new(api_version: api_version, base_url: url(base_url), deployment_id: deployment_id,
                                 frequency_penalty: frequency_penalty, max_tokens: max_tokens, model: model, n: n,
                                 presence_penalty: presence_penalty, resource_name: resource_name, stop: stop,
                                 temperature: temperature, top_p: top_p, is_azure: true, verbosity: nil,
                                 reasoning_effort: nil)
          end

          def xai(base_url: nil, max_tokens: nil, model: nil, temperature: nil, top_p: nil)
            GenerativeXAI.new(base_url: url(base_url), max_tokens: max_tokens, model: model, temperature: temperature,
                              top_p: top_p)
          end

          private

          # Validate eagerly (Python validates with pydantic's AnyHttpUrl at construction time).
          def url(value)
            Generate.parse_url(value)
            value
          end
        end
      end

      # Python _GroupedTask
      class GroupedTask < ::Weaviate::Model
        attribute :prompt
        attribute :non_blob_properties, default: nil
        attribute :image_properties, default: nil
        attribute :images, default: nil
        attribute :metadata, default: false

        def to_grpc(provider)
          ::Weaviate::V1::GenerativeSearch::Grouped.new(
            task: prompt,
            properties: Generate.to_text_array(non_blob_properties),
            queries: [provider.to_grpc(GenerativeConfigRuntimeOptions.new(return_metadata: metadata, images: images,
                                                                          image_properties: image_properties))]
          )
        end
      end

      # Python _SinglePrompt
      class SinglePrompt < ::Weaviate::Model
        attribute :prompt
        attribute :image_properties, default: nil
        attribute :images, default: nil
        attribute :metadata, default: false
        attribute :debug, default: false

        def to_grpc(provider)
          ::Weaviate::V1::GenerativeSearch::Single.new(
            prompt: prompt,
            debug: debug,
            queries: [provider.to_grpc(GenerativeConfigRuntimeOptions.new(return_metadata: metadata, images: images,
                                                                          image_properties: image_properties))]
          )
        end
      end

      # Factory for the `single_prompt` / `grouped_task` arguments of the `.generate` search methods.
      class GenerativeParameters
        class << self
          def grouped_task(prompt, non_blob_properties: nil, image_properties: nil, images: nil, metadata: false)
            GroupedTask.new(prompt: prompt, non_blob_properties: non_blob_properties,
                            image_properties: image_properties, images: parse_images(images), metadata: metadata)
          end

          def single_prompt(prompt, image_properties: nil, images: nil, metadata: false, debug: false)
            SinglePrompt.new(prompt: prompt, image_properties: image_properties, images: parse_images(images),
                             metadata: metadata, debug: debug)
          end

          private

          def parse_images(images)
            return nil if images.nil?
            return [::Weaviate::Util.parse_blob(images)] if images.is_a?(String) || images.is_a?(Pathname) ||
                                                           images.respond_to?(:read)

            images.map { |image| ::Weaviate::Util.parse_blob(image) }
          end
        end
      end
    end
  end
end
