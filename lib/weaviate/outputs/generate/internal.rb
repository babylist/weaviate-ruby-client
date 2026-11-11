# frozen_string_literal: true

require_relative "../query/internal"

module Weaviate
  module Outputs
    # Return types of the `.generate` namespace (port of weaviate.collections.classes.internal).
    module Generate
      # The generative data returned relevant to a single prompt generative query.
      # +debug+ is a Weaviate::V1::GenerativeDebug, +metadata+ a provider-specific Weaviate::V1::Generative*Metadata.
      class GenerativeSingle < ::Weaviate::Model
        attribute :debug
        attribute :metadata
        attribute :text
      end

      # The generative data returned relevant to a grouped prompt generative query.
      class GenerativeGrouped < ::Weaviate::Model
        attribute :metadata
        attribute :text
      end

      # A single Weaviate object returned by a query within the `generate` namespace of a collection.
      class GenerativeObject < ::Weaviate::Outputs::Query::Object
        attribute :generated, default: nil
        attribute :generative, default: nil
      end

      # The return type of a query within the `generate` namespace of a collection.
      class GenerativeReturn < ::Weaviate::Model
        attribute :generated, default: nil # deprecated: use generative.text
        attribute :objects
        attribute :generative, default: nil
        attribute :query_profile, default: nil
      end

      # A group of objects returned in a generative group by query.
      class GenerativeGroup < ::Weaviate::Outputs::Query::Group
        attribute :generated, default: nil
      end

      # The return type of a `.generate` query with the `group_by` argument specified.
      class GenerativeGroupByReturn < ::Weaviate::Model
        attribute :objects
        attribute :groups
        attribute :generated, default: nil
        attribute :query_profile, default: nil
      end
    end
  end
end
