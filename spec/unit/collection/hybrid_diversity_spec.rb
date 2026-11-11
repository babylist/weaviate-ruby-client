# frozen_string_literal: true

# Port of test/collection/test_hybrid_diversity.py: hybrid diversity_selection populates the
# top-level Hybrid.selection (not the nested near_vector / near_text selection).
RSpec.describe "hybrid diversity" do # rubocop:disable RSpec/DescribeClass
  let(:q) { Weaviate::Classes::Query }

  def builder(version = Weaviate::ServerVersion.new(1, 38, 0))
    Weaviate::Collections::Grpc::QueryGRPC.new(weaviate_version: version, name: "Dummy", tenant: nil,
                                               consistency_level: nil, validate_arguments: true,
                                               uses_125_api: true, uses_127_api: true)
  end

  it "test_hybrid_near_vector_sets_top_level_selection" do
    req = builder.hybrid(query: nil, vector: q::HybridVector.near_vector([1.0, 0.0, 0.0]),
                         diversity_selection: q::Diversity.mmr(limit: 7, balance: 0.0), limit: 7)
    mmr = req.hybrid_search.selection.mmr
    expect(mmr.limit).to eq(7)
    expect(mmr.balance).to eq(0.0)
    expect(req.hybrid_search.near_vector.has_selection?).to be(false)
  end

  it "test_hybrid_near_text_sets_top_level_selection" do
    req = builder.hybrid(query: nil, vector: q::HybridVector.near_text("cats"),
                         diversity_selection: q::Diversity.mmr(limit: 3, balance: 0.5), limit: 3)
    mmr = req.hybrid_search.selection.mmr
    expect(mmr.limit).to eq(3)
    expect(mmr.balance).to eq(0.5)
    expect(req.hybrid_search.near_text.has_selection?).to be(false)
  end

  it "test_hybrid_without_selection_leaves_it_unset" do
    req = builder.hybrid(query: nil, vector: q::HybridVector.near_vector([1.0, 0.0, 0.0]), limit: 5)
    expect(req.hybrid_search.has_selection?).to be(false)
  end
end
