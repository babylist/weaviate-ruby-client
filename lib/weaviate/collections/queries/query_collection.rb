# frozen_string_literal: true

require_relative "executor"

module Weaviate
  module Collections
    module Queries
      # Port of weaviate.collections.query._QueryCollection: the `collection.query` namespace.
      #
      # Search methods return a Weaviate::Outputs::Query::QueryReturn, or a GroupByReturn when `group_by:`
      # is given; `fetch_object_by_id` returns an ObjectSingleReturn or nil.
      class QueryCollection < SearchExecutor
        def fetch_object_by_id(uuid, include_vector: false, return_properties: nil, return_references: nil)
          return_metadata = Q::MetadataQuery.new(creation_time: true, last_update_time: true, is_consistent: true)
          kw = { include_vector: include_vector, return_metadata: return_metadata,
                 return_properties: return_properties, return_references: return_references }
          res = execute_search(:fetch_object_by_id, uuid, kw, nil)
          objects = result_to_query_return(res, query_options(kw)).objects
          return nil if objects.empty?

          obj = objects[0]
          OQ::ObjectSingleReturn.new(
            uuid: obj.uuid, vector: obj.vector, properties: obj.properties,
            metadata: OQ::MetadataSingleObjectReturn.new(creation_time: obj.metadata.creation_time,
                                                         last_update_time: obj.metadata.last_update_time,
                                                         is_consistent: obj.metadata.is_consistent),
            references: obj.references, collection: obj.collection
          )
        end

        def fetch_objects(limit: nil, offset: nil, after: nil, filters: nil, sort: nil, include_vector: false,
                          return_metadata: nil, return_properties: nil, return_references: nil)
          kw = call_kwargs(binding, __method__)
          result_to_query_return(execute_search(:fetch_objects, nil, kw, nil), query_options(kw))
        end

        def fetch_objects_by_ids(ids, limit: nil, offset: nil, after: nil, sort: nil, include_vector: false,
                                 return_metadata: nil, return_properties: nil, return_references: nil)
          kw = call_kwargs(binding, __method__)
          ids = ids.nil? ? [] : ids.to_a
          return result_to_query_return(::Weaviate::V1::SearchReply.new, query_options(kw)) if ids.empty?

          result_to_query_return(execute_search(:fetch_objects_by_ids, ids, kw, nil), query_options(kw))
        end

        def bm25(query, query_properties: nil, limit: nil, offset: nil, operator: nil, auto_limit: nil, filters: nil,
                 group_by: nil, rerank: nil, boost: nil, include_vector: false, return_metadata: nil,
                 return_properties: nil, return_references: nil)
          search(:bm25, query, call_kwargs(binding, __method__))
        end

        def hybrid(query, alpha: nil, vector: nil, query_properties: nil, fusion_type: nil, max_vector_distance: nil,
                   limit: nil, offset: nil, bm25_operator: nil, auto_limit: nil, filters: nil, group_by: nil,
                   rerank: nil, boost: nil, diversity_selection: nil, target_vector: nil, include_vector: false,
                   return_metadata: nil, return_properties: nil, return_references: nil)
          search(:hybrid, query, call_kwargs(binding, __method__))
        end

        def near_vector(near_vector, certainty: nil, distance: nil, limit: nil, offset: nil, auto_limit: nil,
                        filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil, include_vector: false,
                        return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          search(:near_vector, near_vector, call_kwargs(binding, __method__))
        end

        def near_object(near_object, certainty: nil, distance: nil, limit: nil, offset: nil, auto_limit: nil,
                        filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil, include_vector: false,
                        return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          search(:near_object, near_object, call_kwargs(binding, __method__))
        end

        def near_text(query, certainty: nil, distance: nil, move_to: nil, move_away: nil, limit: nil, offset: nil,
                      auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                      include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                      diversity_selection: nil)
          search(:near_text, query, call_kwargs(binding, __method__))
        end

        def near_image(near_image, certainty: nil, distance: nil, limit: nil, offset: nil, auto_limit: nil,
                       filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil, include_vector: false,
                       return_metadata: nil, return_properties: nil, return_references: nil,
                       diversity_selection: nil)
          search(:near_image, near_image, call_kwargs(binding, __method__))
        end

        def near_media(media, media_type, certainty: nil, distance: nil, limit: nil, offset: nil, auto_limit: nil,
                       filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil, include_vector: false,
                       return_metadata: nil, return_properties: nil, return_references: nil,
                       diversity_selection: nil)
          search(:near_media, [media, media_type], call_kwargs(binding, __method__))
        end

        private

        def search(kind, primary, kw)
          result_to_query_or_groupby_return(execute_search(kind, primary, kw, nil), query_options(kw))
        end
      end

      # Port of weaviate.collections.generate._GenerateCollection: the `collection.generate` namespace
      # (retrieval augmented generation). Every method accepts the query arguments of the matching
      # `collection.query` method plus `single_prompt:`, `grouped_task:`, `grouped_properties:` and
      # `generative_provider:`.
      #
      # Search methods return a Weaviate::Outputs::Generate::GenerativeReturn, or a
      # GenerativeGroupByReturn when `group_by:` is given.
      class GenerateCollection < SearchExecutor
        GENERATIVE_KEYS = %i[single_prompt grouped_task grouped_properties generative_provider].freeze

        def fetch_objects(single_prompt: nil, grouped_task: nil, grouped_properties: nil, generative_provider: nil,
                          limit: nil, offset: nil, after: nil, filters: nil, sort: nil, include_vector: false,
                          return_metadata: nil, return_properties: nil, return_references: nil)
          kw = call_kwargs(binding, __method__)
          res = execute_search(:fetch_objects, nil, kw, generative(kw))
          result_to_generative_query_return(res, query_options(kw))
        end

        def fetch_objects_by_ids(ids, single_prompt: nil, grouped_task: nil, grouped_properties: nil,
                                 generative_provider: nil, limit: nil, offset: nil, after: nil, sort: nil,
                                 include_vector: false, return_metadata: nil, return_properties: nil,
                                 return_references: nil)
          kw = call_kwargs(binding, __method__)
          ids = ids.nil? ? [] : ids.to_a
          return result_to_generative_query_return(::Weaviate::V1::SearchReply.new, query_options(kw)) if ids.empty?

          res = execute_search(:fetch_objects_by_ids, ids, kw, generative(kw))
          result_to_generative_query_return(res, query_options(kw))
        end

        def bm25(query, single_prompt: nil, grouped_task: nil, grouped_properties: nil, generative_provider: nil,
                 query_properties: nil, limit: nil, offset: nil, operator: nil, auto_limit: nil, filters: nil,
                 group_by: nil, rerank: nil, boost: nil, include_vector: false, return_metadata: nil,
                 return_properties: nil, return_references: nil)
          search(:bm25, query, call_kwargs(binding, __method__))
        end

        def hybrid(query, single_prompt: nil, grouped_task: nil, grouped_properties: nil, generative_provider: nil,
                   alpha: nil, vector: nil, query_properties: nil, fusion_type: nil, max_vector_distance: nil,
                   limit: nil, offset: nil, bm25_operator: nil, auto_limit: nil, filters: nil, group_by: nil,
                   rerank: nil, boost: nil, diversity_selection: nil, target_vector: nil, include_vector: false,
                   return_metadata: nil, return_properties: nil, return_references: nil)
          search(:hybrid, query, call_kwargs(binding, __method__))
        end

        def near_vector(near_vector, single_prompt: nil, grouped_task: nil, grouped_properties: nil,
                        generative_provider: nil, certainty: nil, distance: nil, limit: nil, offset: nil,
                        auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                        include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          search(:near_vector, near_vector, call_kwargs(binding, __method__))
        end

        def near_object(near_object, single_prompt: nil, grouped_task: nil, grouped_properties: nil,
                        generative_provider: nil, certainty: nil, distance: nil, limit: nil, offset: nil,
                        auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                        include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                        diversity_selection: nil)
          search(:near_object, near_object, call_kwargs(binding, __method__))
        end

        def near_text(query, single_prompt: nil, grouped_task: nil, grouped_properties: nil, generative_provider: nil,
                      certainty: nil, distance: nil, move_to: nil, move_away: nil, limit: nil, offset: nil,
                      auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                      include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                      diversity_selection: nil)
          search(:near_text, query, call_kwargs(binding, __method__))
        end

        def near_image(near_image, single_prompt: nil, grouped_task: nil, grouped_properties: nil,
                       generative_provider: nil, certainty: nil, distance: nil, limit: nil, offset: nil,
                       auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                       include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                       diversity_selection: nil)
          search(:near_image, near_image, call_kwargs(binding, __method__))
        end

        def near_media(media, media_type, single_prompt: nil, grouped_task: nil, grouped_properties: nil,
                       generative_provider: nil, certainty: nil, distance: nil, limit: nil, offset: nil,
                       auto_limit: nil, filters: nil, group_by: nil, rerank: nil, boost: nil, target_vector: nil,
                       include_vector: false, return_metadata: nil, return_properties: nil, return_references: nil,
                       diversity_selection: nil)
          search(:near_media, [media, media_type], call_kwargs(binding, __method__))
        end

        private

        def generative(kw)
          G::Generative.new(single: kw[:single_prompt], grouped: kw[:grouped_task],
                            grouped_properties: kw[:grouped_properties], generative_provider: kw[:generative_provider])
        end

        def search(kind, primary, kw)
          result_to_generative_return(execute_search(kind, primary, kw, generative(kw)), query_options(kw))
        end
      end
    end
  end
end
