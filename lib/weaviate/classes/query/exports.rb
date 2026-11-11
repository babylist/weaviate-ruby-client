# frozen_string_literal: true

require_relative "../generate/generative"

module Weaviate
  module Classes
    # Mirrors weaviate.classes.query. Filters, query inputs and return-reference
    # helpers are defined in this module's other files.
    module Query
      GenerativeConfig = ::Weaviate::Classes::Generate::GenerativeConfig

      # Names exported by weaviate.classes.query that are defined by other areas
      # (Metrics: aggregate, GeoCoordinate: data types) are resolved lazily.
      LAZY_EXPORTS = {
        Metrics: "Weaviate::Classes::Aggregate::Metrics",
        GeoCoordinate: "Weaviate::Classes::Data::GeoCoordinate"
      }.freeze

      def self.const_missing(name)
        target = LAZY_EXPORTS[name]
        return super if target.nil?

        value = Object.const_get(target)
        const_set(name, value)
      end
    end
  end
end
