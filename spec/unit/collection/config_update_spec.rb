# frozen_string_literal: true

# Port of test/collection/test_config_update.py
RSpec.describe "collection config update" do # rubocop:disable RSpec/DescribeClass
  c = Weaviate::Classes::Config
  invalid_input = Weaviate::Exceptions::WeaviateInvalidInputError

  # Port of test/collection/schema.py::multi_vector_schema
  def self.vector_index_config(quantizer)
    {
      "skip" => false,
      "cleanupIntervalSeconds" => 300,
      "maxConnections" => 32,
      "efConstruction" => 128,
      "ef" => -1,
      "dynamicEfMin" => 100,
      "dynamicEfMax" => 500,
      "dynamicEfFactor" => 8,
      "vectorCacheMaxObjects" => 1_000_000_000_000,
      "flatSearchCutoff" => 40_000,
      "distance" => "cosine",
      "pq" => {
        "enabled" => quantizer == "pq",
        "bitCompression" => false,
        "segments" => 0,
        "centroids" => 256,
        "trainingLimit" => 100_000,
        "encoder" => { "type" => "kmeans", "distribution" => "log-normal" }
      },
      "bq" => { "enabled" => quantizer == "bq" },
      "sq" => { "enabled" => quantizer == "sq", "trainingLimit" => 100_000, "rescoreLimit" => 20 },
      "rq" => { "enabled" => quantizer == "rq", "bits" => 8, "rescoreLimit" => 20 }
    }
  end

  def self.multi_vector_schema(quantizer = nil)
    {
      "class" => "Something",
      "invertedIndexConfig" => {
        "bm25" => { "b" => 0.75, "k1" => 1.2 },
        "cleanupIntervalSeconds" => 60,
        "stopwords" => { "additions" => nil, "preset" => "en", "removals" => nil }
      },
      "multiTenancyConfig" => { "autoTenantActivation" => false, "autoTenantCreation" => false, "enabled" => false },
      "properties" => [
        {
          "dataType" => ["text"],
          "indexFilterable" => true,
          "indexRangeFilters" => false,
          "indexSearchable" => true,
          "name" => "name",
          "tokenization" => "word"
        }
      ],
      "replicationConfig" => { "asyncEnabled" => false, "factor" => 1 },
      "shardingConfig" => {
        "virtualPerPhysical" => 128,
        "desiredCount" => 1,
        "actualCount" => 1,
        "desiredVirtualCount" => 128,
        "actualVirtualCount" => 128,
        "key" => "_id",
        "strategy" => "hash",
        "function" => "murmur3"
      },
      "vectorConfig" => {
        "boi" => {
          "vectorIndexConfig" => vector_index_config(quantizer),
          "vectorIndexType" => "hnsw",
          "vectorizer" => { "none" => {} }
        },
        "yeh" => {
          "vectorIndexConfig" => vector_index_config(quantizer),
          "vectorIndexType" => "hnsw",
          "vectorizer" => { "none" => {} }
        }
      }
    }
  end

  def multi_vector_schema(quantizer = nil) = self.class.multi_vector_schema(quantizer)

  [[nil, nil], [0, 0], [120, 120]].each do |offset, expected|
    it "test_object_ttl_update_offset[#{offset.inspect}]" do
      update = c::Reconfigure::ObjectTTL.delete_by_date_property(filter_expired_objects: true, ttl_offset: offset)
      expect(update.defaultTtl).to eq(expected)
      merged = update.merge_with_existing(
        { "enabled" => true, "deleteOn" => "expiresAt", "defaultTtl" => 3600, "filterExpiredObjects" => false }
      )
      expect(merged["defaultTtl"]).to eq(expected.nil? ? 3600 : expected)
      expect(merged["filterExpiredObjects"]).to be(true)
    end
  end

  {
    "pq" => { quantizer: -> { c::Reconfigure::VectorIndex::Quantizer.pq }, conflicts: %w[bq sq] },
    "bq" => { quantizer: -> { c::Reconfigure::VectorIndex::Quantizer.bq }, conflicts: %w[pq sq] },
    "sq" => { quantizer: -> { c::Reconfigure::VectorIndex::Quantizer.sq }, conflicts: %w[pq bq] }
  }.each do |name, spec|
    [[nil, false], *spec[:conflicts].map { |q| [q, true] }].each do |existing, should_error|
      it "test_enabling_#{name}_multi_vector[#{existing.inspect}]" do
        schema = multi_vector_schema(existing)
        update = c::CollectionConfigUpdate.new(
          vectorizer_config: [
            c::Reconfigure::NamedVectors.update(
              "boi",
              vector_index_config: c::Reconfigure::VectorIndex.hnsw(quantizer: spec[:quantizer].call)
            )
          ]
        )
        if should_error
          expect { update.merge_with_existing(schema) }.to raise_error(invalid_input)
          next
        end

        new_schema = update.merge_with_existing(schema)
        %w[pq bq sq].each do |q|
          expect(new_schema["vectorConfig"]["boi"]["vectorIndexConfig"][q]["enabled"]).to be(q == name)
        end
        expect(new_schema["vectorConfig"]["yeh"]).to eq(multi_vector_schema["vectorConfig"]["yeh"])
      end
    end
  end

  it "test_replication_async_config_replace_on_update" do
    schema = { "factor" => 1, "asyncEnabled" => true, "asyncConfig" => { "maxWorkers" => 8, "hashtreeHeight" => 20 } }
    update = c::Reconfigure.replication(async_config: c::Reconfigure::Replication.async_config(max_workers: 16))
    result = update.merge_with_existing(schema)
    expect(result["asyncConfig"]).to eq({ "maxWorkers" => 16 })
    expect(result["asyncConfig"]).not_to have_key("hashtreeHeight")
  end

  it "test_replication_async_config_preserved_when_async_disabled" do
    schema = { "factor" => 1, "asyncEnabled" => true, "asyncConfig" => { "maxWorkers" => 8, "hashtreeHeight" => 20 } }
    result = c::Reconfigure.replication(async_enabled: false).merge_with_existing(schema)
    expect(result["asyncEnabled"]).to be(false)
    expect(result["asyncConfig"]).to eq({ "maxWorkers" => 8, "hashtreeHeight" => 20 })
  end

  it "test_replication_async_config_preserved_when_not_provided" do
    schema = { "factor" => 1, "asyncEnabled" => true, "asyncConfig" => { "maxWorkers" => 8, "hashtreeHeight" => 20 } }
    result = c::Reconfigure.replication(factor: 2).merge_with_existing(schema)
    expect(result["factor"]).to eq(2)
    expect(result["asyncConfig"]).to eq({ "maxWorkers" => 8, "hashtreeHeight" => 20 })
  end

  it "test_replication_async_config_reset_all_fields" do
    schema = { "factor" => 1, "asyncEnabled" => true, "asyncConfig" => { "maxWorkers" => 8, "hashtreeHeight" => 20 } }
    update = c::Reconfigure.replication(async_config: c::Reconfigure::Replication.async_config)
    expect(update.merge_with_existing(schema)["asyncConfig"]).to eq({})
  end

  describe "test_object_ttl_update_merges_into_objectTtlConfig" do
    cases = [
      [
        { "enabled" => true, "deleteOn" => "expiresAt", "defaultTtl" => 3600, "filterExpiredObjects" => false },
        -> { c::ObjectTTLConfigUpdate.new(enabled: true, filterExpiredObjects: true) },
        { "enabled" => true, "deleteOn" => "expiresAt", "defaultTtl" => 3600, "filterExpiredObjects" => true }
      ],
      [
        nil,
        -> { c::Reconfigure::ObjectTTL.delete_by_update_time(time_to_live: 3600) },
        { "enabled" => true, "deleteOn" => "_lastUpdateTimeUnix", "defaultTtl" => 3600 }
      ],
      [
        { "enabled" => true, "deleteOn" => "expiresAt", "defaultTtl" => 3600, "filterExpiredObjects" => false },
        -> { c::Reconfigure::ObjectTTL.disable },
        { "enabled" => false, "deleteOn" => "expiresAt", "defaultTtl" => 3600, "filterExpiredObjects" => false }
      ]
    ]

    cases.each_with_index do |(stored, update, expected), i|
      it "case #{i}" do
        schema = stored.nil? ? { "class" => "Test" } : { "class" => "Test", "objectTtlConfig" => stored }
        merged = c::CollectionConfigUpdate.new(object_ttl_config: update.call).merge_with_existing(schema)
        expect(merged).not_to have_key("objectTTLConfig")
        expect(merged["objectTtlConfig"]).to eq(expected)
      end
    end
  end

  # An HFresh schema, which mandates RQ and so carries no pq/bq/sq blocks.
  def hfresh_schema(rescore_limit = 20)
    {
      "class" => "HFreshRQ",
      "vectorConfig" => {
        "boi" => {
          "vectorizer" => { "text2vec-weaviate" => {} },
          "vectorIndexType" => "hfresh",
          "vectorIndexConfig" => {
            "distance" => "cosine",
            "maxPostingSizeKB" => 1024,
            "searchProbe" => 8,
            "rq" => { "enabled" => true, "bits" => 1, "rescoreLimit" => rescore_limit }
          }
        }
      }
    }
  end

  it "test_updating_rq_on_hfresh_without_pq_block" do
    schema = hfresh_schema
    update = c::CollectionConfigUpdate.new(
      vector_config: c::Reconfigure::Vectors.update(
        name: "boi",
        vector_index_config: c::Reconfigure::VectorIndex.hfresh(
          quantizer: c::Reconfigure::VectorIndex::Quantizer.rq(rescore_limit: 500)
        )
      )
    )
    new_schema = update.merge_with_existing(schema)
    expect(new_schema["vectorConfig"]["boi"]["vectorIndexConfig"]["rq"]["rescoreLimit"]).to eq(500)
    expect(new_schema["vectorConfig"]["boi"]["vectorIndexConfig"]["rq"]["enabled"]).to be_truthy
  end

  it "test_quantizer_check_tolerates_missing_pq_block" do
    update = c::CollectionConfigUpdate.new(
      vector_config: c::Reconfigure::Vectors.update(
        name: "boi",
        vector_index_config: c::Reconfigure::VectorIndex.hfresh(quantizer: c::Reconfigure::VectorIndex::Quantizer.rq)
      )
    )
    # No KeyError: rq is the quantizer already in use, so the update is allowed through.
    expect { update.merge_with_existing(hfresh_schema) }.not_to raise_error
  end

  it "test_switching_quantizer_still_rejected_when_pq_enabled" do
    update = c::CollectionConfigUpdate.new(
      vectorizer_config: [
        c::Reconfigure::NamedVectors.update(
          "boi",
          vector_index_config: c::Reconfigure::VectorIndex.hnsw(quantizer: c::Reconfigure::VectorIndex::Quantizer.rq)
        )
      ]
    )
    expect { update.merge_with_existing(multi_vector_schema("pq")) }.to raise_error(invalid_input)
  end

  [false, true].each do |use_deprecated_syntax|
    it "test_updating_dropped_vector_index[#{use_deprecated_syntax}]" do
      schema = multi_vector_schema
      # shape reported by Weaviate for a vector dropped via `config.delete_vector_index()`
      schema["vectorConfig"]["boi"] = { "vectorizer" => { "none" => {} }, "vectorIndexType" => "none" }

      hnsw = c::Reconfigure::VectorIndex.hnsw(ef: 128)
      update =
        if use_deprecated_syntax
          c::CollectionConfigUpdate.new(
            vectorizer_config: [c::Reconfigure::NamedVectors.update("boi", vector_index_config: hnsw)]
          )
        else
          c::CollectionConfigUpdate.new(
            vector_config: [c::Reconfigure::Vectors.update(name: "boi", vector_index_config: hnsw)]
          )
        end

      expect { update.merge_with_existing(schema) }.to raise_error(invalid_input, /delete_vector_index/)
    end
  end

  it "test_updating_vector_next_to_dropped_vector_index" do
    schema = multi_vector_schema
    schema["vectorConfig"]["boi"] = { "vectorizer" => { "none" => {} }, "vectorIndexType" => "none" }

    update = c::CollectionConfigUpdate.new(
      vector_config: [
        c::Reconfigure::Vectors.update(name: "yeh", vector_index_config: c::Reconfigure::VectorIndex.hnsw(ef: 128))
      ]
    )
    new_schema = update.merge_with_existing(schema)

    expect(new_schema["vectorConfig"]["yeh"]["vectorIndexConfig"]["ef"]).to eq(128)
    expect(new_schema["vectorConfig"]["boi"]).to eq({ "vectorizer" => { "none" => {} }, "vectorIndexType" => "none" })
  end

  it "test_updating_vector_when_none_left" do
    update = c::CollectionConfigUpdate.new(
      vector_config: [
        c::Reconfigure::Vectors.update(name: "gone", vector_index_config: c::Reconfigure::VectorIndex.hnsw(ef: 128))
      ]
    )
    expect do
      update.merge_with_existing({ "class" => "Test", "properties" => [] })
    end.to raise_error(invalid_input, /does not exist/)
  end
end
