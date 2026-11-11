# frozen_string_literal: true

require "json"

module Weaviate
  module Collections
    module Aggregate
      # Port of weaviate.gql.aggregate.AggregateBuilder and the pieces of
      # weaviate.gql.filter it renders. Only used for Weaviate < 1.29, where
      # aggregations go through GraphQL instead of gRPC.
      class GQLBuilder
        NUMERIC_TYPES = %w[valueInt valueNumber valueIntArray valueNumberArray valueIntList valueNumberList].freeze
        TEXT_TYPES = %w[valueText valueString valueTextList valueStringList valueTextArray valueStringArray].freeze
        BOOL_TYPES = %w[valueBoolean valueBooleanArray valueBooleanList].freeze
        VALUE_TYPES = (NUMERIC_TYPES + TEXT_TYPES + BOOL_TYPES +
                       %w[valueDate valueDateArray valueDateList valueGeoRange]).freeze

        def initialize(class_name)
          @class_name = Util.capitalize_first_letter(class_name)
          @fields = []
          @uses_filter = false
          @with_meta_count = false
        end

        def with_tenant(tenant)
          raise TypeError, "tenant must be of type str" unless tenant.is_a?(String)

          @tenant = tenant
          @uses_filter = true
          self
        end

        def with_meta_count
          @with_meta_count = true
          self
        end

        def with_object_limit(limit)
          @object_limit = limit
          self
        end

        def with_limit(limit)
          @limit = limit
          self
        end

        def with_fields(field)
          @fields << field
          self
        end

        def with_where(content)
          @where = render_where(content)
          @uses_filter = true
          self
        end

        def with_group_by_filter(properties)
          @group_by_properties = properties
          @uses_filter = true
          self
        end

        def with_hybrid(content)
          raise ArgumentError, "Cannot use 'hybrid' and 'near' filters simultaneously." unless @near.nil?

          @hybrid = render_hybrid(content)
          @uses_filter = true
          self
        end

        def with_near_text(content)
          set_near(render_near_text(content))
        end

        def with_near_vector(content)
          vector = content.fetch("vector")
          set_near("nearVector: {vector: #{JSON.generate(vector)}#{near_suffix(content)}} ")
        end

        def with_near_object(content)
          key = content.key?("id") ? "id" : "beacon"
          set_near("nearObject: {#{key}: \"#{content[key]}\"#{near_suffix(content)}} ")
        end

        def with_near_image(content)
          set_near("nearImage: {image: \"#{content.fetch("image")}\"#{near_suffix(content)}} ")
        end

        def build
          query = +"{Aggregate{#{@class_name}"
          if @uses_filter
            query << "("
            query << @where if @where
            query << "groupBy: #{JSON.generate(@group_by_properties)}" if @group_by_properties
            query << @near if @near
            query << "objectLimit: #{@object_limit}" if @object_limit && @object_limit != 0
            query << "tenant: \"#{@tenant}\"" if @tenant
            query << "limit: #{@limit}" unless @limit.nil?
            query << @hybrid if @hybrid
            query << ")"
          end
          query << "{"
          query << "meta{count}" if @with_meta_count
          @fields.each { |f| query << f }
          query << "}}}"
          query
        end

        private

        def set_near(rendered)
          raise ArgumentError, "Cannot use multiple 'near' filters." unless @near.nil?
          raise ArgumentError, "Cannot use 'near' and 'hybrid' filters simultaneously." unless @hybrid.nil?

          @near = rendered
          @uses_filter = true
          self
        end

        def near_suffix(content)
          out = +""
          out << " certainty: #{py_num(content["certainty"])}" if content.key?("certainty")
          out << " distance: #{py_num(content["distance"])}" if content.key?("distance")
          out << " targetVectors: \"#{content["targetVector"]}\"" if content.key?("targetVector")
          out
        end

        def render_near_text(content)
          concepts = content.fetch("concepts")
          concepts = [concepts] if concepts.is_a?(String)
          out = +"nearText: {concepts: #{JSON.generate(concepts)}"
          out << " certainty: #{py_num(content["certainty"])}" if content.key?("certainty")
          out << " distance: #{py_num(content["distance"])}" if content.key?("distance")
          { "moveTo" => "moveTo", "moveAwayFrom" => "moveAwayFrom" }.each do |key, label|
            next unless content.key?(key)

            move = content[key]
            out << " #{label}: {force: #{py_num(move["force"])}"
            out << " concepts: #{JSON.generate(Array(move["concepts"]))}" if move.key?("concepts")
            if move.key?("objects")
              out << " objects: ["
              Array(move["objects"]).each do |obj|
                k = obj.key?("id") ? "id" : "beacon"
                out << "{#{k}: #{JSON.generate(obj[k])}} "
              end
              out << "]"
            end
            out << "}"
          end
          out << " targetVectors: \"#{content["targetVector"]}\"" if content.key?("targetVector")
          "#{out}} "
        end

        def render_hybrid(content)
          out = +""
          out << "query: #{Util.sanitize_str(content["query"])}" unless content["query"].nil?
          out << ", vector: #{py_list(content["vector"])}" unless content["vector"].nil?
          out << ", alpha: #{py_num(content["alpha"])}" unless content["alpha"].nil?
          props = content["properties"]
          out << ", properties: [\"#{props.join('","')}\"]" if props && !props.empty?
          out << ", targetVectors: [\"#{content["targetVectors"].join('","')}\"]" unless content["targetVectors"].nil?
          out << ", maxVectorDistance:#{py_num(content["maxVectorDistance"])}" unless content["maxVectorDistance"].nil?
          "hybrid:{#{out}}"
        end

        def render_where(content)
          "where: #{render_where_body(content)} "
        end

        def render_where_body(content)
          if content.key?("operands")
            operands = content["operands"].map { |op| render_where_body(op) }.join(", ")
            return "{operator: #{content.fetch("operator")} operands: [#{operands}]}"
          end

          value_type = (content.keys & VALUE_TYPES)
          raise ArgumentError, "'value<TYPE>' field is either missing or incorrect: #{content}" if value_type.empty?
          raise ArgumentError, "Multiple fields 'value<TYPE>' are not supported: #{content}" if value_type.length > 1

          value_type = value_type.first
          value = content[value_type]
          gql = +"{path: #{JSON.generate(content.fetch("path"))} operator: #{content.fetch("operator")} " \
                 "#{convert_value_type(value_type)}: "
          gql << render_value(value_type, value)
          "#{gql}}"
        end

        def render_value(value_type, value)
          if NUMERIC_TYPES.include?(value_type)
            value.is_a?(Array) ? py_list(value) : py_num(value).to_s
          elsif TEXT_TYPES.include?(value_type)
            value.is_a?(Array) ? "[#{value.map { |v| Util.sanitize_str(v) }.join(",")}]" : Util.sanitize_str(value)
          elsif BOOL_TYPES.include?(value_type)
            value.is_a?(Array) ? "[#{value.map(&:to_s).join(",")}]" : value.to_s
          elsif %w[valueDateArray valueDateList].include?(value_type)
            "[#{value.map { |v| "\"#{v}\"" }.join(",")}]"
          elsif value_type == "valueGeoRange"
            geo = value["geoCoordinates"]
            "{ geoCoordinates: { latitude: #{geo["latitude"]} longitude: #{geo["longitude"]} } " \
              "distance: { max: #{value["distance"]["max"]} }}"
          else
            "\"#{value}\""
          end
        end

        def convert_value_type(type)
          type.sub(/(Array|List)\z/, "")
        end

        # Python renders numbers via str(): 1.0 stays "1.0", ints stay ints.
        def py_num(value) = value

        def py_list(values) = "[#{values.map { |v| v.is_a?(Array) ? py_list(v) : v }.join(", ")}]"
      end
    end
  end
end
