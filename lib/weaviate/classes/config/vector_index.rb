# frozen_string_literal: true

require_relative "base"
require_relative "enums"
require_relative "fields"

# Port of weaviate/collections/classes/config_vector_index.py
module Weaviate
  module Classes
    module Config
      # _MultiVectorConfigCreateBase
      class MultiVectorConfigCreateBase < ConfigCreateModel
        include Fields

        field :enabled, :bool, default: true
      end

      # _MultiVectorEncodingConfigCreate
      class MultiVectorEncodingConfigCreate < MultiVectorConfigCreateBase
        def self.encoding_name
          raise NotImplementedError
        end

        def encoding_name = self.class.encoding_name
      end

      # _MuveraConfigCreate
      class MuveraConfigCreate < MultiVectorEncodingConfigCreate
        field :ksim, :int
        field :dprojections, :int
        field :repetitions, :int

        def self.encoding_name = "muvera"
      end

      # _MultiVectorConfigCreate
      class MultiVectorConfigCreate < MultiVectorConfigCreateBase
        field :encoding, MultiVectorEncodingConfigCreate, exclude: true
        field :aggregation, :str
      end

      # _UncompressedConfigCreate is referenced in VectorIndexConfigCreate#to_dict, defined below.

      # VectorIndexConfigCreate
      class VectorIndexConfigCreate < ConfigCreateModel
        include Fields

        field :distance, "VectorDistances"
        field :multivector, MultiVectorConfigCreate
        field :quantizer, QuantizerConfigCreate, exclude: true

        def self.vector_index_type
          raise NotImplementedError
        end

        def vector_index_type = self.class.vector_index_type

        def to_dict
          ret_dict = super
          unless quantizer.nil?
            ret_dict[quantizer.class.quantizer_name] =
              quantizer.is_a?(UncompressedConfigCreate) ? true : quantizer.to_dict
          end
          ret_dict["distance"] = distance.to_s unless distance.nil?
          if !multivector.nil? && !multivector.encoding.nil?
            ret_dict["multivector"][multivector.encoding.class.encoding_name] = multivector.encoding.to_dict
          end
          ret_dict
        end
      end

      # VectorIndexConfigUpdate
      class VectorIndexConfigUpdate < ConfigUpdateModel
        include Fields

        field :quantizer, QuantizerConfigUpdate, exclude: true

        def self.vector_index_type
          raise NotImplementedError
        end

        def vector_index_type = self.class.vector_index_type
      end

      # VectorIndexConfigSkipCreate
      class VectorIndexConfigSkipCreate < VectorIndexConfigCreate
        field :skip, :bool, default: true

        def self.vector_index_type = VectorIndexType::HNSW
      end

      # VectorIndexConfigHNSWCreate
      class VectorIndexConfigHNSWCreate < VectorIndexConfigCreate
        field :cleanupIntervalSeconds, :int
        field :dynamicEfMin, :int
        field :dynamicEfMax, :int
        field :dynamicEfFactor, :int
        field :efConstruction, :int
        field :ef, :int
        field :filterStrategy, VectorFilterStrategy
        field :flatSearchCutoff, :int
        field :maxConnections, :int
        field :vectorCacheMaxObjects, :int

        def self.vector_index_type = VectorIndexType::HNSW
      end

      # VectorIndexConfigHFreshCreate
      class VectorIndexConfigHFreshCreate < VectorIndexConfigCreate
        field :maxPostingSizeKB, :int
        field :replicas, :int
        field :searchProbe, :int

        def self.vector_index_type = VectorIndexType::HFRESH
      end

      # VectorIndexConfigFlatCreate
      class VectorIndexConfigFlatCreate < VectorIndexConfigCreate
        field :vectorCacheMaxObjects, :int

        def self.vector_index_type = VectorIndexType::FLAT
      end

      # VectorIndexConfigHNSWUpdate
      class VectorIndexConfigHNSWUpdate < VectorIndexConfigUpdate
        field :dynamicEfMin, :int
        field :dynamicEfMax, :int
        field :dynamicEfFactor, :int
        field :ef, :int
        field :filterStrategy, VectorFilterStrategy
        field :flatSearchCutoff, :int
        field :vectorCacheMaxObjects, :int

        def self.vector_index_type = VectorIndexType::HNSW
      end

      # VectorIndexConfigHFreshUpdate
      class VectorIndexConfigHFreshUpdate < VectorIndexConfigUpdate
        field :maxPostingSizeKB, :int
        field :searchProbe, :int

        def self.vector_index_type = VectorIndexType::HFRESH
      end

      # VectorIndexConfigFlatUpdate
      class VectorIndexConfigFlatUpdate < VectorIndexConfigUpdate
        field :vectorCacheMaxObjects, :int

        def self.vector_index_type = VectorIndexType::FLAT
      end

      # VectorIndexConfigDynamicCreate
      class VectorIndexConfigDynamicCreate < VectorIndexConfigCreate
        field :threshold, :int
        field :hnsw, VectorIndexConfigHNSWCreate
        field :flat, VectorIndexConfigFlatCreate

        def self.vector_index_type = VectorIndexType::DYNAMIC

        def to_dict
          ret_dict = super
          ret_dict["hnsw"] = hnsw.to_dict unless hnsw.nil?
          ret_dict["flat"] = flat.to_dict unless flat.nil?
          ret_dict["threshold"] = threshold unless threshold.nil?
          ret_dict
        end
      end

      # VectorIndexConfigDynamicUpdate
      class VectorIndexConfigDynamicUpdate < VectorIndexConfigUpdate
        field :threshold, :int
        field :hnsw, VectorIndexConfigHNSWUpdate
        field :flat, VectorIndexConfigFlatUpdate

        def self.vector_index_type = VectorIndexType::DYNAMIC
      end

      # _PQEncoderConfigCreate. NOTE: like the Python client (pydantic `serialization_alias` is not
      # applied by `model_dump()`), the encoder type is dumped under the key "type_".
      class PQEncoderConfigCreate < ConfigCreateModel
        include Fields

        field :type_, PQEncoderType
        field :distribution, PQEncoderDistribution
      end

      # _PQEncoderConfigUpdate
      class PQEncoderConfigUpdate < ConfigUpdateModel
        include Fields

        field :type_, PQEncoderType
        field :distribution, PQEncoderDistribution

        def merge_with_existing(schema)
          schema["type"] = type_.to_s unless type_.nil?
          schema["distribution"] = distribution.to_s unless distribution.nil?
          schema
        end
      end

      # _PQConfigCreate
      class PQConfigCreate < QuantizerConfigCreate
        include Fields

        field :enabled, :bool, default: true
        field :bitCompression, :bool
        field :centroids, :int
        field :encoder, PQEncoderConfigCreate, required: true
        field :segments, :int
        field :trainingLimit, :int

        def self.quantizer_name = "pq"
      end

      # _BQConfigCreate
      class BQConfigCreate < QuantizerConfigCreate
        include Fields

        field :enabled, :bool, default: true
        field :cache, :bool
        field :rescoreLimit, :int

        def self.quantizer_name = "bq"
      end

      # _SQConfigCreate
      class SQConfigCreate < QuantizerConfigCreate
        include Fields

        field :enabled, :bool, default: true
        field :rescoreLimit, :int
        field :trainingLimit, :int

        def self.quantizer_name = "sq"
      end

      # _RQConfigCreate
      class RQConfigCreate < QuantizerConfigCreate
        include Fields

        field :enabled, :bool, default: true
        field :cache, :bool
        field :bits, :int
        field :rescoreLimit, :int
        field :centering, :bool
        field :trainingLimit, :int

        def self.quantizer_name = "rq"
      end

      # _UncompressedConfigCreate
      class UncompressedConfigCreate < QuantizerConfigCreate
        include Fields

        field :enabled, :bool, default: true

        def self.quantizer_name = "skipDefaultQuantization"
      end

      # _PQConfigUpdate
      class PQConfigUpdate < QuantizerConfigUpdate
        include Fields

        field :bitCompression, :bool
        field :centroids, :int
        field :enabled, :bool
        field :segments, :int
        field :trainingLimit, :int
        field :encoder, PQEncoderConfigUpdate

        def self.quantizer_name = "pq"
      end

      # _BQConfigUpdate
      class BQConfigUpdate < QuantizerConfigUpdate
        include Fields

        field :enabled, :bool
        field :rescoreLimit, :int

        def self.quantizer_name = "bq"
      end

      # _RQConfigUpdate
      class RQConfigUpdate < QuantizerConfigUpdate
        include Fields

        field :enabled, :bool
        field :rescoreLimit, :int
        field :bits, :int
        field :centering, :bool
        field :trainingLimit, :int

        def self.quantizer_name = "rq"
      end

      # _SQConfigUpdate
      class SQConfigUpdate < QuantizerConfigUpdate
        include Fields

        field :enabled, :bool
        field :rescoreLimit, :int
        field :trainingLimit, :int

        def self.quantizer_name = "sq"
      end

      # _VectorIndexMultivectorEncoding (Configure.VectorIndex.MultiVector.Encoding)
      module VectorIndexMultivectorEncoding
        def self.muvera(ksim: nil, dprojections: nil, repetitions: nil)
          MuveraConfigCreate.new(enabled: true, ksim: ksim, dprojections: dprojections, repetitions: repetitions)
        end
      end

      # _VectorIndexMultiVector (Configure.VectorIndex.MultiVector)
      module VectorIndexMultiVector
        Encoding = VectorIndexMultivectorEncoding

        def self.multi_vector(encoding: nil, aggregation: nil)
          ::Weaviate::Warnings.encoding_in_multi_vector_config unless encoding.nil?
          MultiVectorConfigCreate.new(encoding: encoding, aggregation: aggregation&.to_s)
        end
      end

      # _VectorIndexQuantizer (Configure.VectorIndex.Quantizer)
      module VectorIndexQuantizer
        def self.pq(bit_compression: nil, centroids: nil, encoder_distribution: nil, encoder_type: nil, segments: nil,
                    training_limit: nil)
          ::Weaviate::Warnings.bit_compression_in_pq_config unless bit_compression.nil?
          PQConfigCreate.new(
            centroids: centroids,
            segments: segments,
            trainingLimit: training_limit,
            encoder: PQEncoderConfigCreate.new(type_: encoder_type, distribution: encoder_distribution)
          )
        end

        def self.bq(cache: nil, rescore_limit: nil)
          BQConfigCreate.new(cache: cache, rescoreLimit: rescore_limit)
        end

        # `cache` is not supported by SQ and is ignored (deprecated in Python).
        def self.sq(cache: nil, rescore_limit: nil, training_limit: nil) # rubocop:disable Lint/UnusedMethodArgument
          SQConfigCreate.new(rescoreLimit: rescore_limit, trainingLimit: training_limit)
        end

        def self.rq(cache: nil, bits: nil, rescore_limit: nil, centering: nil, training_limit: nil)
          RQConfigCreate.new(cache: cache, bits: bits, rescoreLimit: rescore_limit, centering: centering,
                             trainingLimit: training_limit)
        end

        def self.none
          UncompressedConfigCreate.new
        end
      end

      # _VectorIndex (Configure.VectorIndex)
      module VectorIndex
        MultiVector = VectorIndexMultiVector
        Quantizer = VectorIndexQuantizer

        def self.none
          VectorIndexConfigSkipCreate.new(distance: nil, quantizer: nil, multivector: nil)
        end

        def self.hnsw(cleanup_interval_seconds: nil, distance_metric: nil, dynamic_ef_factor: nil, dynamic_ef_max: nil,
                      dynamic_ef_min: nil, ef: nil, ef_construction: nil, filter_strategy: nil,
                      flat_search_cutoff: nil, max_connections: nil, vector_cache_max_objects: nil, quantizer: nil,
                      multi_vector: nil)
          ::Weaviate::Warnings.multi_vector_in_hnsw_config unless multi_vector.nil?
          VectorIndexConfigHNSWCreate.new(
            cleanupIntervalSeconds: cleanup_interval_seconds,
            distance: distance_metric,
            dynamicEfMin: dynamic_ef_min,
            dynamicEfMax: dynamic_ef_max,
            dynamicEfFactor: dynamic_ef_factor,
            efConstruction: ef_construction,
            ef: ef,
            filterStrategy: filter_strategy,
            flatSearchCutoff: flat_search_cutoff,
            maxConnections: max_connections,
            vectorCacheMaxObjects: vector_cache_max_objects,
            quantizer: quantizer,
            multivector: multi_vector
          )
        end

        def self.hfresh(distance_metric: nil, max_posting_size_kb: nil, replicas: nil, search_probe: nil, quantizer: nil,
                        multi_vector: nil)
          VectorIndexConfigHFreshCreate.new(
            distance: distance_metric,
            maxPostingSizeKB: max_posting_size_kb,
            replicas: replicas,
            searchProbe: search_probe,
            quantizer: quantizer,
            multivector: multi_vector
          )
        end

        def self.flat(distance_metric: nil, vector_cache_max_objects: nil, quantizer: nil)
          VectorIndexConfigFlatCreate.new(
            distance: distance_metric,
            vectorCacheMaxObjects: vector_cache_max_objects,
            quantizer: quantizer,
            multivector: nil
          )
        end

        def self.dynamic(distance_metric: nil, threshold: nil, hnsw: nil, flat: nil)
          VectorIndexConfigDynamicCreate.new(
            distance: distance_metric,
            threshold: threshold,
            hnsw: hnsw,
            flat: flat,
            quantizer: nil,
            multivector: nil
          )
        end
      end
    end
  end
end
