# frozen_string_literal: true

module Weaviate
  module Classes
    # Port of weaviate.classes.aggregate (Metrics, GroupByAggregate) and the
    # internal _Metrics* request models.
    module Aggregate
      Agg = ::Weaviate::V1::AggregateRequest::Aggregation

      class MetricsBase < ::Weaviate::Model
        attribute :property_name
        attribute :count, default: false

        def to_grpc
          raise NotImplementedError
        end

        private

        def gql_body(*parts) = parts.join(" ")
      end

      class MetricsText < MetricsBase
        attribute :top_occurrences_count, default: false
        attribute :top_occurrences_value, default: false
        attribute :limit, default: nil

        def to_gql
          limit_str = limit.nil? ? "" : "(limit: #{limit})"
          top = top_occurrences_count || top_occurrences_value
          body = gql_body(count ? "count" : "", top ? "topOccurrences#{limit_str} {" : "",
                          top_occurrences_count ? "occurs" : "", top_occurrences_value ? "value" : "", top ? "}" : "")
          "#{property_name} { #{body} }"
        end

        def to_grpc
          Agg.new(property: property_name,
                  text: Agg::Text.new(count: count, top_occurences: top_occurrences_count, top_occurences_limit: limit))
        end
      end

      class MetricsNum < MetricsBase
        attribute :maximum, default: false
        attribute :mean, default: false
        attribute :median, default: false
        attribute :minimum, default: false
        attribute :mode, default: false
        attribute :sum_, default: false

        def to_gql
          body = gql_body(count ? "count" : "", maximum ? "maximum" : "", mean ? "mean" : "", median ? "median" : "",
                          minimum ? "minimum" : "", mode ? "mode" : "", sum_ ? "sum" : "")
          "#{property_name} { #{body} }"
        end

        private

        def num_fields
          { count: count, maximum: maximum, mean: mean, median: median, minimum: minimum, mode: mode, sum: sum_ }
        end
      end

      class MetricsInteger < MetricsNum
        def to_grpc = Agg.new(property: property_name, int: Agg::Integer.new(**num_fields))
      end

      class MetricsNumber < MetricsNum
        def to_grpc = Agg.new(property: property_name, number: Agg::Number.new(**num_fields))
      end

      class MetricsBoolean < MetricsBase
        attribute :percentage_false, default: false
        attribute :percentage_true, default: false
        attribute :total_false, default: false
        attribute :total_true, default: false

        def to_gql
          body = gql_body(count ? "count" : "", percentage_false ? "percentageFalse" : "",
                          percentage_true ? "percentageTrue" : "", total_false ? "totalFalse" : "",
                          total_true ? "totalTrue" : "")
          "#{property_name} { #{body} }"
        end

        def to_grpc
          Agg.new(property: property_name,
                  boolean: Agg::Boolean.new(count: count, percentage_false: percentage_false,
                                            percentage_true: percentage_true, total_false: total_false,
                                            total_true: total_true))
        end
      end

      class MetricsDate < MetricsBase
        attribute :maximum, default: false
        attribute :median, default: false
        attribute :minimum, default: false
        attribute :mode, default: false

        def to_gql
          body = gql_body(count ? "count" : "", maximum ? "maximum" : "", median ? "median" : "",
                          minimum ? "minimum" : "", mode ? "mode" : "")
          "#{property_name} { #{body} }"
        end

        def to_grpc
          Agg.new(property: property_name,
                  date: Agg::Date.new(count: count, maximum: maximum, median: median, minimum: minimum, mode: mode))
        end
      end

      class MetricsReference < ::Weaviate::Model
        attribute :property_name
        attribute :pointing_to, default: false

        def to_gql = "#{property_name} { #{pointing_to ? "pointingTo" : ""} }"

        def to_grpc
          Agg.new(property: property_name, reference: Agg::Reference.new(pointing_to: pointing_to))
        end
      end

      class GroupByAggregate < ::Weaviate::Model
        attribute :prop
        attribute :limit, default: nil

        def after_initialize
          raise TypeError, "prop must be a String" unless prop.is_a?(String)
          raise TypeError, "limit must be an Integer" unless limit.nil? || limit.is_a?(Integer)
        end

        def to_grpc
          ::Weaviate::V1::AggregateRequest::GroupBy.new(collection: "", property: prop)
        end
      end

      # Metrics.new("prop").integer(mean: true)
      class Metrics
        def initialize(property)
          @property = property
        end

        def text(count: false, top_occurrences_count: false, top_occurrences_value: false, limit: nil,
                 min_occurrences: nil)
          if !limit.nil? && !min_occurrences.nil?
            raise ArgumentError, "You cannot use both `limit` and `min_occurrences` at the same time. Use `limit` instead."
          end

          ::Weaviate::Warnings.min_occurrences_metric_deprecated unless min_occurrences.nil?
          count = top_occurrences_count = top_occurrences_value = true unless count || top_occurrences_count || top_occurrences_value
          MetricsText.new(property_name: @property, count: count, top_occurrences_count: top_occurrences_count,
                          top_occurrences_value: top_occurrences_value, limit: limit.nil? ? min_occurrences : limit)
        end

        def integer(count: false, maximum: false, mean: false, median: false, minimum: false, mode: false, sum_: false)
          MetricsInteger.new(property_name: @property, **all_if_none(count: count, maximum: maximum, mean: mean,
                                                                     median: median, minimum: minimum, mode: mode,
                                                                     sum_: sum_))
        end

        def number(count: false, maximum: false, mean: false, median: false, minimum: false, mode: false, sum_: false)
          MetricsNumber.new(property_name: @property, **all_if_none(count: count, maximum: maximum, mean: mean,
                                                                    median: median, minimum: minimum, mode: mode,
                                                                    sum_: sum_))
        end

        def boolean(count: false, percentage_false: false, percentage_true: false, total_false: false, total_true: false)
          MetricsBoolean.new(property_name: @property,
                             **all_if_none(count: count, percentage_false: percentage_false,
                                           percentage_true: percentage_true, total_false: total_false,
                                           total_true: total_true))
        end

        def date_(count: false, maximum: false, median: false, minimum: false, mode: false)
          MetricsDate.new(property_name: @property,
                          **all_if_none(count: count, maximum: maximum, median: median, minimum: minimum, mode: mode))
        end
        alias date date_

        def reference(pointing_to: false)
          MetricsReference.new(property_name: @property, pointing_to: true || pointing_to)
        end

        private

        def all_if_none(**flags)
          flags.values.any? ? flags : flags.transform_values { true }
        end
      end
    end
  end
end
