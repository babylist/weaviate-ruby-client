# frozen_string_literal: true

module Weaviate
  module Classes
    module Query
      # Define how the query's hybrid fusion operation should be performed.
      module HybridFusion
        extend ::Weaviate::StrEnum

        RANKED = "FUSION_TYPE_RANKED"
        RELATIVE_SCORE = "FUSION_TYPE_RELATIVE_SCORE"
      end

      # Define how the query's move operation should be performed.
      class Move
        attr_reader :force

        def initialize(force_ = nil, force: force_, objects: nil, concepts: nil)
          if (objects.nil? || (objects.is_a?(Array) && objects.empty?)) &&
             (concepts.nil? || (concepts.is_a?(Array) && concepts.empty?))
            raise ArgumentError, "Either objects or concepts need to be given"
          end

          @force = force
          @objects = if objects.nil? then nil
                     elsif objects.is_a?(Array) then objects.map(&:to_s)
                     else [objects.to_s]
                     end
          @concepts = if concepts.nil? then nil
                      elsif concepts.is_a?(Array) then concepts
                      else [concepts]
                      end
        end

        def objects_list = @objects
        def concepts_list = @concepts

        def to_gql_payload
          payload = { "force" => force }
          payload["objects"] = @objects.map { |obj| { "id" => obj } } unless @objects.nil?
          payload["concepts"] = @concepts unless @concepts.nil?
          payload
        end

        def ==(other)
          other.is_a?(Move) && other.force == force && other.objects_list == objects_list &&
            other.concepts_list == concepts_list
        end
      end

      # Define which metadata should be returned in the query's results.
      class MetadataQuery < ::Weaviate::Model
        attribute :creation_time, default: false
        attribute :last_update_time, default: false
        attribute :distance, default: false
        attribute :certainty, default: false
        attribute :score, default: false
        attribute :explain_score, default: false
        attribute :is_consistent, default: false
        attribute :query_profile, default: false

        # All fields except query_profile (which adds overhead; see full_with_profile).
        def self.full
          new(creation_time: true, last_update_time: true, distance: true, certainty: true, score: true,
              explain_score: true, is_consistent: true)
        end

        # All fields, including query profiling (requires Weaviate >= 1.36.9).
        def self.full_with_profile
          new(creation_time: true, last_update_time: true, distance: true, certainty: true, score: true,
              explain_score: true, is_consistent: true, query_profile: true)
        end
      end

      # Python _MetadataQuery: the internal, request-level metadata selection.
      class MetadataQueryInternal < ::Weaviate::Model
        attribute :vector
        attribute :uuid, default: true
        attribute :creation_time_unix, default: false
        attribute :last_update_time_unix, default: false
        attribute :distance, default: false
        attribute :certainty, default: false
        attribute :score, default: false
        attribute :explain_score, default: false
        attribute :is_consistent, default: false
        attribute :vectors, default: nil
        attribute :query_profile, default: false

        def self.from_public(public, include_vector)
          vector = [true, false].include?(include_vector) ? include_vector : false
          vectors = include_vector.is_a?(Array) ? include_vector : nil
          return new(vector: vector, vectors: vectors) if public.nil?

          new(vector: vector, vectors: vectors, creation_time_unix: public.creation_time,
              last_update_time_unix: public.last_update_time, distance: public.distance,
              certainty: public.certainty, score: public.score, explain_score: public.explain_score,
              is_consistent: public.is_consistent, query_profile: public.query_profile)
        end
      end

      # Define how the query's group-by operation should be performed.
      class GroupBy < ::Weaviate::Model
        attribute :prop
        attribute :objects_per_group
        attribute :number_of_groups
      end

      # Python _Sort
      class SortItem < ::Weaviate::Model
        attribute :prop
        attribute :ascending, default: true
      end

      # Python _Sorting: a chain of sort operations.
      class Sorting
        attr_reader :sorts

        def initialize
          @sorts = []
        end

        def by_property(name, ascending: true)
          @sorts << SortItem.new(prop: name, ascending: ascending)
          self
        end

        def by_id(ascending: true)
          @sorts << SortItem.new(prop: "_id", ascending: ascending)
          self
        end

        def by_creation_time(ascending: true)
          @sorts << SortItem.new(prop: "_creationTimeUnix", ascending: ascending)
          self
        end

        def by_update_time(ascending: true)
          @sorts << SortItem.new(prop: "_lastUpdateTimeUnix", ascending: ascending)
          self
        end

        def ==(other) = other.is_a?(Sorting) && other.sorts == sorts
      end

      # Define how the query's sort operation should be performed using the available static methods.
      class Sort
        def initialize
          raise TypeError, "Sort cannot be instantiated. Use the static methods to create a sorter."
        end

        class << self
          def by_property(name, ascending: true) = Sorting.new.by_property(name, ascending: ascending)
          def by_id(ascending: true) = Sorting.new.by_id(ascending: ascending)
          def by_creation_time(ascending: true) = Sorting.new.by_creation_time(ascending: ascending)
          def by_update_time(ascending: true) = Sorting.new.by_update_time(ascending: ascending)
        end
      end

      # Define how the query's rerank operation should be performed.
      class Rerank < ::Weaviate::Model
        attribute :prop
        attribute :query, default: nil
      end

      # ---- Boost ---------------------------------------------------------------

      # The decay curve used by a distance-based boost (`time_decay`, `numeric_decay`).
      module BoostCurve
        extend ::Weaviate::StrEnum

        EXPONENTIAL = "exp"
        GAUSSIAN = "gauss"
        LINEAR = "linear"
      end

      # The transform applied to a numeric property's value in `numeric_property`.
      module BoostModifier
        extend ::Weaviate::StrEnum

        LOG1P = "log1p"
        SQRT = "sqrt"
      end

      class TimeDecayFunction < ::Weaviate::Model
        attribute :property
        attribute :origin
        attribute :scale
        attribute :offset, default: nil
        attribute :curve, default: nil
        attribute :decay_value, default: nil
      end

      class NumericDecayFunction < ::Weaviate::Model
        attribute :property
        attribute :origin
        attribute :scale
        attribute :offset, default: nil
        attribute :curve, default: nil
        attribute :decay_value, default: nil
      end

      class PropertyValueFunction < ::Weaviate::Model
        attribute :property
        attribute :modifier, default: nil
      end

      class BoostCondition < ::Weaviate::Model
        attribute :filter, default: nil
        attribute :time_decay, default: nil
        attribute :numeric_decay, default: nil
        attribute :property_value, default: nil
        attribute :weight, default: nil
      end

      # Python _Boost (exported as BoostReturn)
      class BoostReturn < ::Weaviate::Model
        attribute :conditions
        attribute :weight, default: nil
        attribute :depth, default: nil
      end

      # Soft-rank search results: promote or demote objects without removing them from the result set.
      # Available in Weaviate v1.38 and later. Pass the result of a static method via `boost:`.
      class Boost
        Curve = BoostCurve
        Modifier = BoostModifier

        def initialize
          raise TypeError, "Boost cannot be instantiated. Use the static methods to create a boost."
        end

        class << self
          def filter(filter, weight: nil, depth: nil)
            BoostReturn.new(conditions: [BoostCondition.new(filter: filter)], weight: weight, depth: depth)
          end

          def time_decay(property, scale:, origin: nil, offset: nil, curve: nil, decay: nil, weight: nil, depth: nil)
            BoostReturn.new(
              conditions: [
                BoostCondition.new(
                  time_decay: TimeDecayFunction.new(
                    property: property,
                    origin: origin.nil? ? "now" : decay_origin_to_str(origin),
                    scale: decay_duration_to_str(scale),
                    offset: offset.nil? ? nil : decay_duration_to_str(offset),
                    curve: curve,
                    decay_value: decay
                  )
                )
              ],
              weight: weight, depth: depth
            )
          end

          def numeric_decay(property, origin:, scale:, offset: nil, curve: nil, decay: nil, weight: nil, depth: nil)
            BoostReturn.new(
              conditions: [
                BoostCondition.new(
                  numeric_decay: NumericDecayFunction.new(
                    property: property, origin: Float(origin), scale: Float(scale),
                    offset: offset.nil? ? nil : Float(offset), curve: curve, decay_value: decay
                  )
                )
              ],
              weight: weight, depth: depth
            )
          end

          def numeric_property(name, modifier: nil, weight: nil, depth: nil)
            BoostReturn.new(
              conditions: [BoostCondition.new(property_value: PropertyValueFunction.new(property: name,
                                                                                         modifier: modifier))],
              weight: weight, depth: depth
            )
          end

          def blend(boosts, weight: nil, depth: nil)
            boosts = [boosts] if boosts.is_a?(BoostReturn)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Boost.blend() requires at least one boost." if boosts.empty?

            boosts.each do |r|
              next if r.depth.nil?

              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "Cannot set `depth` on sub-boosts passed to `blend()`. Use the top-level `depth` parameter instead."
            end
            conditions = boosts.flat_map do |r|
              r.conditions.map { |cond| cond.weight.nil? && !r.weight.nil? ? cond.with(weight: r.weight) : cond }
            end
            BoostReturn.new(conditions: conditions, weight: weight, depth: depth)
          end

          # Python _decay_duration_to_str: Numeric seconds (Python timedelta) or a duration String such as "7d".
          def decay_duration_to_str(val)
            return val unless val.is_a?(Numeric)

            total = val.to_f
            return "#{(total / 86_400).to_i}d" if total >= 86_400 && (total % 86_400).zero?
            return "#{(total / 3600).to_i}h" if total >= 3600 && (total % 3600).zero?
            return "#{(total / 60).to_i}m" if total >= 60 && (total % 60).zero?
            return "#{total.to_i}s" if total == total.to_i

            "#{total}s"
          end

          # Python _decay_origin_to_str: Time -> RFC3339 (UTC when no zone), Strings ("now") pass through.
          def decay_origin_to_str(val)
            val = val.to_time if !val.is_a?(Time) && val.respond_to?(:to_time) && !val.is_a?(String)
            return val unless val.is_a?(Time)

            frac = val.usec.zero? ? "" : format(".%06d", val.usec)
            "#{val.strftime("%Y-%m-%dT%H:%M:%S")}#{frac}#{val.strftime("%:z")}"
          end
        end
      end

      # ---- Diversity (MMR) -----------------------------------------------------

      # Define MMR (Maximal Marginal Relevance) diversity selection. Not supported for multi-vector indexes.
      class MMR < ::Weaviate::Model
        attribute :limit, default: nil
        attribute :balance, default: nil
      end

      # Factory for diversity selection of search results.
      class Diversity
        def initialize
          raise TypeError, "Diversity cannot be instantiated directly. Use Diversity.mmr(...)."
        end

        def self.mmr(limit_ = nil, limit: limit_, balance: nil) = MMR.new(limit: limit, balance: balance)
      end

      # ---- BM25 operators ------------------------------------------------------

      class BM25OperatorOptions < ::Weaviate::Model
        def self.operator = self::OPERATOR
        def operator = self.class::OPERATOR
      end

      # Define the 'Or' operator for keyword queries.
      class BM25OperatorOr < BM25OperatorOptions
        OPERATOR = :OPERATOR_OR
        attribute :minimum_should_match
      end

      # Define the 'And' operator for keyword queries.
      class BM25OperatorAnd < BM25OperatorOptions
        OPERATOR = :OPERATOR_AND
      end

      # Define the cross-property 'And' operator for keyword queries.
      class BM25OperatorAndCross < BM25OperatorOptions
        OPERATOR = :OPERATOR_AND_CROSS
      end

      # Define how the BM25 query's token matching should be performed (exported as BM25Operator).
      class BM25OperatorFactory
        def initialize
          raise TypeError, "BM25Operator cannot be instantiated. Use the static methods to create."
        end

        class << self
          # At least +minimum_match+ keyword tokens (excluding stopwords) must match.
          def or_(minimum_match_ = nil, minimum_match: minimum_match_)
            BM25OperatorOr.new(minimum_should_match: minimum_match)
          end

          # All query tokens must match (within a single property).
          def and_ = BM25OperatorAnd.new

          # All query tokens must match across the searched properties combined.
          # Requires Weaviate 1.37.15, 1.38.8, 1.39.0 or higher.
          def and_cross = BM25OperatorAndCross.new
        end
      end
      BM25Operator = BM25OperatorFactory

      # ---- Vectors ---------------------------------------------------------------

      # Python _ListOfVectorsQuery: many vectors over a single-vector space.
      class ListOfVectorsQuery < ::Weaviate::Model
        attribute :dimensionality
        attribute :vectors

        def self.is_one_dimensional(query) = query.dimensionality == "1D" # rubocop:disable Naming/PredicatePrefix
        def self.is_two_dimensional(query) = query.dimensionality == "2D" # rubocop:disable Naming/PredicatePrefix
        def one_dimensional? = dimensionality == "1D"
        def two_dimensional? = dimensionality == "2D"
      end

      # Factory class for near vector queries with multiple vectors in `near_vector()` and `hybrid()` methods.
      class NearVector
        def self.list_of_vectors(*vectors)
          if !vectors.empty? && vectors[0].respond_to?(:size) && vectors[0].size.positive?
            first = vectors[0].to_a[0]
            dimensionality = ::Weaviate::Collections::Grpc::Validator.list_like?(first) ? "2D" : "1D"
            return ListOfVectorsQuery.new(dimensionality: dimensionality, vectors: vectors)
          end
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "At least one vector must be given, got: #{vectors.inspect}"
        end
      end

      # Python _HybridNearText
      class HybridNearText < ::Weaviate::Model
        attribute :text
        attribute :distance, default: nil
        attribute :certainty, default: nil
        attribute :move_to, default: nil
        attribute :move_away, default: nil
      end

      # Python _HybridNearVector
      class HybridNearVector < ::Weaviate::Model
        attribute :vector
        attribute :distance, default: nil
        attribute :certainty, default: nil
      end

      # Python _MultiTargetVectorJoinEnum
      module MultiTargetVectorJoinEnum
        extend ::Weaviate::StrEnum

        SUM = "SUM"
        AVERAGE = "AVERAGE"
        MINIMUM = "MINIMUM"
        RELATIVE_SCORE = "RELATIVE_SCORE"
        MANUAL_WEIGHTS = "MANUAL_WEIGHTS"
      end

      # Python _MultiTargetVectorJoin
      class MultiTargetVectorJoin < ::Weaviate::Model
        attribute :combination
        attribute :target_vectors
        attribute :weights, default: nil

        COMBINATIONS = {
          MultiTargetVectorJoinEnum::AVERAGE => :COMBINATION_METHOD_TYPE_AVERAGE,
          MultiTargetVectorJoinEnum::SUM => :COMBINATION_METHOD_TYPE_SUM,
          MultiTargetVectorJoinEnum::RELATIVE_SCORE => :COMBINATION_METHOD_TYPE_RELATIVE_SCORE,
          MultiTargetVectorJoinEnum::MANUAL_WEIGHTS => :COMBINATION_METHOD_TYPE_MANUAL,
          MultiTargetVectorJoinEnum::MINIMUM => :COMBINATION_METHOD_TYPE_MIN
        }.freeze

        def to_grpc_target_vector(_version = nil)
          weights_grpc = []
          targets = target_vectors
          unless weights.nil?
            targets = []
            weights.each do |target, weight|
              Array(weight).each do |w|
                weights_grpc << ::Weaviate::V1::WeightsForTarget.new(target: target.to_s, weight: Float(w))
                targets << target.to_s
              end
            end
          end
          ::Weaviate::V1::Targets.new(target_vectors: targets.map(&:to_s), weights_for_targets: weights_grpc,
                                      combination: COMBINATIONS.fetch(combination))
        end
      end

      # Define how the distances from different target vectors should be combined.
      class TargetVectors
        class << self
          def sum(target_vectors)
            MultiTargetVectorJoin.new(combination: MultiTargetVectorJoinEnum::SUM, target_vectors: target_vectors)
          end

          def average(target_vectors)
            MultiTargetVectorJoin.new(combination: MultiTargetVectorJoinEnum::AVERAGE, target_vectors: target_vectors)
          end

          def minimum(target_vectors)
            MultiTargetVectorJoin.new(combination: MultiTargetVectorJoinEnum::MINIMUM, target_vectors: target_vectors)
          end

          def manual_weights(weights)
            MultiTargetVectorJoin.new(combination: MultiTargetVectorJoinEnum::MANUAL_WEIGHTS,
                                      target_vectors: weights.keys.map(&:to_s), weights: weights)
          end

          def relative_score(weights)
            MultiTargetVectorJoin.new(combination: MultiTargetVectorJoinEnum::RELATIVE_SCORE,
                                      target_vectors: weights.keys.map(&:to_s), weights: weights)
          end
        end
      end

      # Factory for the near text / near vector sub-searches of hybrid queries.
      class HybridVector
        class << self
          def near_text(query, certainty: nil, distance: nil, move_to: nil, move_away: nil)
            HybridNearText.new(text: query, distance: distance, certainty: certainty, move_to: move_to,
                               move_away: move_away)
          end

          def near_vector(vector, certainty: nil, distance: nil)
            HybridNearVector.new(vector: vector, distance: distance, certainty: certainty)
          end
        end
      end

      # ---- Return references / properties -------------------------------------

      # Python _QueryReference: base of QueryReference and QueryReference::MultiTarget.
      class QueryReferenceBase < ::Weaviate::Model
        attribute :link_on
        attribute :include_vector, default: false
        attribute :return_metadata, default: nil
        attribute :return_properties, default: nil
        attribute :return_references, default: nil

        # Python `_return_metadata`
        def return_metadata_internal
          MetadataQueryInternal.from_public(return_metadata, include_vector)
        end
      end

      # Python _QueryReferenceMultiTarget
      class QueryReferenceMultiTarget < QueryReferenceBase
        attribute :target_collection
      end

      # Define a query-time reference to a single-target property when querying through cross-references.
      class QueryReference < QueryReferenceBase
        # Define a query-time reference to a multi-target property.
        MultiTarget = QueryReferenceMultiTarget
      end

      # Define the query-time return properties of a nested property.
      class QueryNested < ::Weaviate::Model
        attribute :name
        attribute :properties
      end

      # The different types of media that can be used in a `near_media` query.
      module NearMediaType
        extend ::Weaviate::StrEnum

        AUDIO = "audio"
        DEPTH = "depth"
        IMAGE = "image"
        IMU = "imu"
        THERMAL = "thermal"
        VIDEO = "video"
      end
    end
  end
end
