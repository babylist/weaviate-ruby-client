# frozen_string_literal: true

require_relative "query/internal"
require_relative "generate/internal"

module Weaviate
  module Outputs
    # Mirrors weaviate.outputs.query. Static type aliases of the Python module
    # (WeaviateField, QueryReturnType, NearVectorInputType, ...) have no Ruby counterpart.
    module Query
      FilterByCreationTime = ::Weaviate::Classes::Query::FilterByCreationTime
      FilterById = ::Weaviate::Classes::Query::FilterById
      FilterByProperty = ::Weaviate::Classes::Query::FilterByProperty
      FilterByRef = ::Weaviate::Classes::Query::FilterByRef
      FilterByUpdateTime = ::Weaviate::Classes::Query::FilterByUpdateTime
      FilterReturn = ::Weaviate::Classes::Query::Filters

      BM25OperatorAnd = ::Weaviate::Classes::Query::BM25OperatorAnd
      BM25OperatorAndCross = ::Weaviate::Classes::Query::BM25OperatorAndCross
      BM25OperatorOr = ::Weaviate::Classes::Query::BM25OperatorOr
      ListOfVectorsQuery = ::Weaviate::Classes::Query::ListOfVectorsQuery
      MMR = ::Weaviate::Classes::Query::MMR
      Sorting = ::Weaviate::Classes::Query::Sorting

      GenerativeObject = ::Weaviate::Outputs::Generate::GenerativeObject
      GenerativeReturn = ::Weaviate::Outputs::Generate::GenerativeReturn
      GenerativeGroupByReturn = ::Weaviate::Outputs::Generate::GenerativeGroupByReturn
      GenerativeGroup = ::Weaviate::Outputs::Generate::GenerativeGroup
      GenerativeSingle = ::Weaviate::Outputs::Generate::GenerativeSingle
      GenerativeGrouped = ::Weaviate::Outputs::Generate::GenerativeGrouped

      def self.const_missing(name)
        return super unless name == :GeoCoordinate

        const_set(name, ::Weaviate::Classes::Data::GeoCoordinate)
      end
    end
  end
end
