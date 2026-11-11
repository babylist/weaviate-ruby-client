# frozen_string_literal: true

require "json"
require_relative "../grpc/shared"
require_relative "gql_builder"

module Weaviate
  module Collections
    module Aggregate
      # Port of weaviate.collections.grpc.aggregate._AggregateGRPC
      class AggregateGRPC < ::Weaviate::Collections::Grpc::BaseGRPC
        VECTOR_SEARCH_ARGS_MSG = "You must provide at least one of the following arguments: certainty, distance, " \
                                 "object_limit when vector searching"

        def initialize(weaviate_version:, name:, tenant:, consistency_level:, validate_arguments:)
          super(weaviate_version: weaviate_version, consistency_level: consistency_level,
                validate_arguments: validate_arguments)
          @name = name
          @tenant = tenant
        end

        def objects_count_request = create_request(objects_count: true)

        def hybrid(query:, alpha:, vector:, properties:, distance:, target_vector:, bm25_operator:, **common)
          create_request(hybrid: parse_hybrid(query, alpha, vector, properties, bm25_operator, nil, distance,
                                              target_vector), **common)
        end

        def near_media(media:, type_:, certainty:, distance:, target_vector:, **common)
          check_vector_search_args(certainty, distance, common[:object_limit])
          create_request(**parse_media(media, type_, certainty, distance, target_vector), **common)
        end

        def near_object(near_object:, certainty:, distance:, target_vector:, **common)
          check_vector_search_args(certainty, distance, common[:object_limit])
          create_request(near_object: parse_near_object(near_object, certainty, distance, target_vector), **common)
        end

        def near_text(near_text:, certainty:, distance:, move_to:, move_away:, target_vector:, **common)
          check_vector_search_args(certainty, distance, common[:object_limit])
          create_request(near_text: parse_near_text(near_text, certainty, distance, move_to, move_away, target_vector),
                         **common)
        end

        def near_vector(near_vector:, certainty:, distance:, target_vector:, **common)
          check_vector_search_args(certainty, distance, common[:object_limit])
          create_request(near_vector: parse_near_vector(near_vector, certainty, distance, target_vector), **common)
        end

        def over_all(**common)
          create_request(**common)
        end

        private

        def check_vector_search_args(certainty, distance, object_limit)
          return unless @validate_arguments && certainty.nil? && distance.nil? && object_limit.nil?

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, VECTOR_SEARCH_ARGS_MSG
        end

        def create_request(aggregations: [], filters: nil, group_by: nil, limit: nil, object_limit: nil,
                           objects_count: false, **search)
          fields = { collection: @name, aggregations: aggregations, filters: filters, group_by: group_by,
                     limit: limit, object_limit: object_limit, objects_count: objects_count, tenant: @tenant,
                     **search }
          ::Weaviate::V1::AggregateRequest.new(**fields.compact)
        end
      end

      # Port of weaviate.collections.aggregate._AggregateCollection (collection.aggregate):
      # over_all, hybrid, near_image, near_object, near_text, near_vector.
      class AggregateCollection
        Grpc = ::Weaviate::Collections::Grpc
        Out = ::Weaviate::Outputs::Aggregate
        Agg = ::Weaviate::Classes::Aggregate

        def initialize(connection:, name:, consistency_level: nil, tenant: nil, validate_arguments: true)
          @connection = connection
          @name = name
          @tenant = tenant
          @consistency_level = consistency_level
          @validate_arguments = validate_arguments
        end

        def inspect = "#<#{self.class.name} name=#{@name.inspect} tenant=#{@tenant.inspect}>"

        def over_all(filters: nil, group_by: nil, total_count: true, return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            builder = base(return_metrics, filters, total_count)
            builder = add_groupby(builder, group_by)
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.over_all(**common_grpc(return_metrics, filters, group_by, total_count))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        def hybrid(query, alpha: nil, vector: nil, query_properties: nil, object_limit: nil, bm25_operator: nil,
                   filters: nil, group_by: nil, target_vector: nil, max_vector_distance: nil, total_count: true,
                   return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            builder = base(return_metrics, filters, total_count)
            payload = { "query" => query, "alpha" => alpha, "vector" => vector, "properties" => query_properties,
                        "targetVectors" => target_vector.nil? ? nil : [target_vector],
                        "maxVectorDistance" => max_vector_distance }.compact
            builder = builder.with_hybrid(payload)
            builder = builder.with_object_limit(object_limit) unless object_limit.nil?
            builder = add_groupby(builder, group_by)
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.hybrid(query: query, alpha: alpha, vector: vector, properties: query_properties,
                                distance: max_vector_distance, target_vector: target_vector,
                                bm25_operator: bm25_operator,
                                **common_grpc(return_metrics, filters, group_by, total_count, object_limit))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        def near_image(near_image, certainty: nil, distance: nil, object_limit: nil, filters: nil, group_by: nil,
                       target_vector: nil, total_count: true, return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            unless near_image.is_a?(String) || near_image.is_a?(IO) || near_image.is_a?(StringIO) ||
                   (defined?(Pathname) && near_image.is_a?(Pathname))
              Grpc::Validator.validate_input(Grpc::Validator.arg([String, IO], "near_image", near_image))
            end
            check_near_args(certainty, distance, object_limit)
            builder = base(return_metrics, filters, total_count)
            builder = add_groupby(builder, group_by)
            payload = { "image" => Util.parse_blob(near_image), "certainty" => certainty, "distance" => distance,
                        "targetVector" => target_vector }.compact
            builder = builder.with_near_image(payload)
            builder = builder.with_object_limit(object_limit) unless object_limit.nil?
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.near_media(media: Util.parse_blob(near_image), type_: "image", certainty: certainty,
                                    distance: distance, target_vector: target_vector,
                                    **common_grpc(return_metrics, filters, group_by, total_count, object_limit))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        def near_object(near_object, certainty: nil, distance: nil, object_limit: nil, filters: nil, group_by: nil,
                        target_vector: nil, total_count: true, return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            check_near_args(certainty, distance, object_limit)
            Grpc::Validator.validate_input(Grpc::Validator.arg([String], "near_object", near_object))
            builder = base(return_metrics, filters, total_count)
            builder = add_groupby(builder, group_by)
            payload = { "id" => near_object.to_s, "certainty" => certainty, "distance" => distance,
                        "targetVector" => target_vector }.compact
            builder = builder.with_near_object(payload)
            builder = builder.with_object_limit(object_limit) unless object_limit.nil?
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.near_object(near_object: near_object, certainty: certainty, distance: distance,
                                     target_vector: target_vector,
                                     **common_grpc(return_metrics, filters, group_by, total_count, object_limit))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        def near_text(query, certainty: nil, distance: nil, move_to: nil, move_away: nil, object_limit: nil,
                      filters: nil, group_by: nil, target_vector: nil, total_count: true, return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            if !target_vector.nil? && !target_vector.is_a?(String)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "A `target_vector` argument other than a string is not supported in <v1.28.4"
            end
            move = ::Weaviate::Classes::Query::Move
            Grpc::Validator.validate_input([
                                             Grpc::Validator.arg([[:list_of, String], String], "query", query),
                                             Grpc::Validator.arg([move, nil], "move_to", move_to),
                                             Grpc::Validator.arg([move, nil], "move_away", move_away)
                                           ])
            check_near_args(certainty, distance, object_limit)
            builder = base(return_metrics, filters, total_count)
            builder = add_groupby(builder, group_by)
            payload = { "concepts" => query.is_a?(Array) ? query : [query], "certainty" => certainty,
                        "distance" => distance, "moveTo" => move_to&.to_gql_payload,
                        "moveAwayFrom" => move_away&.to_gql_payload, "targetVector" => target_vector }.compact
            builder = builder.with_near_text(payload)
            builder = builder.with_object_limit(object_limit) unless object_limit.nil?
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.near_text(near_text: query, certainty: certainty, distance: distance, move_to: move_to,
                                   move_away: move_away, target_vector: target_vector,
                                   **common_grpc(return_metrics, filters, group_by, total_count, object_limit))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        def near_vector(near_vector, certainty: nil, distance: nil, object_limit: nil, filters: nil, group_by: nil,
                        target_vector: nil, total_count: true, return_metrics: nil)
          return_metrics, group_by = normalize(return_metrics, group_by)
          if gql?
            unless near_vector.is_a?(Array) && !near_vector.first.is_a?(Array)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "A `near_vector` argument other than a list of floats is not supported in <v1.28.4"
            end
            if !target_vector.nil? && !target_vector.is_a?(String)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "A `target_vector` argument other than a string is not supported in <v1.28.4"
            end
            check_near_args(certainty, distance, object_limit)
            builder = base(return_metrics, filters, total_count)
            builder = add_groupby(builder, group_by)
            payload = { "vector" => near_vector, "certainty" => certainty, "distance" => distance,
                        "targetVector" => target_vector }.compact
            builder = builder.with_near_vector(payload)
            builder = builder.with_object_limit(object_limit) unless object_limit.nil?
            return gql_result(do_gql(builder), return_metrics, group_by)
          end

          request = grpc.near_vector(near_vector: near_vector, certainty: certainty, distance: distance,
                                     target_vector: target_vector,
                                     **common_grpc(return_metrics, filters, group_by, total_count, object_limit))
          to_result(!group_by.nil?, @connection.grpc_aggregate(request))
        end

        private

        def gql?
          @connection.weaviate_version.is_lower_than(1, 29, 0)
        end

        def grpc
          AggregateGRPC.new(weaviate_version: @connection.weaviate_version, name: @name, tenant: @tenant,
                            consistency_level: @consistency_level, validate_arguments: @validate_arguments)
        end

        def normalize(return_metrics, group_by)
          return_metrics = [return_metrics] unless return_metrics.nil? || return_metrics.is_a?(Array)
          group_by = Agg::GroupByAggregate.new(prop: group_by) if group_by.is_a?(String)
          [return_metrics, group_by]
        end

        def common_grpc(return_metrics, filters, group_by, total_count, object_limit = nil)
          {
            aggregations: return_metrics.nil? ? [] : return_metrics.map(&:to_grpc),
            filters: filters.nil? ? nil : Grpc::FilterToGRPC.convert(filters),
            group_by: group_by&.to_grpc,
            limit: group_by&.limit,
            objects_count: total_count,
            object_limit: object_limit
          }
        end

        # --- gRPC result parsing ---------------------------------------------

        def to_result(is_groupby, response)
          unless is_groupby
            return Out::AggregateReturn.new(
              properties: response.single_result.aggregations&.aggregations.to_a
                                  .to_h { |a| [a.property, parse_property_grpc(a)] },
              total_count: response.single_result.objects_count
            )
          end

          Out::AggregateGroupByReturn.new(
            # An unset proto message is nil in Ruby (Python returns an empty default), e.g. no groups found.
            groups: response.grouped_results&.groups.to_a.map do |group|
              Out::AggregateGroup.new(
                grouped_by: parse_grouped_by_value(group.grouped_by),
                properties: group.aggregations&.aggregations.to_a.to_h { |a| [a.property, parse_property_grpc(a)] },
                total_count: group.objects_count
              )
            end
          )
        end

        def parse_grouped_by_value(grouped_by)
          value =
            case grouped_by.value
            when :text then grouped_by.text
            when :int then grouped_by.int
            when :number then grouped_by.number
            when :boolean then grouped_by.boolean
            when :texts then grouped_by.texts.values.to_a
            when :ints then grouped_by.ints.values.to_a
            when :numbers then grouped_by.numbers.values.to_a
            when :booleans then grouped_by.booleans.values.to_a
            when :geo
              ::Weaviate::Classes::Data::GeoCoordinate.new(latitude: grouped_by.geo.latitude,
                                                           longitude: grouped_by.geo.longitude)
            else
              ::Weaviate::Warnings.unknown_type_encountered(grouped_by.value)
              nil
            end
          Out::GroupedBy.new(prop: grouped_by.path[0], value: value)
        end

        def opt(msg, field)
          msg.public_send(:"has_#{field}?") ? msg.public_send(field) : nil
        end

        def parse_property_grpc(aggregation)
          case aggregation.aggregation
          when :text
            t = aggregation.text
            Out::AggregateText.new(
              count: t.count,
              top_occurrences: t.top_occurences&.items.to_a.map { |o| Out::TopOccurrence.new(count: o.occurs, value: o.value) }
            )
          when :int
            i = aggregation.int
            Out::AggregateInteger.new(count: i.count, maximum: opt(i, :maximum), mean: opt(i, :mean),
                                      median: opt(i, :median), minimum: opt(i, :minimum), mode: opt(i, :mode),
                                      sum_: opt(i, :sum))
          when :number
            n = aggregation.number
            Out::AggregateNumber.new(count: n.count, maximum: opt(n, :maximum), mean: opt(n, :mean),
                                     median: opt(n, :median), minimum: opt(n, :minimum), mode: opt(n, :mode),
                                     sum_: opt(n, :sum))
          when :boolean
            b = aggregation.boolean
            Out::AggregateBoolean.new(count: b.count, percentage_false: opt(b, :percentage_false),
                                      percentage_true: opt(b, :percentage_true), total_false: opt(b, :total_false),
                                      total_true: opt(b, :total_true))
          when :date
            d = aggregation.date
            Out::AggregateDate.new(count: d.count, maximum: opt(d, :maximum), median: opt(d, :median),
                                   minimum: opt(d, :minimum), mode: opt(d, :mode))
          when :reference
            Out::AggregateReference.new(pointing_to: aggregation.reference.pointing_to.to_a)
          else
            raise ArgumentError, "Unknown aggregation type #{aggregation.inspect} encountered in " \
                                 "_Aggregate.__parse_property_grpc()"
          end
        end

        # --- GraphQL (Weaviate < 1.29) ---------------------------------------

        def check_near_args(certainty, distance, object_limit)
          Grpc::Validator.validate_input([
                                           Grpc::Validator.arg([Integer, Float, nil], "certainty", certainty),
                                           Grpc::Validator.arg([Integer, Float, nil], "distance", distance),
                                           Grpc::Validator.arg([Integer, nil], "object_limit", object_limit)
                                         ])
          return unless certainty.nil? && distance.nil? && object_limit.nil?

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, AggregateGRPC::VECTOR_SEARCH_ARGS_MSG
        end

        METRIC_CLASSES = [Agg::MetricsText, Agg::MetricsInteger, Agg::MetricsNumber, Agg::MetricsDate,
                          Agg::MetricsBoolean, Agg::MetricsReference].freeze

        def base(return_metrics, filters, total_count)
          Grpc::Validator.validate_input([
                                           Grpc::Validator.arg([[:list_of, *METRIC_CLASSES], nil], "return_metrics",
                                                               return_metrics),
                                           Grpc::Validator.arg([::Weaviate::Classes::Query::Filters, nil], "filters",
                                                               filters),
                                           Grpc::Validator.arg([:bool], "total_count", total_count)
                                         ])
          builder = GQLBuilder.new(@name)
          builder = builder.with_fields(return_metrics.map(&:to_gql).join(" ")) unless return_metrics.nil?
          builder = builder.with_where(Grpc::FilterToREST.convert(filters)) unless filters.nil?
          builder = builder.with_meta_count if total_count
          builder = builder.with_tenant(@tenant) unless @tenant.nil?
          builder
        end

        def add_groupby(builder, group_by)
          Grpc::Validator.validate_input(Grpc::Validator.arg([String, Agg::GroupByAggregate, nil], "group_by", group_by))
          return builder if group_by.nil?

          builder = builder.with_group_by_filter([group_by.prop])
          builder = builder.with_limit(group_by.limit) unless group_by.limit.nil?
          builder.with_fields(" groupedBy { path value } ")
        end

        def do_gql(builder)
          res = @connection.post("/graphql", weaviate_object: { "query" => builder.build }, is_gql_query: true)
          data = Util.decode_json_response_dict(res, "Query was not successful")
          errs = data["errors"]
          return data if errs.nil?

          if errs[0]["message"].to_s.include?("Unexpected empty IN")
            raise ::Weaviate::Exceptions::WeaviateQueryError.new(
              "The query that you sent had no body so GraphQL was unable to parse it. You must provide at least " \
              "one option to the aggregation method in order to build a valid query.", "GQL Aggregate"
            )
          end
          raise ::Weaviate::Exceptions::WeaviateQueryError.new(
            "Error in GraphQL response: #{JSON.pretty_generate(errs)}, for the following query: #{builder.build}",
            "GQL Aggregate"
          )
        end

        def gql_result(response, return_metrics, group_by)
          results = response.dig("data", "Aggregate", @name)
          raise ArgumentError, "There was an error parsing the GraphQL response: #{response}" if results.nil?

          if group_by.nil?
            result = results[0]
            return Out::AggregateReturn.new(
              properties: return_metrics.nil? ? {} : parse_properties(result, return_metrics),
              total_count: result["meta"]&.fetch("count")
            )
          end

          Out::AggregateGroupByReturn.new(
            groups: results.map do |result|
              Out::AggregateGroup.new(
                grouped_by: Out::GroupedBy.new(prop: result["groupedBy"]["path"][0],
                                               value: result["groupedBy"]["value"]),
                properties: return_metrics.nil? ? {} : parse_properties(result, return_metrics),
                total_count: result["meta"]&.fetch("count")
              )
            end
          )
        end

        def parse_properties(result, metrics)
          metrics.each_with_object({}) do |metric, props|
            next unless result.key?(metric.property_name)

            props[metric.property_name] = parse_property_gql(result[metric.property_name], metric)
          end
        end

        def parse_property_gql(prop, metric)
          case metric
          when Agg::MetricsText
            Out::AggregateText.new(
              count: prop["count"],
              top_occurrences: Array(prop["topOccurrences"]).map { |o| Out::TopOccurrence.new(count: o["occurs"], value: o["value"]) }
            )
          when Agg::MetricsInteger, Agg::MetricsNumber
            klass = metric.is_a?(Agg::MetricsInteger) ? Out::AggregateInteger : Out::AggregateNumber
            klass.new(count: prop["count"], maximum: prop["maximum"], mean: prop["mean"], median: prop["median"],
                      minimum: prop["minimum"], mode: prop["mode"], sum_: prop["sum"])
          when Agg::MetricsBoolean
            Out::AggregateBoolean.new(count: prop["count"], percentage_false: prop["percentageFalse"],
                                      percentage_true: prop["percentageTrue"], total_false: prop["totalFalse"],
                                      total_true: prop["totalTrue"])
          when Agg::MetricsDate
            Out::AggregateDate.new(count: prop["count"], maximum: prop["maximum"], median: prop["median"],
                                   minimum: prop["minimum"], mode: prop["mode"])
          when Agg::MetricsReference
            Out::AggregateReference.new(pointing_to: prop["pointingTo"])
          else
            raise ArgumentError, "Unknown aggregation type #{metric} encountered for property #{prop}"
          end
        end
      end
    end
  end
end
