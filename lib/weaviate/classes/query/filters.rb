# frozen_string_literal: true

module Weaviate
  module Classes
    module Query
      # Port of weaviate.collections.classes.filters._Operator
      module Operator
        extend ::Weaviate::StrEnum

        EQUAL = "Equal"
        NOT_EQUAL = "NotEqual"
        LESS_THAN = "LessThan"
        LESS_THAN_EQUAL = "LessThanEqual"
        GREATER_THAN = "GreaterThan"
        GREATER_THAN_EQUAL = "GreaterThanEqual"
        LIKE = "Like"
        IS_NULL = "IsNull"
        CONTAINS_ANY = "ContainsAny"
        CONTAINS_ALL = "ContainsAll"
        CONTAINS_NONE = "ContainsNone"
        WITHIN_GEO_RANGE = "WithinGeoRange"
        AND = "And"
        OR = "Or"
        NOT = "Not"

        TO_GRPC = {
          EQUAL => :OPERATOR_EQUAL,
          NOT_EQUAL => :OPERATOR_NOT_EQUAL,
          LESS_THAN => :OPERATOR_LESS_THAN,
          LESS_THAN_EQUAL => :OPERATOR_LESS_THAN_EQUAL,
          GREATER_THAN => :OPERATOR_GREATER_THAN,
          GREATER_THAN_EQUAL => :OPERATOR_GREATER_THAN_EQUAL,
          LIKE => :OPERATOR_LIKE,
          IS_NULL => :OPERATOR_IS_NULL,
          CONTAINS_ANY => :OPERATOR_CONTAINS_ANY,
          CONTAINS_ALL => :OPERATOR_CONTAINS_ALL,
          CONTAINS_NONE => :OPERATOR_CONTAINS_NONE,
          WITHIN_GEO_RANGE => :OPERATOR_WITHIN_GEO_RANGE,
          AND => :OPERATOR_AND,
          OR => :OPERATOR_OR,
          NOT => :OPERATOR_NOT
        }.freeze

        # Python: _Operator._to_grpc()
        def self.to_grpc(operator)
          TO_GRPC.fetch(operator)
        end
      end

      # Base of every filter (Python _Filters). Supports `&`, `|` and `~`.
      class Filters
        def &(other)
          FilterAnd.new([self, other])
        end

        def |(other)
          FilterOr.new([self, other])
        end

        def ~
          FilterNot.new(self)
        end
      end

      # Python _FilterAnd / _FilterOr / _FilterNot
      class FilterCombination < Filters
        attr_reader :filters

        def initialize(filters)
          super()
          @filters = filters
        end

        def ==(other)
          other.class == self.class && other.filters == filters
        end
        alias eql? ==

        def hash = [self.class, filters].hash

        def inspect = "#<#{self.class.name} operator=#{operator} filters=#{filters.inspect}>"
      end

      class FilterAnd < FilterCombination
        def operator = Operator::AND
      end

      class FilterOr < FilterCombination
        def operator = Operator::OR
      end

      class FilterNot < FilterCombination
        def initialize(filter)
          super([filter])
        end

        def operator = Operator::NOT
      end

      # Python _GeoCoordinateFilter
      class GeoCoordinateFilter < ::Weaviate::Model
        attribute :latitude
        attribute :longitude
        attribute :distance
      end

      # Python _SingleTargetRef
      class SingleTargetRef < ::Weaviate::Model
        attribute :link_on
        attribute :target, default: nil
      end

      # Python _MultiTargetRef
      class MultiTargetRef < ::Weaviate::Model
        attribute :target_collection
        attribute :link_on
        attribute :target, default: nil
      end

      # Python _CountRef
      class CountRef < ::Weaviate::Model
        attribute :link_on
      end

      EMPTY_LIST_FILTER_MSG = "Filtering on empty lists is not supported by Weaviate. " \
                              "To filter by property length, use " \
                              "Filter.by_property('prop', length=True).equal(0)"

      # Python _FilterValue
      class FilterValue < Filters
        attr_reader :value, :operator, :target

        def initialize(value:, operator:, target:)
          super()
          @value = value
          @operator = operator
          @target = target
        end

        def ==(other)
          other.is_a?(FilterValue) && other.value == value && other.operator == operator && other.target == target
        end
        alias eql? ==

        def hash = [FilterValue, value, operator, target].hash

        def to_h = { value: value, operator: operator, target: target }

        def inspect = "#<#{self.class.name} operator=#{operator} target=#{target.inspect} value=#{value.inspect}>"
      end

      # Python _FilterBase
      class FilterBase
        private

        def target_path
          return @property if @target.nil?

          target = FilterBase.deep_copy(@target)
          root = target
          target = target.target until target.target.nil?
          target.target = @property
          root
        end

        def filter_value(value, operator)
          FilterValue.new(target: target_path, value: value, operator: operator)
        end

        def check_not_empty_list(val)
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, EMPTY_LIST_FILTER_MSG if val.is_a?(Array) && val.empty?
        end

        def check_has_values(val, name)
          return unless val.respond_to?(:empty?) && val.empty?

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Filter #{name} must have at least one value"
        end

        public

        def self.deep_copy(ref)
          return ref unless ref.is_a?(SingleTargetRef) || ref.is_a?(MultiTargetRef)

          ref.with(target: deep_copy(ref.target))
        end
      end

      # Python _FilterByProperty
      class FilterByProperty < FilterBase
        def initialize(prop:, length:, target: nil)
          super()
          @target = target
          prop = "len(#{prop})" if length
          @property = prop
        end

        def is_none(val) # rubocop:disable Naming/PredicatePrefix
          filter_value(val, Operator::IS_NULL)
        end
        alias none? is_none

        def contains_any(val)
          check_has_values(val, "contains_any")
          filter_value(val, Operator::CONTAINS_ANY)
        end

        def contains_all(val)
          check_has_values(val, "contains_all")
          filter_value(val, Operator::CONTAINS_ALL)
        end

        def contains_none(val)
          check_has_values(val, "contains_none")
          filter_value(val, Operator::CONTAINS_NONE)
        end

        {
          equal: Operator::EQUAL, not_equal: Operator::NOT_EQUAL, less_than: Operator::LESS_THAN,
          less_or_equal: Operator::LESS_THAN_EQUAL, greater_than: Operator::GREATER_THAN,
          greater_or_equal: Operator::GREATER_THAN_EQUAL
        }.each do |meth, op|
          define_method(meth) do |val|
            check_not_empty_list(val)
            filter_value(val, op)
          end
        end

        def like(val)
          filter_value(val, Operator::LIKE)
        end

        def within_geo_range(coordinate, distance:)
          filter_value(
            GeoCoordinateFilter.new(latitude: coordinate.latitude, longitude: coordinate.longitude, distance: distance),
            Operator::WITHIN_GEO_RANGE
          )
        end
      end

      # Python _FilterByTime
      class FilterByTime < FilterBase
        def contains_any(dates)
          check_has_values(dates, "contains_any")
          filter_value(dates, Operator::CONTAINS_ANY)
        end

        def contains_none(dates)
          check_has_values(dates, "contains_none")
          filter_value(dates, Operator::CONTAINS_NONE)
        end

        {
          equal: Operator::EQUAL, not_equal: Operator::NOT_EQUAL, less_than: Operator::LESS_THAN,
          less_or_equal: Operator::LESS_THAN_EQUAL, greater_than: Operator::GREATER_THAN,
          greater_or_equal: Operator::GREATER_THAN_EQUAL
        }.each do |meth, op|
          define_method(meth) { |date| filter_value(date, op) }
        end
      end

      class FilterByUpdateTime < FilterByTime
        def initialize(target: nil)
          super()
          @target = target
          @property = "_lastUpdateTimeUnix"
        end
      end

      class FilterByCreationTime < FilterByTime
        def initialize(target: nil)
          super()
          @target = target
          @property = "_creationTimeUnix"
        end
      end

      # Python _FilterById
      class FilterById < FilterBase
        def initialize(target: nil)
          super()
          @target = target
          @property = "_id"
        end

        def contains_any(uuids)
          check_has_values(uuids, "contains_any")
          filter_value(uuids.map { |u| ::Weaviate::Util.get_valid_uuid(u) }, Operator::CONTAINS_ANY)
        end

        def contains_none(uuids)
          check_has_values(uuids, "contains_none")
          filter_value(uuids.map { |u| ::Weaviate::Util.get_valid_uuid(u) }, Operator::CONTAINS_NONE)
        end

        def equal(uuid)
          filter_value(::Weaviate::Util.get_valid_uuid(uuid), Operator::EQUAL)
        end

        def not_equal(uuid)
          filter_value(::Weaviate::Util.get_valid_uuid(uuid), Operator::NOT_EQUAL)
        end
      end

      # Python _FilterByCount
      class FilterByCount < FilterBase
        def initialize(link_on, target: nil)
          super()
          @target = target
          @property = CountRef.new(link_on: link_on)
        end

        {
          equal: Operator::EQUAL, not_equal: Operator::NOT_EQUAL, less_than: Operator::LESS_THAN,
          less_or_equal: Operator::LESS_THAN_EQUAL, greater_than: Operator::GREATER_THAN,
          greater_or_equal: Operator::GREATER_THAN_EQUAL
        }.each do |meth, op|
          define_method(meth) { |count| filter_value(count, op) }
        end
      end

      # Python _FilterByRef
      class FilterByRef
        def initialize(target)
          @target = target
          @last_target = target # used to append to the end of the chain
        end

        def by_ref(link_on)
          @last_target.target = SingleTargetRef.new(link_on: link_on)
          @last_target = @last_target.target
          self
        end

        def by_ref_multi_target(reference, target_collection:)
          target_collection = ::Weaviate::Util.capitalize_first_letter(target_collection)
          @last_target.target = MultiTargetRef.new(link_on: reference, target_collection: target_collection)
          @last_target = @last_target.target
          self
        end

        def by_ref_count(link_on)
          FilterByCount.new(link_on, target: @target)
        end

        def by_id
          FilterById.new(target: @target)
        end

        def by_creation_time
          FilterByCreationTime.new(target: @target)
        end

        def by_update_time
          FilterByUpdateTime.new(target: @target)
        end

        def by_property(name, length: false)
          FilterByProperty.new(prop: name, length: length, target: @target)
        end
      end

      # Port of weaviate.classes.query.Filter: the root of the filter-building chain.
      #
      #   Filter.by_property("age").greater_than(3) & Filter.by_id.equal(uuid)
      class Filter
        def initialize
          raise TypeError, "Filter cannot be instantiated. Use the static methods to create a filter."
        end

        class << self
          def by_ref(link_on)
            FilterByRef.new(SingleTargetRef.new(link_on: link_on))
          end

          def by_ref_multi_target(link_on, target_collection:)
            target_collection = ::Weaviate::Util.capitalize_first_letter(target_collection)
            FilterByRef.new(MultiTargetRef.new(link_on: link_on, target_collection: target_collection))
          end

          def by_ref_count(link_on)
            FilterByCount.new(link_on)
          end

          def by_id
            FilterById.new(target: nil)
          end

          def by_creation_time
            FilterByCreationTime.new(target: nil)
          end

          def by_update_time
            FilterByUpdateTime.new(target: nil)
          end

          def by_property(name, length: false)
            FilterByProperty.new(prop: name, length: length, target: nil)
          end

          def all_of(filters)
            return filters[0] if filters.length == 1
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Filter.all_of must have at least one filter" if filters.empty?

            FilterAnd.new(filters)
          end

          def any_of(filters)
            return filters[0] if filters.length == 1
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Filter.any_of must have at least one filter" if filters.empty?

            FilterOr.new(filters)
          end

          def not_(filter)
            FilterNot.new(filter)
          end
          alias_method :not, :not_
        end
      end

      # Python type aliases for the return classes
      FilterReturn = Filters
    end
  end
end
