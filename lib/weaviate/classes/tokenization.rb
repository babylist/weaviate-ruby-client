# frozen_string_literal: true

require_relative "../tokenization/tokenization"

module Weaviate
  module Classes
    # Port of weaviate.classes.tokenization. The schema-config classes (StopwordsConfig,
    # StopwordsCreate, StopwordsPreset, TextAnalyzerConfigCreate, Tokenization) are resolved
    # lazily from Weaviate::Classes::Config.
    module Tokenization
      TokenizeResult = ::Weaviate::Tokenization::TokenizeResult

      CONFIG_EXPORTS = %i[StopwordsConfig StopwordsCreate StopwordsPreset TextAnalyzerConfigCreate Tokenization].freeze

      def self.const_missing(name)
        return super unless CONFIG_EXPORTS.include?(name)

        ::Weaviate::Classes::Config.const_get(name, false)
      end
    end
  end
end
