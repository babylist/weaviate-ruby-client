# frozen_string_literal: true

# Port of test/collection/test_target_vectors.py
RSpec.describe "target vectors" do # rubocop:disable RSpec/DescribeClass
  q = Weaviate::Classes::Query

  def query_grpc(version)
    weaviate_version = Weaviate::ServerVersion.from_string(version)
    Weaviate::Collections::Grpc::QueryGRPC.new(
      weaviate_version: weaviate_version, name: "Documents", tenant: nil, consistency_level: nil,
      validate_arguments: true, uses_125_api: weaviate_version.is_at_least(1, 25, 0),
      uses_127_api: weaviate_version.is_at_least(1, 27, 0)
    )
  end

  searches = {
    "near_vector" => lambda { |ctx, version, vector, target_vector|
      ctx.query_grpc(version).near_vector(near_vector: vector, target_vector: target_vector).near_vector.targets
    },
    "hybrid" => lambda { |ctx, version, vector, target_vector|
      ctx.query_grpc(version).hybrid(query: "example", vector: vector, target_vector: target_vector)
         .hybrid_search.targets
    },
    "hybrid_near_vector" => lambda { |ctx, version, vector, target_vector|
      ctx.query_grpc(version).hybrid(query: "example", vector: q::HybridVector.near_vector(vector),
                                     target_vector: target_vector).hybrid_search.targets
    }
  }
  versions = ["1.26.0", "1.27.0", "1.29.0"]

  searches.each do |search_name, search|
    versions.each do |version|
      { "list" => -> { %w[title summary] },
        "weights" => -> { q::TargetVectors.manual_weights({ "title" => 1.0, "summary" => 2.0 }) } }.each do |id, tv|
        it "test_mismatched_vector_names[#{id}-#{version}-#{search_name}]" do
          expect do
            search.call(self, version, { "title" => [1.0, 0.0], "body" => [0.0, 1.0] }, tv.call)
          end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /must match the target vectors/)
        end
      end

      it "test_vector_names_in_a_different_order[#{version}-#{search_name}]" do
        targets = search.call(self, version, { "summary" => [0.0, 1.0], "title" => [1.0, 0.0] },
                              q::TargetVectors.manual_weights({ "title" => 1.0, "summary" => 2.0 }))
        weights = targets.weights_for_targets.to_h { |w| [w.target, w.weight] }
        expect(weights).to eq("title" => 1.0, "summary" => 2.0)
        expect(targets.target_vectors.to_a).to eq(%w[summary title]) unless version == "1.26.0"
      end
    end

    ["1.27.0", "1.29.0"].each do |version|
      it "test_repeated_target_vector_names_with_multiple_weights[#{version}-#{search_name}]" do
        targets = search.call(self, version, { "title" => q::NearVector.list_of_vectors([1.0, 0.0], [0.0, 1.0]) },
                              q::TargetVectors.manual_weights({ "title" => [1.0, 2.0] }))
        expect(targets.target_vectors.to_a).to eq(%w[title title])
        expect(targets.weights_for_targets.map { |w| [w.target, w.weight] }).to eq([["title", 1.0], ["title", 2.0]])
      end
    end
  end
end
