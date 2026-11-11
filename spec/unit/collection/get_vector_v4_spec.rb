# frozen_string_literal: true

# Port of test/test_get_vector_v4.py. Ruby has no numpy/pandas/polars; any object responding to
# #to_a (e.g. Numo::NArray, Vector) is converted the same way.
RSpec.describe "get_vector_v4" do # rubocop:disable RSpec/DescribeClass
  def get_vector_v4(vec) = Weaviate::Collections::Grpc.get_vector_v4(vec)

  it "test_get_vector_v4_with_list" do
    vec = get_vector_v4([1.0, 2.0, 3.0, 4.0, 5.0])
    expect(vec).to be_a(Array)
    expect(vec).to all(be_a(Float))
  end

  it "test_get_vector_v4_with_array_like (numpy/pandas/polars stand-in)" do
    array_like = Struct.new(:values) do
      def to_a = values
    end
    vec = get_vector_v4(array_like.new([1.0, 2.0]))
    expect(vec).to eq([1.0, 2.0])
    expect(vec).to all(be_a(Float))
  end

  it "raises WeaviateInvalidInputError for malformed vectors" do
    expect { get_vector_v4(42) }.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /malformatted/)
    expect { Weaviate::Collections::Grpc::Pack.single(["a"]) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end
end
