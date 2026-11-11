# frozen_string_literal: true

module Weaviate
  # Port of weaviate.connect.integrations + weaviate.integrations
  module Integrations
    # Header-producing integration config. +fields+ maps attribute => header name.
    class IntegrationConfig
      def initialize(fields, values)
        @fields = fields
        @values = values
      end

      def to_header
        @fields.each_with_object({}) do |(attr, header), h|
          value = @values[attr]
          h[header] = value.to_s unless value.nil?
        end
      end
      alias to_h to_header
    end

    def self.build(prefix, mapping, values)
      raise ArgumentError, "api_key is required" if values.key?(:api_key) && values[:api_key].nil?

      IntegrationConfig.new(mapping.transform_values { |v| "X-#{prefix}-#{v}" }, values)
    end

    def self.cohere(api_key:, base_url: nil, requests_per_minute_embeddings: nil)
      build("Cohere", { api_key: "Api-Key", requests_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                        base_url: "Baseurl" }, binding_values(binding))
    end

    def self.huggingface(api_key:, requests_per_minute_embeddings: nil, base_url: nil)
      build("Huggingface", { api_key: "Api-Key", requests_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                             base_url: "Baseurl" }, binding_values(binding))
    end

    def self.openai(api_key:, requests_per_minute_embeddings: nil, tokens_per_minute_embeddings: nil,
                    organization: nil, base_url: nil)
      build("Openai", { api_key: "Api-Key", organization: "Organization",
                        requests_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                        tokens_per_minute_embeddings: "Ratelimit-TokenPM-Embedding",
                        base_url: "Baseurl" }, binding_values(binding))
    end

    def self.voyageai(api_key:, requests_per_minute_embeddings: nil, tokens_per_minute_embeddings: nil, base_url: nil)
      build("Voyageai", { api_key: "Api-Key", requests_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                          tokens_per_minute_embeddings: "Ratelimit-TokenPM-Embedding",
                          base_url: "Baseurl" }, binding_values(binding))
    end

    def self.jinaai(api_key:, requests_per_minute_embeddings: nil, base_url: nil)
      build("Jinaai", { api_key: "Api-Key", requests_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                        base_url: "Baseurl" }, binding_values(binding))
    end

    def self.mistral(api_key:, request_per_minute_embeddings: nil, tokens_per_minute_embeddings: nil)
      build("Mistral", { api_key: "Api-Key", request_per_minute_embeddings: "Ratelimit-RequestPM-Embedding",
                         tokens_per_minute_embeddings: "Ratelimit-TokenPM-Embedding" }, binding_values(binding))
    end

    def self.binding_values(bind)
      bind.local_variables.to_h { |v| [v, bind.local_variable_get(v)] }
    end
    private_class_method :binding_values

    # client.integrations
    class Namespace
      def initialize(connection)
        @connection = connection
      end

      def configure(integrations_config)
        integrations_config = [integrations_config] unless integrations_config.is_a?(Array)
        @connection.set_integrations(integrations_config)
        nil
      end
    end
  end
end
