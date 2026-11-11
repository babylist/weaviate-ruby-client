# frozen_string_literal: true

module Weaviate
  module Collections
    module Grpc
      # Python weaviate.collections.classes.internal._Generative: the RAG part of a search request.
      class Generative
        G = ::Weaviate::Classes::Generate

        attr_reader :single, :grouped, :grouped_properties, :generative_provider

        def initialize(single:, grouped:, grouped_properties:, generative_provider: nil)
          @single = single
          @grouped = grouped
          @grouped_properties = grouped_properties
          @generative_provider = generative_provider
        end

        # -> Weaviate::V1::GenerativeSearch
        def to_grpc(server_version)
          return to_grpc_legacy(server_version) if server_version.is_lower_than(1, 27, 14)

          ::Weaviate::V1::GenerativeSearch.new(single: single_grpc, grouped: grouped_grpc)
        end

        private

        def provider_queries(opts)
          @generative_provider.nil? ? nil : [@generative_provider.to_grpc(opts)]
        end

        def options_for(prompt)
          G::GenerativeConfigRuntimeOptions.new(return_metadata: prompt.metadata, images: prompt.images,
                                                image_properties: prompt.image_properties)
        end

        def single_grpc
          case @single
          when G::SinglePrompt
            ::Weaviate::V1::GenerativeSearch::Single.new(prompt: @single.prompt, queries: provider_queries(options_for(@single)),
                                                         debug: @single.debug)
          when String
            ::Weaviate::V1::GenerativeSearch::Single.new(
              prompt: @single, queries: provider_queries(G::GenerativeConfigRuntimeOptions.new)
            )
          end
        end

        def grouped_grpc
          case @grouped
          when G::GroupedTask
            ::Weaviate::V1::GenerativeSearch::Grouped.new(
              task: @grouped.prompt, properties: G.to_text_array(@grouped.non_blob_properties),
              queries: provider_queries(options_for(@grouped))
            )
          when String
            ::Weaviate::V1::GenerativeSearch::Grouped.new(
              task: @grouped, properties: G.to_text_array(@grouped_properties),
              queries: provider_queries(G::GenerativeConfigRuntimeOptions.new)
            )
          end
        end

        def to_grpc_legacy(server_version)
          unless @generative_provider.nil?
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Dynamic RAG", server_version.to_s,
                                                                             "1.27.14")
          end

          single_prompt = @single.is_a?(G::SinglePrompt) ? @single.prompt : @single
          if @grouped.is_a?(G::GroupedTask)
            grouped_task = @grouped.prompt
            grouped_properties = @grouped.non_blob_properties
          else
            grouped_task = @grouped
            grouped_properties = @grouped_properties
          end
          ::Weaviate::V1::GenerativeSearch.new(single_response_prompt: single_prompt.to_s,
                                               grouped_response_task: grouped_task.to_s,
                                               grouped_properties: grouped_properties)
        end
      end

      # Python _GroupBy: request-level group-by built from Weaviate::Classes::Query::GroupBy.
      class GroupByRequest
        attr_reader :prop, :number_of_groups, :objects_per_group

        def initialize(prop:, number_of_groups:, objects_per_group:)
          @prop = prop
          @number_of_groups = number_of_groups
          @objects_per_group = objects_per_group
        end

        def to_grpc
          ::Weaviate::V1::GroupBy.new(path: [@prop], number_of_groups: @number_of_groups,
                                      objects_per_group: @objects_per_group)
        end

        def self.from_input(group_by)
          return nil if group_by.nil?

          new(prop: group_by.prop, number_of_groups: group_by.number_of_groups,
              objects_per_group: group_by.objects_per_group)
        end
      end

      # Python _QueryOptions: what to extract from a search reply.
      class QueryOptions < ::Weaviate::Model
        attribute :include_metadata
        attribute :include_properties
        attribute :include_references
        attribute :include_vector
        attribute :is_group_by

        def self.from_input(return_metadata, return_properties, include_vector, collection_references,
                            query_references, rerank = nil, group_by = nil)
          new(
            include_metadata: !return_metadata.nil? || !rerank.nil?,
            include_properties: !(return_properties.is_a?(Array) && return_properties.empty?),
            include_references: !collection_references.nil? || !query_references.nil?,
            include_vector: [true, false].include?(include_vector) ? include_vector : true,
            is_group_by: !group_by.nil?
          )
        end
      end
    end
  end
end
