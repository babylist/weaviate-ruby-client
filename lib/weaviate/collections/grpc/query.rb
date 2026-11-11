# frozen_string_literal: true

require_relative "shared"

module Weaviate
  module Collections
    module Grpc
      # Port of weaviate.collections.grpc.query._QueryGRPC: builds Weaviate::V1::SearchRequest messages.
      class QueryGRPC < BaseGRPC
        CURVE_TO_PROTO = {
          ::Weaviate::Classes::Query::BoostCurve::EXPONENTIAL => :DECAY_CURVE_EXPONENTIAL,
          ::Weaviate::Classes::Query::BoostCurve::GAUSSIAN => :DECAY_CURVE_GAUSS,
          ::Weaviate::Classes::Query::BoostCurve::LINEAR => :DECAY_CURVE_LINEAR
        }.freeze

        MODIFIER_TO_PROTO = {
          ::Weaviate::Classes::Query::BoostModifier::LOG1P => :PROPERTY_VALUE_MODIFIER_LOG1P,
          ::Weaviate::Classes::Query::BoostModifier::SQRT => :PROPERTY_VALUE_MODIFIER_SQRT
        }.freeze

        attr_reader :name, :tenant

        def initialize(weaviate_version:, name:, tenant:, consistency_level:, validate_arguments:, uses_125_api:,
                       uses_127_api:)
          super(weaviate_version: weaviate_version, consistency_level: consistency_level,
                validate_arguments: validate_arguments)
          @name = name
          @tenant = tenant
          @uses_125_api = uses_125_api
          @uses_127_api = uses_127_api
        end

        def get(limit: nil, offset: nil, after: nil, filters: nil, sort: nil, return_metadata: nil,
                return_properties: nil, return_references: nil, generative: nil, rerank: nil, boost: nil)
          Validator.validate_input(Validator.arg([Q::Sorting, nil], "sort", sort)) if @validate_arguments

          sort_by = sort&.sorts&.map { |s| ::Weaviate::V1::SortBy.new(ascending: s.ascending, path: [s.prop]) }
          create_request(after: after, limit: limit, offset: offset, filters: filters, metadata: return_metadata,
                         return_properties: return_properties, return_references: return_references,
                         generative: generative, rerank: rerank, boost: boost, sort_by: sort_by)
        end

        def hybrid(query:, alpha: nil, vector: nil, properties: nil, fusion_type: nil, distance: nil, limit: nil,
                   offset: nil, bm25_operator: nil, autocut: nil, filters: nil, group_by: nil, return_metadata: nil,
                   return_properties: nil, return_references: nil, generative: nil, rerank: nil, boost: nil,
                   diversity_selection: nil, target_vector: nil)
          create_request(
            limit: limit, offset: offset, filters: filters, group_by: group_by, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut,
            hybrid_search: parse_hybrid(query, alpha, vector, properties, bm25_operator, fusion_type, distance,
                                        target_vector, diversity_selection)
          )
        end

        def bm25(query:, properties: nil, limit: nil, offset: nil, operator: nil, autocut: nil, filters: nil,
                 group_by: nil, return_metadata: nil, return_properties: nil, return_references: nil,
                 generative: nil, rerank: nil, boost: nil)
          if @validate_arguments
            Validator.validate_input([Validator.arg([nil, String], "query", query),
                                      Validator.arg([:list, nil], "properties", properties)])
          end

          bm25 = if query.nil?
                   nil
                 else
                   ::Weaviate::V1::BM25.new(query: query, properties: properties.nil? ? [] : properties.to_a,
                                            search_operator: bm25_operator_to_grpc(operator))
                 end
          create_request(
            limit: limit, offset: offset, filters: filters, group_by: group_by, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut, bm25: bm25
          )
        end

        def near_vector(near_vector:, certainty: nil, distance: nil, limit: nil, offset: nil, autocut: nil,
                        filters: nil, group_by: nil, generative: nil, rerank: nil, boost: nil, target_vector: nil,
                        return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          create_request(
            limit: limit, offset: offset, filters: filters, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut, group_by: group_by,
            near_vector: parse_near_vector(near_vector, certainty, distance, target_vector, diversity_selection)
          )
        end

        def near_object(near_object:, certainty: nil, distance: nil, limit: nil, offset: nil, autocut: nil,
                        filters: nil, group_by: nil, generative: nil, rerank: nil, boost: nil, target_vector: nil,
                        return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          create_request(
            limit: limit, offset: offset, filters: filters, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut, group_by: group_by,
            near_object: parse_near_object(near_object, certainty, distance, target_vector, diversity_selection)
          )
        end

        def near_text(near_text:, certainty: nil, distance: nil, move_to: nil, move_away: nil, limit: nil,
                      offset: nil, autocut: nil, filters: nil, group_by: nil, generative: nil, rerank: nil,
                      boost: nil, target_vector: nil, return_metadata: nil, return_properties: nil,
                      return_references: nil, diversity_selection: nil)
          create_request(
            limit: limit, offset: offset, filters: filters, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut, group_by: group_by,
            near_text: parse_near_text(near_text, certainty, distance, move_to, move_away, target_vector,
                                       diversity_selection)
          )
        end

        def near_media(media:, type_:, certainty: nil, distance: nil, limit: nil, offset: nil, autocut: nil,
                       filters: nil, group_by: nil, generative: nil, rerank: nil, boost: nil, target_vector: nil,
                       return_metadata: nil, return_properties: nil, return_references: nil,
                       diversity_selection: nil)
          create_request(
            limit: limit, offset: offset, filters: filters, metadata: return_metadata,
            return_properties: return_properties, return_references: return_references, generative: generative,
            rerank: rerank, boost: boost, autocut: autocut, group_by: group_by,
            **parse_media(media, type_, certainty, distance, target_vector, diversity_selection)
          )
        end

        # MetadataQueryInternal -> Weaviate::V1::MetadataRequest
        def metadata_to_grpc(metadata)
          ::Weaviate::V1::MetadataRequest.new(
            uuid: metadata.uuid, vector: metadata.vector, creation_time_unix: metadata.creation_time_unix,
            last_update_time_unix: metadata.last_update_time_unix, distance: metadata.distance,
            certainty: metadata.certainty, explain_score: metadata.explain_score, score: metadata.score,
            is_consistent: metadata.is_consistent, vectors: metadata.vectors&.map(&:to_s),
            query_profile: metadata.query_profile
          )
        end

        def translate_properties_from_python_to_grpc(properties, references)
          return nil if properties.nil? && references.nil?

          ::Weaviate::V1::PropertiesRequest.new(
            return_all_nonref_properties: properties.nil?,
            non_ref_properties: properties&.select { |p| p.is_a?(String) || p.is_a?(Symbol) }&.map(&:to_s),
            ref_properties: references&.map { |ref| ref_properties_request(ref) },
            object_properties: properties&.select { |p| p.is_a?(Q::QueryNested) }&.map { |p| resolve_property(p) }
          )
        end

        private

        def create_request(limit: nil, offset: nil, after: nil, filters: nil, metadata: nil, return_properties: nil,
                           return_references: nil, generative: nil, rerank: nil, boost: nil, autocut: nil,
                           group_by: nil, sort_by: nil, **search)
          validate_request(limit, offset, after, filters, metadata, generative, rerank, autocut, group_by,
                           return_properties, return_references)

          references_parsed = return_references.nil? ? nil : convert_to_set(return_references)
          properties_parsed = parse_return_properties(return_properties)

          ::Weaviate::V1::SearchRequest.new(
            uses_123_api: true,
            uses_125_api: @uses_125_api,
            uses_127_api: @uses_127_api,
            collection: @name,
            limit: limit,
            offset: offset,
            after: after.nil? ? "" : after.to_s,
            autocut: autocut,
            properties: translate_properties_from_python_to_grpc(properties_parsed, references_parsed),
            metadata: metadata.nil? ? nil : metadata_to_grpc(metadata),
            consistency_level: @consistency_level,
            tenant: @tenant,
            filters: FilterToGRPC.convert(filters),
            generative: generative&.to_grpc(@weaviate_version),
            group_by: group_by&.to_grpc,
            rerank: rerank.nil? ? nil : ::Weaviate::V1::Rerank.new(property: rerank.prop, query: rerank.query),
            boost: boost_to_grpc(boost),
            sort_by: sort_by,
            near_vector: search[:near_vector],
            hybrid_search: search[:hybrid_search],
            bm25_search: search[:bm25],
            near_object: search[:near_object],
            near_text: search[:near_text],
            near_audio: search[:near_audio],
            near_depth: search[:near_depth],
            near_image: search[:near_image],
            near_imu: search[:near_imu],
            near_thermal: search[:near_thermal],
            near_video: search[:near_video]
          )
        end

        def validate_request(limit, offset, after, filters, metadata, generative, rerank, autocut, group_by,
                             return_properties, return_references)
          return unless @validate_arguments

          Validator.validate_input([
                                     Validator.arg([Integer, nil], "limit", limit),
                                     Validator.arg([Integer, nil], "offset", offset),
                                     Validator.arg([String, nil], "after", after),
                                     Validator.arg([Q::Filters, nil], "filters", filters),
                                     Validator.arg([Q::MetadataQueryInternal, nil], "metadata", metadata),
                                     Validator.arg([Generative, nil], "generative", generative),
                                     Validator.arg([Q::Rerank, nil], "rerank", rerank),
                                     Validator.arg([Integer, nil], "autocut", autocut),
                                     Validator.arg([GroupByRequest, nil], "group_by", group_by),
                                     Validator.arg([String, Symbol, :bool, Q::QueryNested, Array, nil],
                                                   "return_properties", return_properties),
                                     Validator.arg([Q::QueryReferenceBase, Array, nil],
                                                   "return_references", return_references)
                                   ])
          if return_properties.is_a?(Array)
            return_properties.each do |prop|
              Validator.validate_input(Validator.arg([String, Symbol, Q::QueryNested], "return_properties", prop))
            end
          end
          return unless return_references.is_a?(Array)

          return_references.each do |ref|
            Validator.validate_input(Validator.arg([Q::QueryReferenceBase], "return_references", ref))
          end
        end

        def boost_to_grpc(boost)
          return nil if boost.nil?

          b = ::Weaviate::V1::Boost
          conditions = boost.conditions.map do |cond|
            fields = { weight: cond.weight&.to_f }
            if !cond.filter.nil?
              fields[:filter] = FilterToGRPC.convert(cond.filter)
            elsif !cond.time_decay.nil?
              td = cond.time_decay
              fields[:time_decay] = b::TimeDecayFunction.new(
                property: td.property, origin: td.origin, scale: td.scale, offset: td.offset,
                curve: td.curve.nil? ? :DECAY_CURVE_UNSPECIFIED : CURVE_TO_PROTO.fetch(td.curve),
                decay_value: td.decay_value&.to_f
              )
            elsif !cond.numeric_decay.nil?
              nd = cond.numeric_decay
              fields[:numeric_decay] = b::NumericDecayFunction.new(
                property: nd.property, origin: nd.origin, scale: nd.scale, offset: nd.offset,
                curve: nd.curve.nil? ? :DECAY_CURVE_UNSPECIFIED : CURVE_TO_PROTO.fetch(nd.curve),
                decay_value: nd.decay_value&.to_f
              )
            elsif !cond.property_value.nil?
              pv = cond.property_value
              fields[:property_value] = b::PropertyValueFunction.new(
                property: pv.property,
                modifier: pv.modifier.nil? ? :PROPERTY_VALUE_MODIFIER_UNSPECIFIED : MODIFIER_TO_PROTO.fetch(pv.modifier)
              )
            end
            b::Condition.new(**fields)
          end
          b.new(conditions: conditions, weight: boost.weight&.to_f, depth: boost.depth)
        end

        def resolve_property(prop)
          props = prop.properties.is_a?(Array) ? prop.properties : [prop.properties]
          ::Weaviate::V1::ObjectPropertiesRequest.new(
            prop_name: prop.name,
            primitive_properties: props.select { |p| p.is_a?(String) || p.is_a?(Symbol) }.map(&:to_s),
            object_properties: props.select { |p| p.is_a?(Q::QueryNested) }.map { |p| resolve_property(p) }
          )
        end

        def ref_properties_request(ref)
          ::Weaviate::V1::RefPropertiesRequest.new(
            reference_property: ref.link_on,
            properties: translate_properties_from_python_to_grpc(
              parse_return_properties(ref.return_properties),
              ref.return_references.nil? ? nil : convert_to_set(ref.return_references)
            ),
            metadata: metadata_to_grpc(ref.return_metadata_internal),
            target_collection: ref.is_a?(Q::QueryReferenceMultiTarget) ? ref.target_collection : nil
          )
        end

        def parse_return_properties(props)
          return nil if props.nil? || props == true

          convert_to_set(props == false ? [] : props)
        end

        # Python __convert_to_set: de-duplicated list, preserving order.
        def convert_to_set(args)
          args.is_a?(Array) ? args.uniq : [args]
        end
      end
    end
  end
end
