# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_query_profile.py
RSpec.describe "collection query profile", :integration do
  include Batch4Helpers

  go_duration_re = /\A[\d.]+(ns|µs|ms|s|m|h)\z/

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }

  # Assert that a string looks like a Go duration (e.g. '1.234ms', '5.458µs').
  define_method(:assert_go_duration) do |value, label = ""|
    expect(value).to match(go_duration_re), "Expected Go duration format for #{label.inspect}, got #{value.inspect}"
  end

  # Assertions shared by every search profile regardless of type.
  def assert_common_profile(profile)
    expect(profile.details.length).to be > 0, "Profile details should not be empty"
    expect(profile.details).to have_key("total_took")
    assert_go_duration(profile.details["total_took"], "total_took")
    profile.details.each do |key, value|
      expect(key).to be_a(String).and(satisfy { |k| k != "" })
      expect(value).to be_a(String).and(satisfy { |v| v != "" })
    end
  end

  def create_and_populate
    collection = collection_factory(properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)])
    skip("Query profiling requires Weaviate >= 1.36.9") if server_version.is_lower_than(1, 36, 9)
    data_object = Weaviate::Classes::Data::DataObject
    collection.data.insert_many(
      [
        data_object.new(properties: { "text" => "hello world" }, vector: [1.0, 0.0, 0.0]),
        data_object.new(properties: { "text" => "goodbye world" }, vector: [0.0, 1.0, 0.0]),
        data_object.new(properties: { "text" => "foo bar baz" }, vector: [0.0, 0.0, 1.0])
      ]
    )
    collection
  end

  it "test_fetch_objects_with_query_profile" do
    # Test that query profiling works with fetch_objects (object lookup).
    collection = create_and_populate
    result = collection.query.fetch_objects(return_metadata: q::MetadataQuery.new(query_profile: true))
    expect(result.objects.length).to eq(3)
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.name).not_to eq("")
    expect(shard.node).not_to eq("")

    expect(shard.searches).to have_key("object")
    expect(shard.searches).not_to have_key("vector")
    expect(shard.searches).not_to have_key("keyword")
    assert_common_profile(shard.searches["object"])
  end

  it "test_near_vector_with_query_profile" do
    # Test that query profiling works with near_vector search.
    collection = create_and_populate
    result = collection.query.near_vector(
      [1.0, 0.0, 0.0], return_metadata: q::MetadataQuery.new(query_profile: true, distance: true), limit: 2
    )
    expect(result.objects.length).to eq(2)
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.searches).to have_key("vector")
    expect(shard.searches).not_to have_key("keyword")
    expect(shard.searches).not_to have_key("object")
    vector_profile = shard.searches["vector"]
    assert_common_profile(vector_profile)

    expect(vector_profile.details).to have_key("vector_search_took")
    assert_go_duration(vector_profile.details["vector_search_took"], "vector_search_took")

    expect(vector_profile.details).to have_key("hnsw_flat_search")
    expect(%w[true false]).to include(vector_profile.details["hnsw_flat_search"])

    layer_keys = vector_profile.details.keys.select { |k| k.start_with?("knn_search_layer_") }
    expect(layer_keys.length).to be > 0, "Expected at least one knn_search_layer_*_took key"
    layer_keys.each { |k| assert_go_duration(vector_profile.details[k], k) }

    expect(vector_profile.details).to have_key("objects_took")
    assert_go_duration(vector_profile.details["objects_took"], "objects_took")
  end

  it "test_bm25_with_query_profile" do
    # Test that query profiling works with BM25 keyword search.
    collection = create_and_populate
    result = collection.query.bm25("hello", return_metadata: q::MetadataQuery.new(query_profile: true, score: true))
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.searches).to have_key("keyword")
    expect(shard.searches).not_to have_key("vector")
    expect(shard.searches).not_to have_key("object")
    keyword_profile = shard.searches["keyword"]
    assert_common_profile(keyword_profile)

    expect(keyword_profile.details).to have_key("kwd_method")
    expect(keyword_profile.details["kwd_method"]).not_to eq("")

    expect(keyword_profile.details).to have_key("kwd_time")
    assert_go_duration(keyword_profile.details["kwd_time"], "kwd_time")

    expect(keyword_profile.details).to have_key("kwd_1_tok_time")
    assert_go_duration(keyword_profile.details["kwd_1_tok_time"], "kwd_1_tok_time")

    expect(keyword_profile.details).to have_key("kwd_6_res_count")
    expect(keyword_profile.details["kwd_6_res_count"]).to match(/\A\d+\z/)
    expect(Integer(keyword_profile.details["kwd_6_res_count"])).to be >= 0
  end

  it "test_hybrid_with_query_profile" do
    # Test that query profiling works with hybrid search (both vector and keyword).
    collection = create_and_populate
    result = collection.query.hybrid("hello", vector: [1.0, 0.0, 0.0],
                                              return_metadata: q::MetadataQuery.new(query_profile: true), limit: 2)
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.searches).to have_key("vector"), "Hybrid should produce a 'vector' profile"
    expect(shard.searches).to have_key("keyword"), "Hybrid should produce a 'keyword' profile"
    expect(shard.searches).not_to have_key("object")

    assert_common_profile(shard.searches["vector"])
    expect(shard.searches["vector"].details).to have_key("vector_search_took")

    assert_common_profile(shard.searches["keyword"])
    expect(shard.searches["keyword"].details).to have_key("kwd_method")
  end

  it "test_near_vector_group_by_with_query_profile" do
    # Test that query profiling works with group_by.
    collection = create_and_populate
    result = collection.query.near_vector(
      [1.0, 0.0, 0.0],
      return_metadata: q::MetadataQuery.new(query_profile: true),
      group_by: q::GroupBy.new(prop: "text", objects_per_group: 1, number_of_groups: 3)
    )
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.searches).to have_key("vector")
    assert_common_profile(shard.searches["vector"])
  end

  it "test_full_with_profile" do
    # Test that MetadataQuery.full_with_profile returns profiling and all other metadata.
    collection = create_and_populate
    result = collection.query.near_vector([1.0, 0.0, 0.0], return_metadata: q::MetadataQuery.full_with_profile,
                                                           limit: 1)
    expect(result.objects.length).to eq(1)
    obj = result.objects[0]
    expect(obj.metadata.distance).not_to be_nil
    expect(obj.metadata.creation_time).not_to be_nil
    expect(obj.metadata.last_update_time).not_to be_nil
    expect(obj.metadata.score).not_to be_nil
    expect(obj.metadata.explain_score).not_to be_nil

    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0
    assert_common_profile(result.query_profile.shards[0].searches["vector"])
  end

  it "test_full_excludes_query_profile" do
    # Test that MetadataQuery.full does not include query profiling.
    collection = create_and_populate
    result = collection.query.fetch_objects(return_metadata: q::MetadataQuery.full)
    expect(result.query_profile).to be_nil
  end

  it "test_no_query_profile_when_not_requested" do
    # Test that query_profile is nil when not requested.
    collection = create_and_populate
    result = collection.query.fetch_objects(return_metadata: q::MetadataQuery.new(distance: true))
    expect(result.query_profile).to be_nil
  end

  it "test_query_profile_with_metadata_list" do
    # Test that query profiling works when using list-style metadata.
    collection = create_and_populate
    result = collection.query.near_vector([1.0, 0.0, 0.0], return_metadata: %w[query_profile distance], limit: 2)
    expect(result.query_profile).not_to be_nil
    expect(result.query_profile.shards.length).to be > 0

    shard = result.query_profile.shards[0]
    expect(shard.searches).to have_key("vector")
    assert_common_profile(shard.searches["vector"])
  end

  it "test_query_profile_details_are_strings" do
    # Test that all detail keys and values are non-empty strings.
    collection = create_and_populate
    result = collection.query.near_vector([1.0, 0.0, 0.0], return_metadata: q::MetadataQuery.new(query_profile: true),
                                                           limit: 1)
    expect(result.query_profile).not_to be_nil
    result.query_profile.shards.each do |shard|
      expect(shard.searches.length).to be > 0, "Shard should have at least one search profile"
      shard.searches.each do |search_type, profile|
        expect(search_type).to be_a(String).and(satisfy { |s| s != "" })
        expect(profile.details.length).to be > 0
        profile.details.each do |key, value|
          expect(key).to be_a(String).and(satisfy { |k| k != "" })
          expect(value).to be_a(String).and(satisfy { |v| v != "" })
        end
      end
    end
  end
end
