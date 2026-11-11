# frozen_string_literal: true

require "date"

module Weaviate
  module Collections
    module Grpc
      # Port of weaviate.collections.filters._FilterToGRPC: converts a filter built with
      # Weaviate::Classes::Query::Filter into a Weaviate::V1::Filters protobuf message.
      #
      #   Weaviate::Collections::Grpc::FilterToGRPC.convert(filter) # => Weaviate::V1::Filters or nil
      module FilterToGRPC
        Q = ::Weaviate::Classes::Query

        module_function

        def convert(weav_filter)
          return nil if weav_filter.nil?
          return value_filter(weav_filter) if weav_filter.is_a?(Q::FilterValue)

          and_or_not_filter(weav_filter)
        end

        def value_filter(weav_filter)
          value = weav_filter.value
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, Q::EMPTY_LIST_FILTER_MSG if value.is_a?(Array) && value.empty?

          operator = Q::Operator.to_grpc(weav_filter.operator)
          target = to_target(weav_filter.target)
          if [true, false].include?(value)
            return ::Weaviate::V1::Filters.new(operator: operator, value_boolean: value, target: target)
          end

          ::Weaviate::V1::Filters.new(
            operator: operator,
            value_text: filter_to_text(value),
            value_int: value.is_a?(Integer) ? value : nil,
            value_number: value.is_a?(Float) ? value : nil,
            value_boolean_array: filter_to_bool_list(value),
            value_int_array: filter_to_int_list(value),
            value_number_array: filter_to_float_list(value),
            value_text_array: filter_to_text_list(value),
            value_geo: filter_to_geo(value),
            target: target
          )
        end

        def to_target(target)
          case target
          when String
            ::Weaviate::V1::FilterTarget.new(property: target)
          when Q::CountRef
            ::Weaviate::V1::FilterTarget.new(count: ::Weaviate::V1::FilterReferenceCount.new(on: target.link_on))
          when Q::SingleTargetRef
            ::Weaviate::V1::FilterTarget.new(
              single_target: ::Weaviate::V1::FilterReferenceSingleTarget.new(on: target.link_on,
                                                                             target: to_target(target.target))
            )
          when Q::MultiTargetRef
            ::Weaviate::V1::FilterTarget.new(
              multi_target: ::Weaviate::V1::FilterReferenceMultiTarget.new(
                on: target.link_on, target: to_target(target.target), target_collection: target.target_collection
              )
            )
          else
            raise ArgumentError, "Unknown filter target: #{target.inspect}"
          end
        end

        def time?(value)
          value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(Date)
        end

        def time_to_string(value)
          ::Weaviate::Util.datetime_to_string(value)
        end

        def filter_to_geo(value)
          return nil unless value.is_a?(Q::GeoCoordinateFilter)

          ::Weaviate::V1::GeoCoordinatesFilter.new(latitude: Float(value.latitude), longitude: Float(value.longitude),
                                                   distance: Float(value.distance))
        end

        def filter_to_text(value)
          return value if value.is_a?(String)
          return value.to_s if value.is_a?(Symbol)
          return time_to_string(value) if time?(value)

          nil
        end

        def filter_to_text_list(value)
          return nil unless value.is_a?(Array) && !value.empty?

          first = value[0]
          if first.is_a?(String) || first.is_a?(Symbol)
            ::Weaviate::V1::TextArray.new(values: value.map(&:to_s))
          elsif time?(first)
            ::Weaviate::V1::TextArray.new(values: value.map { |d| time_to_string(d) })
          end
        end

        def filter_to_bool_list(value)
          return nil unless value.is_a?(Array) && !value.empty? && [true, false].include?(value[0])

          ::Weaviate::V1::BooleanArray.new(values: value)
        end

        def filter_to_float_list(value)
          return nil unless value.is_a?(Array) && !value.empty? && value[0].is_a?(Float)

          ::Weaviate::V1::NumberArray.new(values: value.map { |v| Float(v) })
        end

        def filter_to_int_list(value)
          return nil unless value.is_a?(Array) && !value.empty? && value[0].is_a?(Integer)

          ::Weaviate::V1::IntArray.new(values: value)
        end

        def and_or_not_filter(weav_filter)
          ::Weaviate::V1::Filters.new(
            operator: Q::Operator.to_grpc(weav_filter.operator),
            filters: weav_filter.filters.filter_map { |f| convert(f) }
          )
        end
      end

      # Port of weaviate.collections.filters._FilterToREST: converts a filter into the
      # REST/GraphQL `where` JSON shape.
      module FilterToREST
        Q = ::Weaviate::Classes::Query

        module_function

        def convert(weav_filter)
          return value_filter(weav_filter) if weav_filter.is_a?(Q::FilterValue)

          {
            "operator" => weav_filter.operator,
            "operands" => weav_filter.filters.filter_map { |f| convert(f) }
          }
        end

        def value_filter(weav_filter)
          { "operator" => weav_filter.operator, "path" => to_path(weav_filter.target),
            **parse_filter(weav_filter.value) }
        end

        def to_path(target)
          case target
          when String then [target]
          when Q::SingleTargetRef
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Cannot use Filter.by_ref() in the aggregate API currently. Instead use " \
                  "Filter.by_ref_multi_target() and specify the target collection explicitly."
          when Q::MultiTargetRef
            [target.link_on, target.target_collection, *to_path(target.target)]
          else
            raise ArgumentError, "Unknown filter target: #{target.inspect}"
          end
        end

        def parse_filter(value)
          return { "valueText" => value } if value.is_a?(String)
          return { "valueDate" => ::Weaviate::Util.datetime_to_string(value) } if FilterToGRPC.time?(value)
          return { "valueBoolean" => value } if [true, false].include?(value)
          return { "valueInt" => value } if value.is_a?(Integer)
          return { "valueNumber" => value } if value.is_a?(Float)

          if value.is_a?(Array)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, Q::EMPTY_LIST_FILTER_MSG if value.empty?

            first = value[0]
            return { "valueTextArray" => value } if first.is_a?(String)
            if FilterToGRPC.time?(first)
              return { "valueDateArray" => value.map { |v| ::Weaviate::Util.datetime_to_string(v) } }
            end
            return { "valueBooleanArray" => value } if [true, false].include?(first)
            return { "valueIntArray" => value } if first.is_a?(Integer)
            return { "valueNumberArray" => value } if first.is_a?(Float)
          end
          raise ArgumentError, "Unknown filter value type: #{value.class}"
        end
      end
    end
  end
end
