# frozen_string_literal: true

require_relative "base_executor"

module Weaviate
  module Collections
    module Queries
      # Shared implementation of every query type (Python duplicates one executor per query type and
      # per namespace; here the `.query` and `.generate` namespaces share these request builders).
      class SearchExecutor < BaseExecutor
        SEARCHES = %i[fetch_objects fetch_objects_by_ids bm25 hybrid near_vector near_object near_text near_image
                      near_media].freeze

        private

        # Collects the keyword arguments of the calling public method from its binding.
        def call_kwargs(bnd, meth)
          method(meth).parameters.each_with_object({}) do |(type, name), out|
            out[name] = bnd.local_variable_get(name) if %i[key keyreq].include?(type)
          end
        end

        # Builds and sends the request; returns the raw Weaviate::V1::SearchReply.
        def execute_search(kind, primary, kw, generative)
          @connection.grpc_search(build_request(kind, primary, kw, generative))
        end

        def query_options(kw)
          G::QueryOptions.from_input(kw[:return_metadata], kw[:return_properties], kw[:include_vector], @references,
                                     kw[:return_references], kw[:rerank], kw[:group_by])
        end

        def build_request(kind, primary, kw, generative)
          q = query_grpc
          common = {
            return_metadata: parse_return_metadata(kw[:return_metadata], kw[:include_vector]),
            return_properties: parse_return_properties(kw[:return_properties]),
            return_references: parse_return_references(kw[:return_references])
          }
          common[:generative] = generative unless generative.nil?
          paging = { limit: kw[:limit], offset: kw[:offset] }
          search = { autocut: kw[:auto_limit], filters: kw[:filters], group_by: G::GroupByRequest.from_input(kw[:group_by]),
                     rerank: kw[:rerank], boost: kw[:boost] }

          case kind
          when :fetch_objects
            q.get(**paging, after: kw[:after], filters: kw[:filters], sort: kw[:sort], **common)
          when :fetch_objects_by_ids
            filters = Q::Filter.any_of(primary.map { |uuid| Q::Filter.by_id.equal(uuid) })
            q.get(**paging, after: kw[:after], filters: filters, sort: kw[:sort], **common)
          when :fetch_object_by_id
            q.get(limit: 1, filters: Q::Filter.by_id.equal(primary), **common)
          when :bm25
            q.bm25(query: primary, properties: kw[:query_properties], operator: kw[:operator], **paging, **search,
                   **common)
          when :hybrid
            q.hybrid(query: primary, alpha: kw[:alpha], vector: kw[:vector], properties: kw[:query_properties],
                     fusion_type: kw[:fusion_type], distance: kw[:max_vector_distance],
                     bm25_operator: kw[:bm25_operator], diversity_selection: kw[:diversity_selection],
                     target_vector: kw[:target_vector], **paging, **search, **common)
          when :near_vector
            q.near_vector(near_vector: primary, **near_args(kw), **paging, **search, **common)
          when :near_object
            q.near_object(near_object: primary, **near_args(kw), **paging, **search, **common)
          when :near_text
            q.near_text(near_text: primary, move_to: kw[:move_to], move_away: kw[:move_away], **near_args(kw),
                        **paging, **search, **common)
          when :near_image
            q.near_media(media: ::Weaviate::Util.parse_blob(primary), type_: Q::NearMediaType::IMAGE,
                         **near_args(kw), **paging, **search, **common)
          when :near_media
            media, media_type = primary
            q.near_media(media: ::Weaviate::Util.parse_blob(media), type_: media_type.to_s, **near_args(kw), **paging,
                         **search, **common)
          else
            raise ArgumentError, "unknown search #{kind}"
          end
        end

        def near_args(kw)
          { certainty: kw[:certainty], distance: kw[:distance], target_vector: kw[:target_vector],
            diversity_selection: kw[:diversity_selection] }
        end
      end
    end
  end
end
