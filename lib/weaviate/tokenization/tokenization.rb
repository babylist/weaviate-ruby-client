# frozen_string_literal: true

module Weaviate
  # Port of weaviate.tokenization (`client.tokenization`).
  module Tokenization
    # Result of a tokenization operation.
    #
    # indexed: tokens as they would be stored in the inverted index.
    # query: tokens as they would be used for querying (after stopword removal).
    class TokenizeResult < ::Weaviate::Model
      attribute :indexed
      attribute :query

      def self.from_weaviate(data)
        new(indexed: data.fetch("indexed"), query: data.fetch("query"))
      end
    end

    # Port of weaviate.tokenization.sync._Tokenization.
    class Tokenization
      def initialize(connection)
        @connection = connection
      end

      # Tokenize text using the generic /v1/tokenize endpoint.
      #
      # +stopwords+ (a StopwordsCreate or StopwordsConfig) and +stopword_presets+
      # (Hash of name => Array of words) are mutually exclusive.
      def text(text_ = nil, tokenization_ = nil, text: text_, tokenization: tokenization_, analyzer_config: nil,
               stopwords: nil, stopword_presets: nil)
        check_version

        if !stopwords.nil? && !stopword_presets.nil?
          raise ArgumentError, "stopwords and stopword_presets are mutually exclusive; pass only one"
        end

        payload = { "text" => text, "tokenization" => tokenization.to_s }

        unless analyzer_config.nil?
          ac_dict = analyzer_config.to_dict
          payload["analyzerConfig"] = ac_dict if ac_dict && !ac_dict.empty?
        end

        unless stopwords.nil?
          config = ::Weaviate::Classes::Config
          if config.const_defined?(:StopwordsConfig) && stopwords.is_a?(config::StopwordsConfig)
            # Widen from the read-side shape returned by config.get to the write-side shape.
            create = config::StopwordsCreate
            stopwords = create.new(**create.attribute_names.to_h { |n| [n, stopwords.public_send(n)] })
          end
          sw_dict = stopwords.to_dict
          payload["stopwords"] = sw_dict if sw_dict && !sw_dict.empty?
        end

        unless stopword_presets.nil?
          validated = {}
          stopword_presets.each do |name, words|
            unless words.is_a?(Array)
              raise ArgumentError, "stopword_presets[#{name.to_s.inspect}] must be a list of strings, got #{words.class}"
            end
            unless words.all? { |w| w.is_a?(String) }
              raise ArgumentError, "stopword_presets[#{name.to_s.inspect}] must contain only strings"
            end

            validated[name.to_s] = words.dup
          end
          payload["stopwordPresets"] = validated
        end

        res = @connection.post(
          "/tokenize", weaviate_object: payload, error_msg: "Tokenization failed",
                       status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "tokenize text")
        )
        TokenizeResult.from_weaviate(res.json)
      end

      # Tokenize text using a property's configured tokenization settings.
      def for_property(collection_ = nil, property_name_ = nil, text_ = nil, collection: collection_,
                       property_name: property_name_, text: text_)
        check_version

        path = "/schema/#{::Weaviate::Util.capitalize_first_letter(collection)}/properties/#{property_name}/tokenize"
        res = @connection.post(
          path, weaviate_object: { "text" => text }, error_msg: "Property tokenization failed",
                status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "tokenize property text")
        )
        TokenizeResult.from_weaviate(res.json)
      end

      private

      def check_version
        version = @connection.weaviate_version
        return unless version.is_lower_than(1, 37, 0)

        raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Tokenization", version.to_s, "1.37.0")
      end
    end
  end
end
