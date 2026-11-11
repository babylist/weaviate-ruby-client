# frozen_string_literal: true

# Port of test/collection/test_bm25_operator.py
RSpec.describe Weaviate::Classes::Query::BM25Operator do
  def builder(version = "1.39.0")
    Weaviate::Collections::Grpc::QueryGRPC.new(weaviate_version: Weaviate::ServerVersion.from_string(version),
                                               name: "Dummy", tenant: nil, consistency_level: nil,
                                               validate_arguments: true, uses_125_api: true, uses_127_api: true)
  end

  it "test_and_cross_wired_into_request" do
    bm25 = builder.bm25(query: "banana split", operator: described_class.and_cross)
    expect(bm25.bm25_search.search_operator.operator).to eq(:OPERATOR_AND_CROSS)

    hybrid = builder.hybrid(query: "banana split", alpha: 0.0, bm25_operator: described_class.and_cross)
    expect(hybrid.hybrid_search.bm25_search_operator.operator).to eq(:OPERATOR_AND_CROSS)
  end

  ["1.37.14", "1.38.7"].each do |version|
    it "test_and_cross_rejected_on_unsupported_versions[#{version}]" do
      expect { builder(version).bm25(query: "banana split", operator: described_class.and_cross) }
        .to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
    end
  end

  it "wires the or operator with its minimum match" do
    op = builder.bm25(query: "a b", operator: described_class.or_(minimum_match: 2)).bm25_search.search_operator
    expect([op.operator, op.minimum_or_tokens_match]).to eq([:OPERATOR_OR, 2])
  end
end
