# frozen_string_literal: true

require_relative "validator"

module Weaviate
  module Collections
    module Grpc
      UINT32_LEN = 4
      UINT64_LEN = 8

      # Cross-property AND was backported to the 1.37 and 1.38 branches after landing in 1.39.
      BM25_AND_CROSS_MIN_VERSIONS = [[1, 37, 15], [1, 38, 8], [1, 39, 0]].freeze
      BM25_AND_CROSS_MIN_VERSIONS_STR = BM25_AND_CROSS_MIN_VERSIONS.map { |v| v.join(".") }.join(" or ")

      NESTED_LIST_MSG = "This input appears to be a nested list of embeddings.\n" \
                        "If you are trying to search with a multi-vector embedding, check the shape of your input.\n" \
                        "If you are trying to provide multiple target vectors,\n" \
                        "provide a dictionary with target names as keys and embeddings as values."

      # Python weaviate.util._get_vector_v4: normalise a vector-like input (Array or anything with #to_a)
      # into an Array; raises WeaviateInvalidInputError otherwise.
      def self.get_vector_v4(vector)
        ::Weaviate::Util.get_vector_v4(vector)
      end

      # Packs numbers as little-endian float32.
      def self.pack_floats(values)
        values.pack("e*")
      rescue TypeError, ArgumentError
        raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
              "The vector you supplied was malformatted! Vector:  #{values.inspect}"
      end

      # Python _is_1d_vector
      def self.is_1d_vector(inputs) # rubocop:disable Naming/PredicatePrefix
        return false unless Validator.list_like?(inputs) && inputs.size.positive?

        !Validator.list_like?(inputs.to_a[0])
      end

      # Python _is_2d_vector
      def self.is_2d_vector(inputs) # rubocop:disable Naming/PredicatePrefix
        return false unless Validator.list_like?(inputs) && inputs.size.positive?

        is_1d_vector(inputs.to_a[0])
      end

      # Python _ByteOps: little-endian decoding of the packed arrays Weaviate returns.
      module ByteOps
        module_function

        def decode_float32s(byte_vector) = byte_vector.to_s.unpack("e*")
        def decode_float64s(byte_vector) = byte_vector.to_s.unpack("E*")
        def decode_int64s(byte_vector) = byte_vector.to_s.unpack("q<*")
      end

      # Python _Packing
      Packing = Struct.new(:bytes_, :type_, keyword_init: true)

      # Python _Pack: encodes vectors for the gRPC API (float32 little-endian; multi-vectors are
      # prefixed with their uint16 dimension).
      module Pack
        module_function

        def parse_single_or_multi_vec(vector)
          if Grpc.is_2d_vector(vector)
            Packing.new(bytes_: multi(vector), type_: :VECTOR_TYPE_MULTI_FP32)
          elsif Grpc.is_1d_vector(vector)
            Packing.new(bytes_: single(vector), type_: :VECTOR_TYPE_SINGLE_FP32)
          else
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid vectors: #{vector.inspect}"
          end
        end

        def single(vector)
          Grpc.pack_floats(Grpc.get_vector_v4(vector))
        end

        def multi(vector)
          rows = vector.to_a.map { |v| Grpc.get_vector_v4(v) }
          [rows[0].length].pack("v") + Grpc.pack_floats(rows.flatten)
        end
      end

      # Python _Unpack
      module Unpack
        module_function

        def single(byte_vector) = ByteOps.decode_float32s(byte_vector)

        def multi(byte_vector)
          byte_vector = byte_vector.to_s.b
          dim = byte_vector[0, 2].unpack1("v")
          rest = byte_vector[2..] || "".b
          return [] if dim.nil? || dim.zero?

          how_many = rest.bytesize / (dim * UINT32_LEN)
          Array.new(how_many) { |i| ByteOps.decode_float32s(rest[i * dim * UINT32_LEN, dim * UINT32_LEN]) }
        end
      end

      # Port of weaviate.collections.grpc.shared._BaseGRPC. Holds the protobuf builders shared by the
      # query and aggregate request builders (near vector/text/object/media, hybrid, bm25 operator,
      # target vectors). Subclass it (e.g. an aggregate builder) or instantiate it directly:
      #
      #   base = BaseGRPC.new(weaviate_version: conn.weaviate_version, consistency_level: nil,
      #                       validate_arguments: true)
      #   base.parse_near_vector([0.1, 0.2], nil, nil, nil)   # => Weaviate::V1::NearVector
      class BaseGRPC
        Q = ::Weaviate::Classes::Query

        CONSISTENCY_LEVELS = {
          "ONE" => :CONSISTENCY_LEVEL_ONE,
          "QUORUM" => :CONSISTENCY_LEVEL_QUORUM,
          "ALL" => :CONSISTENCY_LEVEL_ALL
        }.freeze

        attr_reader :weaviate_version, :consistency_level, :validate_arguments

        def initialize(weaviate_version:, consistency_level: nil, validate_arguments: true)
          @weaviate_version = weaviate_version
          @consistency_level = self.class.get_consistency_level(consistency_level)
          @validate_arguments = validate_arguments
        end

        # ConsistencyLevel ("ONE"/"QUORUM"/"ALL", or anything responding to #value) -> protobuf enum Symbol.
        def self.get_consistency_level(consistency_level)
          return nil if consistency_level.nil?

          value = consistency_level.respond_to?(:value) ? consistency_level.value : consistency_level
          CONSISTENCY_LEVELS.fetch(value.to_s.upcase) do
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid consistency level: #{consistency_level}"
          end
        end

        # BM25OperatorOptions -> Weaviate::V1::SearchOperatorOptions
        def bm25_operator_to_grpc(bm25_operator)
          return nil if bm25_operator.nil?

          if bm25_operator.is_a?(Q::BM25OperatorAndCross) &&
             !@weaviate_version.is_at_least_any(*BM25_AND_CROSS_MIN_VERSIONS)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
              "BM25Operator.and_cross()", @weaviate_version.to_s, BM25_AND_CROSS_MIN_VERSIONS_STR
            )
          end

          ::Weaviate::V1::SearchOperatorOptions.new(
            operator: bm25_operator.operator,
            minimum_or_tokens_match: bm25_operator.is_a?(Q::BM25OperatorOr) ? bm25_operator.minimum_should_match : nil
          )
        end

        # Python __target_vector_to_grpc: returns [Weaviate::V1::Targets or nil, nil]
        def target_vector_to_grpc(target_vector)
          return [nil, nil] if target_vector.nil?

          case target_vector
          when String, Symbol then [::Weaviate::V1::Targets.new(target_vectors: [target_vector.to_s]), nil]
          when Array then [::Weaviate::V1::Targets.new(target_vectors: target_vector.map(&:to_s)), nil]
          else [target_vector.to_grpc_target_vector(@weaviate_version), nil]
          end
        end

        # Reorder the targets so they match the order of the given vectors.
        def recompute_target_vector_to_grpc(target_vector, target_vectors_tmp)
          if target_vector.is_a?(Q::MultiTargetVectorJoin)
            weights = target_vector.weights
            weights = target_vectors_tmp.uniq.to_h { |t| [t, lookup_weight(weights, t)] } unless weights.nil?
            target_vector = target_vector.with(target_vectors: target_vectors_tmp, weights: weights)
          else
            target_vector = target_vectors_tmp
          end
          target_vector_to_grpc(target_vector)
        end

        # @deprecated in 1.27.0, included for BC until 1.27.0 is no longer supported.
        # Returns [vector_per_target Hash or nil, vector_bytes or nil]
        def vector_per_target(vector, targets, argument_name)
          invalid = invalid_vector_error(argument_name, vector, nil, multi_target: false)
          if vector.is_a?(Hash)
            if targets.nil? || targets.target_vectors.length != vector.length
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "The number of target vectors must be equal to the number of vectors."
            end
            check_vector_keys(vector, targets, argument_name)

            per_target = {}
            vector.each do |key, value|
              nv = Grpc.get_vector_v4(value)
              raise invalid if !nv.is_a?(Array) || nv.empty? || !nv[0].is_a?(Numeric)

              per_target[key.to_s] = Grpc.pack_floats(nv)
            end
            [per_target, nil]
          else
            raise invalid if vector.is_a?(Q::ListOfVectorsQuery) || !Validator.list_like?(vector) || vector.size.zero?
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, NESTED_LIST_MSG unless Grpc.is_1d_vector(vector)

            [nil, Pack.single(vector)]
          end
        end

        # Returns [Array<Weaviate::V1::VectorForTarget> or nil, vector_bytes or nil, target names or nil]
        def vector_for_target(vector, targets, argument_name)
          invalid = invalid_vector_error(argument_name, vector, targets, multi_target: true)
          vector_for_target = []
          target_vectors = []

          add_1d = lambda do |val, key|
            vec = Grpc.get_vector_v4(val)
            raise invalid if !vec.is_a?(Array) || vec.empty? || !vec[0].is_a?(Numeric)

            vector_for_target << if @weaviate_version.is_lower_than(1, 29, 0)
                                   ::Weaviate::V1::VectorForTarget.new(name: key, vector_bytes: Pack.single(vec))
                                 else
                                   ::Weaviate::V1::VectorForTarget.new(
                                     name: key,
                                     vectors: [::Weaviate::V1::Vectors.new(name: key, vector_bytes: Pack.single(vec),
                                                                           type: :VECTOR_TYPE_SINGLE_FP32)]
                                   )
                                 end
            target_vectors << key
          end

          add_2d = lambda do |value, key|
            if @weaviate_version.is_lower_than(1, 29, 0)
              value.to_a.each { |v| add_1d.call(v, key) }
              next
            end
            vector_for_target << ::Weaviate::V1::VectorForTarget.new(
              name: key,
              vectors: [::Weaviate::V1::Vectors.new(name: key, vector_bytes: Pack.multi(value),
                                                    type: :VECTOR_TYPE_MULTI_FP32)]
            )
            target_vectors << key
          end

          add_list_of_vectors = lambda do |value, key|
            if value.one_dimensional? && @weaviate_version.is_lower_than(1, 29, 0)
              value.vectors.each { |v| add_1d.call(v, key) }
              next
            end
            vectors =
              if value.one_dimensional?
                [::Weaviate::V1::Vectors.new(name: key, vector_bytes: Pack.multi(value.vectors),
                                             type: :VECTOR_TYPE_MULTI_FP32)]
              elsif value.two_dimensional?
                value.vectors.map do |vecs|
                  ::Weaviate::V1::Vectors.new(name: key, vector_bytes: Pack.multi(vecs), type: :VECTOR_TYPE_MULTI_FP32)
                end
              else
                raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid list of vectors: #{value.inspect}"
              end
            vector_for_target << ::Weaviate::V1::VectorForTarget.new(name: key, vectors: vectors)
            target_vectors << key
          end

          if vector.is_a?(Hash)
            raise invalid if vector.empty? || targets.nil?

            check_vector_keys(vector, targets, argument_name)
            vector.each do |key, value|
              key = key.to_s
              if Grpc.is_1d_vector(value)
                add_1d.call(value, key)
              elsif Grpc.is_2d_vector(value)
                add_2d.call(value, key)
              elsif value.is_a?(Q::ListOfVectorsQuery)
                add_list_of_vectors.call(value, key)
              else
                raise invalid
              end
            end
            [vector_for_target, nil, target_vectors]
          else
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, NESTED_LIST_MSG unless Grpc.is_1d_vector(vector)

            [nil, Pack.single(vector), nil]
          end
        end

        # Validates and converts certainty/distance to Floats.
        def parse_near_options(certainty = nil, distance = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([Float, Integer, nil], "certainty", certainty),
                                       Validator.arg([Float, Integer, nil], "distance", distance)
                                     ])
          end
          [certainty&.to_f, distance&.to_f]
        end

        # MMR -> Weaviate::V1::Selection
        def self.diversity_selection_to_grpc(diversity_selection)
          return nil if diversity_selection.nil?

          ::Weaviate::V1::Selection.new(
            mmr: ::Weaviate::V1::Selection::MMR.new(limit: diversity_selection.limit,
                                                    balance: diversity_selection.balance&.to_f)
          )
        end

        def diversity_selection_to_grpc(diversity_selection) = self.class.diversity_selection_to_grpc(diversity_selection)

        # -> Weaviate::V1::NearVector
        def parse_near_vector(near_vector, certainty, distance, target_vector, diversity_selection = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([:list, :hash], "near_vector", near_vector),
                                       Validator.arg([String, Symbol, nil, :list, Q::MultiTargetVectorJoin],
                                                     "target_vector", target_vector)
                                     ])
          end
          certainty, distance = parse_near_options(certainty, distance)
          targets, target_vectors = target_vector_to_grpc(target_vector)

          near_vector_grpc = nil
          vector_per_target_tmp = nil
          vector_for_targets = nil
          vectors = nil
          if Grpc.is_1d_vector(near_vector)
            if @weaviate_version.is_lower_than(1, 29, 0)
              near_vector_grpc = Pack.single(near_vector)
            else
              vectors = [::Weaviate::V1::Vectors.new(vector_bytes: Pack.single(near_vector),
                                                     type: :VECTOR_TYPE_SINGLE_FP32)]
            end
          elsif Grpc.is_2d_vector(near_vector) && @weaviate_version.is_at_least(1, 29, 0)
            vectors = [::Weaviate::V1::Vectors.new(vector_bytes: Pack.multi(near_vector),
                                                   type: :VECTOR_TYPE_MULTI_FP32)]
          elsif @weaviate_version.is_lower_than(1, 27, 0)
            vector_per_target_tmp, near_vector_grpc = vector_per_target(near_vector, targets, "near_vector")
          else
            vector_for_targets, near_vector_grpc, target_vectors_tmp = vector_for_target(near_vector, targets,
                                                                                         "near_vector")
            unless target_vectors_tmp.nil?
              targets, target_vectors = recompute_target_vector_to_grpc(target_vector, target_vectors_tmp)
            end
          end

          ::Weaviate::V1::NearVector.new(
            vector_bytes: near_vector_grpc,
            certainty: certainty,
            distance: distance,
            targets: targets,
            target_vectors: target_vectors,
            vector_per_target: vector_per_target_tmp,
            vector_for_targets: vector_for_targets,
            vectors: vectors,
            selection: diversity_selection_to_grpc(diversity_selection)
          )
        end

        def self.parse_move(move)
          return nil if move.nil?

          ::Weaviate::V1::NearTextSearch::Move.new(force: Float(move.force), concepts: move.concepts_list,
                                                   uuids: move.objects_list)
        end

        # -> Weaviate::V1::NearTextSearch
        def parse_near_text(near_text, certainty, distance, move_to, move_away, target_vector,
                            diversity_selection = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([:list, String], "near_text", near_text),
                                       Validator.arg([Q::Move, nil], "move_away", move_away),
                                       Validator.arg([Q::Move, nil], "move_to", move_to),
                                       Validator.arg([String, Symbol, :list, Q::MultiTargetVectorJoin, nil],
                                                     "target_vector", target_vector)
                                     ])
          end
          near_text = [near_text] if near_text.is_a?(String)
          certainty, distance = parse_near_options(certainty, distance)
          targets, target_vectors = target_vector_to_grpc(target_vector)

          ::Weaviate::V1::NearTextSearch.new(
            query: near_text.to_a,
            certainty: certainty,
            distance: distance,
            move_away: self.class.parse_move(move_away),
            move_to: self.class.parse_move(move_to),
            targets: targets,
            target_vectors: target_vectors,
            selection: diversity_selection_to_grpc(diversity_selection)
          )
        end

        # -> Weaviate::V1::NearObject
        def parse_near_object(near_object, certainty, distance, target_vector, diversity_selection = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([String], "near_object", near_object),
                                       Validator.arg([String, Symbol, nil, :list, Q::MultiTargetVectorJoin],
                                                     "target_vector", target_vector)
                                     ])
          end
          certainty, distance = parse_near_options(certainty, distance)
          targets, target_vectors = target_vector_to_grpc(target_vector)

          ::Weaviate::V1::NearObject.new(
            id: near_object.to_s,
            certainty: certainty,
            distance: distance,
            targets: targets,
            target_vectors: target_vectors,
            selection: diversity_selection_to_grpc(diversity_selection)
          )
        end

        MEDIA_TYPES = {
          "audio" => [:near_audio, ::Weaviate::V1::NearAudioSearch, :audio],
          "depth" => [:near_depth, ::Weaviate::V1::NearDepthSearch, :depth],
          "image" => [:near_image, ::Weaviate::V1::NearImageSearch, :image],
          "imu" => [:near_imu, ::Weaviate::V1::NearIMUSearch, :imu],
          "thermal" => [:near_thermal, ::Weaviate::V1::NearThermalSearch, :thermal],
          "video" => [:near_video, ::Weaviate::V1::NearVideoSearch, :video]
        }.freeze

        # Returns a one-entry Hash { near_<type>: Weaviate::V1::Near<Type>Search } to splat into a request.
        def parse_media(media, type_, certainty, distance, target_vector, diversity_selection = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([String], "media", media),
                                       Validator.arg([String, Symbol, nil, :list, Q::MultiTargetVectorJoin],
                                                     "target_vector", target_vector)
                                     ])
          end
          certainty, distance = parse_near_options(certainty, distance)
          targets, target_vectors = target_vector_to_grpc(target_vector)

          field, klass, media_field = MEDIA_TYPES.fetch(type_.to_s) do
            raise ArgumentError, "type_ must be one of ['audio', 'depth', 'image', 'imu', 'thermal', 'video'], " \
                                 "but got #{type_}"
          end
          { field => klass.new(media_field => media, distance: distance, certainty: certainty,
                               target_vectors: target_vectors, targets: targets,
                               selection: diversity_selection_to_grpc(diversity_selection)) }
        end

        # -> Weaviate::V1::Hybrid or nil (when neither query nor vector are given)
        def parse_hybrid(query, alpha, vector, properties, bm25_operator, fusion_type, distance, target_vector,
                         diversity_selection = nil)
          if @validate_arguments
            Validator.validate_input([
                                       Validator.arg([nil, String], "query", query),
                                       Validator.arg([Float, Integer, nil], "alpha", alpha),
                                       Validator.arg([:list, :hash, Q::HybridNearText, Q::HybridNearVector, nil],
                                                     "vector", vector),
                                       Validator.arg([:list, nil], "properties", properties),
                                       Validator.arg([Q::HybridFusion, nil], "fusion_type", fusion_type),
                                       Validator.arg([String, Symbol, nil, :list, Q::MultiTargetVectorJoin],
                                                     "target_vector", target_vector)
                                     ])
          end

          # Set hybrid search to only query the other search-type if one of the two is not set
          alpha = 1 if query.nil?

          targets, target_vectors = target_vector_to_grpc(target_vector)
          near_text = near_vector = vector_bytes = vectors = nil

          if vector.nil?
            # nothing to do
          elsif vector.is_a?(Array) && !vector.empty? && vector[0].is_a?(Float)
            vector_bytes = Grpc.pack_floats(vector) # fast path for simple vector
          elsif Grpc.is_2d_vector(vector) && @weaviate_version.is_at_least(1, 29, 0)
            vectors = [::Weaviate::V1::Vectors.new(vector_bytes: Pack.multi(vector), type: :VECTOR_TYPE_MULTI_FP32)]
          elsif vector.is_a?(Q::HybridNearText)
            near_text = ::Weaviate::V1::NearTextSearch.new(
              query: vector.text.is_a?(String) ? [vector.text] : vector.text.to_a,
              certainty: vector.certainty&.to_f,
              distance: vector.distance&.to_f,
              move_away: self.class.parse_move(vector.move_away),
              move_to: self.class.parse_move(vector.move_to)
            )
          elsif vector.is_a?(Q::HybridNearVector)
            vector_per_target_tmp = vector_for_targets_tmp = nil
            if @weaviate_version.is_lower_than(1, 27, 0)
              vector_per_target_tmp, vector_bytes_tmp = vector_per_target(vector.vector, targets, "vector")
            else
              vector_for_targets_tmp, vector_bytes_tmp, target_vectors_tmp = vector_for_target(vector.vector, targets,
                                                                                               "vector")
              unless target_vectors_tmp.nil?
                targets, target_vectors = recompute_target_vector_to_grpc(target_vector, target_vectors_tmp)
              end
            end
            near_vector = ::Weaviate::V1::NearVector.new(
              vector_bytes: vector_bytes_tmp,
              certainty: vector.certainty&.to_f,
              distance: vector.distance&.to_f,
              vector_per_target: vector_per_target_tmp,
              vector_for_targets: vector_for_targets_tmp
            )
          else
            vector_per_target_tmp = vector_for_targets_tmp = nil
            if @weaviate_version.is_lower_than(1, 27, 0)
              vector_per_target_tmp, vector_bytes_tmp = vector_per_target(vector, targets, "vector")
            else
              vector_for_targets_tmp, vector_bytes_tmp, target_vectors_tmp = vector_for_target(vector, targets,
                                                                                               "vector")
              targets, target_vectors = if target_vectors_tmp.nil?
                                          target_vector_to_grpc(target_vector)
                                        else
                                          recompute_target_vector_to_grpc(target_vector, target_vectors_tmp)
                                        end
            end
            if vector_per_target_tmp || vector_for_targets_tmp
              near_vector = ::Weaviate::V1::NearVector.new(vector_bytes: vector_bytes_tmp,
                                                           vector_per_target: vector_per_target_tmp,
                                                           vector_for_targets: vector_for_targets_tmp)
            else
              vector_bytes = vector_bytes_tmp
            end
          end

          return nil if query.nil? && vector.nil?

          use_alpha_param = @weaviate_version.is_at_least(1, 36, 6)
          alpha_value = alpha.nil? ? nil : alpha.to_f
          ::Weaviate::V1::Hybrid.new(
            properties: properties,
            query: query,
            alpha: use_alpha_param ? nil : (alpha_value || 0.7),
            alpha_param: use_alpha_param ? alpha_value : nil,
            use_alpha_param: use_alpha_param,
            fusion_type: fusion_type&.to_sym,
            target_vectors: target_vectors,
            targets: targets,
            near_text: near_text,
            near_vector: near_vector,
            vector_bytes: vector_bytes,
            vector_distance: distance&.to_f,
            vectors: vectors,
            selection: diversity_selection_to_grpc(diversity_selection),
            bm25_search_operator: bm25_operator_to_grpc(bm25_operator)
          )
        end

        private

        def lookup_weight(weights, target)
          weights.fetch(target) { weights.fetch(target.to_sym) }
        end

        def check_vector_keys(vector, targets, argument_name)
          target_names = targets.target_vectors.to_a.uniq.sort
          keys = vector.keys.map(&:to_s)
          return if target_names == keys.uniq.sort

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "The #{argument_name} keys #{keys.sort} must match the target vectors #{target_names}"
        end

        def invalid_vector_error(argument_name, vector, targets, multi_target:)
          msg = if multi_target
                  "#{argument_name} argument can be:\n- a list of numbers\n- a dictionary with target names as keys " \
                    "and lists of numbers as values for multi target search. The keys must match the given target " \
                    "vectors\nreceived: #{vector.inspect} and #{targets.inspect}."
                else
                  "#{argument_name} argument can be:\n- a list of numbers\n- a dictionary with target names as keys " \
                    "and lists of numbers as values\nreceived: #{vector.inspect}"
                end
          ::Weaviate::Exceptions::WeaviateInvalidInputError.new(msg)
        end
      end
    end
  end
end
