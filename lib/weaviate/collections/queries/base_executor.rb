# frozen_string_literal: true

module Weaviate
  module Collections
    module Queries
      # Port of weaviate.collections.queries.base_executor._BaseExecutor: request preparation shared
      # by `.query` and `.generate`, and conversion of Weaviate::V1::SearchReply into output objects.
      class BaseExecutor
        Q = ::Weaviate::Classes::Query
        OQ = ::Weaviate::Outputs::Query
        OG = ::Weaviate::Outputs::Generate
        G = ::Weaviate::Collections::Grpc

        attr_reader :name

        def initialize(connection:, name:, consistency_level: nil, tenant: nil, validate_arguments: true,
                       properties: nil, references: nil)
          @connection = connection
          @name = name
          @tenant = tenant
          @consistency_level = consistency_level
          @validate_arguments = validate_arguments
          @properties = properties
          @references = references
        end

        def inspect = "#<#{self.class.name} name=#{@name.inspect} tenant=#{@tenant.inspect}>"

        # The request builder (rebuilt per call so it always uses the connection's current server version).
        def query_grpc
          version = @connection.weaviate_version
          G::QueryGRPC.new(weaviate_version: version, name: @name, tenant: @tenant,
                           consistency_level: @consistency_level, validate_arguments: @validate_arguments,
                           uses_125_api: version.is_at_least(1, 25, 0), uses_127_api: version.is_at_least(1, 27, 0))
        end

        # ---- response conversion -------------------------------------------------

        def result_to_query_return(res, options)
          OQ::QueryReturn.new(
            objects: res.results.map { |obj| result_to_query_object(obj.properties, obj.metadata, options) },
            query_profile: extract_query_profile(res)
          )
        end

        def result_to_generative_query_return(res, options)
          OG::GenerativeReturn.new(
            generated: extract_generated_from_reply(res),
            objects: res.results.map do |obj|
              result_to_generative_object(obj.properties, obj.metadata, obj.generative, options)
            end,
            generative: extract_generative_grouped(res.generative_grouped_results),
            query_profile: extract_query_profile(res)
          )
        end

        def result_to_generative_return(res, options)
          options.is_group_by ? result_to_generative_groupby_return(res, options) : result_to_generative_query_return(res, options)
        end

        def result_to_groupby_return(res, options)
          groups = res.group_by_results.to_h { |group| [group.name, result_to_group(group, options)] }
          OQ::GroupByReturn.new(objects: groups.values.flat_map(&:objects), groups: groups,
                                query_profile: extract_query_profile(res))
        end

        def result_to_generative_groupby_return(res, options)
          groups = res.group_by_results.to_h { |group| [group.name, result_to_generative_group(group, options)] }
          objects = groups.values.flat_map do |group|
            group.objects.map do |obj|
              OQ::GroupByObject.new(collection: obj.collection, properties: obj.properties,
                                    references: obj.references, metadata: obj.metadata,
                                    belongs_to_group: group.name, uuid: obj.uuid, vector: obj.vector)
            end
          end
          OG::GenerativeGroupByReturn.new(
            objects: objects, groups: groups,
            generated: res.generative_grouped_result.to_s.empty? ? nil : res.generative_grouped_result,
            query_profile: extract_query_profile(res)
          )
        end

        def result_to_query_or_groupby_return(res, options)
          options.is_group_by ? result_to_groupby_return(res, options) : result_to_query_return(res, options)
        end

        # ---- input parsing ---------------------------------------------------------

        def parse_return_properties(return_properties)
          # fast way to check if it is an empty list, an empty string or false
          return [] if !return_properties.nil? && (return_properties == false ||
                                                   (return_properties.respond_to?(:empty?) && return_properties.empty?))

          return_properties
        end

        def parse_return_metadata(return_metadata, include_vector)
          if @validate_arguments
            G::Validator.validate_input([
                                          G::Validator.arg([[:list_of, String, Symbol], Q::MetadataQuery, nil],
                                                           "return_metadata", return_metadata),
                                          G::Validator.arg([:bool, String, Array], "include_vector", include_vector)
                                        ])
          end
          ret_md =
            if return_metadata.nil? then nil
            elsif return_metadata.is_a?(Q::MetadataQuery) then return_metadata
            else Q::MetadataQuery.new(**return_metadata.to_h { |prop| [prop.to_sym, true] })
            end

          if ret_md&.query_profile && @connection.weaviate_version.is_lower_than(1, 36, 9)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
              "Query profiling", @connection.weaviate_version.to_s, "1.36.9"
            )
          end

          Q::MetadataQueryInternal.from_public(ret_md, include_vector)
        end

        def parse_return_references(return_references)
          return_references
        end

        private

        def retrieve_timestamp(timestamp)
          # Handle the case in which last_update_time_unix is in nanoseconds or milliseconds, issue #958
          if timestamp.to_s.length <= 13
            Time.at(Rational(timestamp, 1000)).utc
          else
            Time.at(Rational(timestamp, 1_000_000_000)).utc
          end
        end

        def extract_metadata_for_object(add_props)
          OQ::MetadataReturn.new(
            distance: add_props.distance_present ? add_props.distance : nil,
            certainty: add_props.certainty_present ? add_props.certainty : nil,
            creation_time: add_props.creation_time_unix_present ? retrieve_timestamp(add_props.creation_time_unix) : nil,
            last_update_time: if add_props.last_update_time_unix_present
                                retrieve_timestamp(add_props.last_update_time_unix)
                              end,
            score: add_props.score_present ? add_props.score : nil,
            explain_score: add_props.explain_score_present ? add_props.explain_score : nil,
            is_consistent: add_props.is_consistent_present ? add_props.is_consistent : nil,
            rerank_score: add_props.rerank_score_present ? add_props.rerank_score : nil
          )
        end

        def extract_metadata_for_group_by_object(add_props)
          OQ::GroupByMetadataReturn.new(distance: add_props.distance_present ? add_props.distance : nil)
        end

        def extract_id_for_object(add_props)
          hex = add_props.id_as_bytes.to_s.unpack1("H*").to_s.rjust(32, "0")
          "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
        end

        def extract_vector_for_object(add_props)
          if add_props.vector_bytes.empty? && add_props.vector.empty? && add_props.vectors.empty?
            return {}
          end
          return { "default" => G::ByteOps.decode_float32s(add_props.vector_bytes) } unless add_props.vector_bytes.empty?

          add_props.vectors.to_h do |vec|
            value = if vec.type == :VECTOR_TYPE_MULTI_FP32
                      G::Unpack.multi(vec.vector_bytes)
                    else
                      G::Unpack.single(vec.vector_bytes)
                    end
            [vec.name, value]
          end
        end

        def extract_generated_from_metadata(add_props)
          add_props.generative_present ? add_props.generative : nil
        end

        def extract_generated_from_generative(generative)
          return nil if generative.nil? || generative.values.empty?

          generative.values[0].result
        end

        def extract_generated_from_reply(res)
          # for BC, generative_grouped_result is deprecated in favour of generative_grouped_results
          return res.generative_grouped_result unless res.generative_grouped_result.to_s.empty?

          grouped = res.generative_grouped_results
          return grouped.values[0].result if grouped && !grouped.values.empty?

          nil
        end

        # Returns the provider-specific metadata message (e.g. Weaviate::V1::GenerativeOpenAIMetadata) or nil.
        def extract_generative_metadata(metadata)
          return nil if metadata.nil?

          field = metadata.kind if metadata.respond_to?(:kind)
          return metadata.public_send(field) if field

          ::Weaviate::V1::GenerativeMetadata.descriptor.each do |f|
            value = metadata.public_send(f.name)
            return value unless value.nil?
          end
          nil
        end

        def extract_generative_single(result)
          return nil if result.nil? || result.values.empty?

          generative = result.values[0]
          debug = generative.debug
          OG::GenerativeSingle.new(
            debug: debug.nil? || debug.full_prompt.to_s.empty? ? nil : debug,
            metadata: extract_generative_metadata(generative.metadata),
            text: generative.result
          )
        end

        def extract_generative_grouped(result)
          return nil if result.nil? || result.values.empty?

          generative = result.values[0]
          OG::GenerativeGrouped.new(metadata: extract_generative_metadata(generative.metadata), text: generative.result)
        end

        def deserialize_list_value(value)
          case value.kind
          when :bool_values then value.bool_values.values.to_a
          when :date_values then value.date_values.values.map { |v| ::Weaviate::Util.datetime_from_weaviate_str(v) }
          when :int_values then G::ByteOps.decode_int64s(value.int_values.values)
          when :number_values then G::ByteOps.decode_float64s(value.number_values.values)
          when :text_values then value.text_values.values.to_a
          when :uuid_values then value.uuid_values.values.to_a
          when :object_values then value.object_values.values.map { |v| parse_nonref_properties(v) }
          else
            ::Weaviate::Warnings.unknown_type_encountered(value.kind)
            nil
          end
        end

        def deserialize_non_ref_prop(value)
          case value.kind
          when :uuid_value then value.uuid_value
          when :date_value then ::Weaviate::Util.datetime_from_weaviate_str(value.date_value)
          when :text_value then value.text_value.to_s
          when :int_value then Integer(value.int_value)
          when :number_value then Float(value.number_value)
          when :bool_value then value.bool_value
          when :list_value then deserialize_list_value(value.list_value)
          when :object_value then parse_nonref_properties(value.object_value)
          when :geo_value then build_geo_coordinate(value.geo_value)
          when :blob_value then value.blob_value
          when :phone_value
            phone = value.phone_value
            OQ::PhoneNumberType.new(country_code: phone.country_code, default_country: phone.default_country,
                                    international_formatted: phone.international_formatted,
                                    national: phone.national, national_formatted: phone.national_formatted,
                                    number: phone.input, valid: phone.valid)
          when :null_value then nil
          else
            ::Weaviate::Warnings.unknown_type_encountered(value.kind)
            nil
          end
        end

        def build_geo_coordinate(geo)
          klass = geo_coordinate_class
          return { "latitude" => geo.latitude, "longitude" => geo.longitude } if klass.nil?

          klass.new(latitude: geo.latitude, longitude: geo.longitude)
        end

        # The GeoCoordinate input/output class lives with the data types (owned by the data area).
        def geo_coordinate_class
          return ::Weaviate::Classes::Data::GeoCoordinate if defined?(::Weaviate::Classes::Data::GeoCoordinate)

          nil
        end

        def parse_nonref_properties(properties)
          return {} if properties.nil?

          map_to_h(properties.fields) { |value| deserialize_non_ref_prop(value) }
        end

        def parse_ref_properties(properties)
          if properties.ref_props.empty?
            return properties.ref_props_requested ? {} : nil
          end

          ref_options = G::QueryOptions.new(include_metadata: true, include_properties: true, include_references: true,
                                            include_vector: true, is_group_by: false)
          properties.ref_props.to_h do |ref_prop|
            objects = ref_prop.properties.map { |prop| result_to_query_object(prop, prop.metadata, ref_options) }
            [ref_prop.prop_name, OQ::CrossReference.from(objects)]
          end
        end

        def object_fields(props, meta, options)
          props ||= ::Weaviate::V1::PropertiesResult.new
          meta ||= ::Weaviate::V1::MetadataResult.new
          {
            collection: props.target_collection,
            properties: options.include_properties ? parse_nonref_properties(props.non_ref_props) : {},
            references: options.include_references ? parse_ref_properties(props) : nil,
            uuid: extract_id_for_object(meta),
            vector: options.include_vector ? extract_vector_for_object(meta) : {}
          }
        end

        def result_to_query_object(props, meta, options)
          meta ||= ::Weaviate::V1::MetadataResult.new
          OQ::Object.new(
            **object_fields(props, meta, options),
            metadata: options.include_metadata ? extract_metadata_for_object(meta) : OQ::MetadataReturn.new
          )
        end

        def result_to_generative_object(props, meta, gen, options)
          meta ||= ::Weaviate::V1::MetadataResult.new
          uses_127_api = @connection.weaviate_version.is_at_least(1, 27, 0)
          OG::GenerativeObject.new(
            **object_fields(props, meta, options),
            metadata: options.include_metadata ? extract_metadata_for_object(meta) : OQ::MetadataReturn.new,
            generated: uses_127_api ? extract_generated_from_generative(gen) : extract_generated_from_metadata(meta),
            generative: extract_generative_single(gen)
          )
        end

        def result_to_group_by_object(props, meta, options, group_name)
          meta ||= ::Weaviate::V1::MetadataResult.new
          OQ::GroupByObject.new(
            **object_fields(props, meta, options),
            metadata: options.include_metadata ? extract_metadata_for_group_by_object(meta) : OQ::GroupByMetadataReturn.new,
            belongs_to_group: group_name
          )
        end

        def group_fields(res, options)
          {
            objects: res.objects.map { |obj| result_to_group_by_object(obj.properties, obj.metadata, options, res.name) },
            name: res.name,
            number_of_objects: res.number_of_objects,
            min_distance: res.min_distance,
            max_distance: res.max_distance,
            rerank_score: res.rerank&.score
          }
        end

        def result_to_group(res, options)
          OQ::Group.new(**group_fields(res, options))
        end

        def result_to_generative_group(res, options)
          OG::GenerativeGroup.new(**group_fields(res, options), generated: res.generative&.result)
        end

        # Google::Protobuf::Map#to_h ignores blocks, so convert explicitly.
        def map_to_h(map)
          out = {}
          map.each { |key, value| out[key] = yield(value) }
          out
        end

        def extract_query_profile(res)
          profile = res.query_profile
          return nil if profile.nil?

          OQ::QueryProfileReturn.new(
            shards: profile.shards.map do |shard|
              OQ::ShardProfileReturn.new(
                name: shard.name,
                node: shard.node,
                searches: map_to_h(shard.searches) do |search|
                  OQ::SearchProfileReturn.new(details: map_to_h(search.details) { |v| v })
                end
              )
            end
          )
        end
      end
    end
  end
end
