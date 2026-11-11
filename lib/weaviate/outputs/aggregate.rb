# frozen_string_literal: true

module Weaviate
  module Outputs
    # Port of the result dataclasses in weaviate.collections.classes.aggregate
    # (exported by weaviate.outputs.aggregate).
    module Aggregate
      class AggregateInteger < ::Weaviate::Model
        attributes :count, :maximum, :mean, :median, :minimum, :mode, :sum_
      end

      class AggregateNumber < ::Weaviate::Model
        attributes :count, :maximum, :mean, :median, :minimum, :mode, :sum_
      end

      class TopOccurrence < ::Weaviate::Model
        attributes :count, :value
      end

      class AggregateText < ::Weaviate::Model
        attribute :count, default: nil
        attribute :top_occurrences, default: -> { [] }
      end

      class AggregateBoolean < ::Weaviate::Model
        attributes :count, :percentage_false, :percentage_true, :total_false, :total_true
      end

      class AggregateReference < ::Weaviate::Model
        attributes :pointing_to
      end

      class AggregateDate < ::Weaviate::Model
        attributes :count, :maximum, :median, :minimum, :mode
      end

      class AggregateReturn < ::Weaviate::Model
        attribute :properties, default: -> { {} }
        attribute :total_count, default: nil
      end

      class GroupedBy < ::Weaviate::Model
        attributes :prop, :value
      end

      class AggregateGroup < ::Weaviate::Model
        attribute :grouped_by
        attribute :properties, default: -> { {} }
        attribute :total_count, default: nil
      end

      class AggregateGroupByReturn < ::Weaviate::Model
        attribute :groups, default: -> { [] }
      end
    end
  end
end
