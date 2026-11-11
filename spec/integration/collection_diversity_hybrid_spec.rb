# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_diversity_hybrid.py
#
# `diversity_selection` is a hybrid-level argument: the server applies it as a post-fusion MMR pass
# (Weaviate >= 1.38.6). These tests assert that balance=0 (pure diversity) produces a different ordering
# than balance=1 (pure relevance), and that mmr.limit caps the result count.
RSpec.describe "collection diversity hybrid", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:diversity) { Weaviate::Classes::Query::Diversity }
  let(:hybrid_vector) { Weaviate::Classes::Query::HybridVector }
  let(:data_object) { Weaviate::Classes::Data::DataObject }

  def skip_if_unsupported
    skip("Hybrid diversity selection requires Weaviate >= 1.38.6") if server_version.is_lower_than(1, 38, 6)
  end

  def new_collection
    collection = collection_factory(
      properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)],
      vectorizer_config: cfg::Configure::Vectorizer.none
    )
    skip_if_unsupported
    collection
  end

  # Create a collection with 3 tight clusters (a, b, c) of vectors in 3D.
  def create_clustered_collection
    collection = new_collection
    collection.data.insert_many(
      [
        data_object.new(properties: { "text" => "a1" }, vector: [1.0, 0.0, 0.0]),
        data_object.new(properties: { "text" => "a2" }, vector: [0.95, 0.05, 0.0]),
        data_object.new(properties: { "text" => "a3" }, vector: [0.9, 0.1, 0.0]),
        data_object.new(properties: { "text" => "b1" }, vector: [0.0, 1.0, 0.0]),
        data_object.new(properties: { "text" => "b2" }, vector: [0.05, 0.95, 0.0]),
        data_object.new(properties: { "text" => "c1" }, vector: [0.0, 0.0, 1.0])
      ]
    )
    collection
  end

  # Create a collection with enough items (>25) that a small mmr.limit is distinguishable from the
  # server's default limit.
  def create_large_collection(n_items: 50)
    collection = new_collection
    collection.data.insert_many(
      Array.new(n_items) { |i| data_object.new(properties: { "text" => "t#{i}" }, vector: [1.0 - (0.001 * i), 0.0, 0.0]) }
    )
    collection
  end

  it "test_hybrid_near_vector_balance_0_differs_from_balance_1" do
    collection = create_clustered_collection
    balance0 = collection.query.hybrid(nil, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                            diversity_selection: diversity.mmr(limit: 3, balance: 0.0), limit: 3).objects
    balance1 = collection.query.hybrid(nil, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                            diversity_selection: diversity.mmr(limit: 3, balance: 1.0), limit: 3).objects
    expect(balance0.map(&:uuid)).not_to eq(balance1.map(&:uuid))
  end

  it "test_hybrid_near_vector_balance_1_matches_baseline" do
    collection = create_clustered_collection
    baseline = collection.query.hybrid(nil, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]), limit: 3).objects
    mmr_balance1 = collection.query.hybrid(nil, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                                diversity_selection: diversity.mmr(limit: 3, balance: 1.0),
                                                limit: 3).objects
    expect(baseline.map(&:uuid)).to eq(mmr_balance1.map(&:uuid))
  end

  it "test_hybrid_alpha_1_balance_0_differs_from_balance_1" do
    collection = create_clustered_collection
    balance0 = collection.query.hybrid("irrelevant", alpha: 1.0, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                                     diversity_selection: diversity.mmr(limit: 3, balance: 0.0),
                                                     limit: 3).objects
    balance1 = collection.query.hybrid("irrelevant", alpha: 1.0, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                                     diversity_selection: diversity.mmr(limit: 3, balance: 1.0),
                                                     limit: 3).objects
    expect(balance0.map(&:uuid)).not_to eq(balance1.map(&:uuid))
  end

  it "test_hybrid_respects_mmr_limit" do
    mmr_limit = 5
    collection = create_large_collection(n_items: 50)

    result = collection.query.hybrid(nil, vector: hybrid_vector.near_vector([1.0, 0.0, 0.0]),
                                          diversity_selection: diversity.mmr(limit: mmr_limit, balance: 0.5)).objects
    expect(result.length).to eq(mmr_limit)
  end
end
