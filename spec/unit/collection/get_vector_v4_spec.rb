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

  [[0.5], Struct.new(:values) { def to_a = values }.new([0.5])].each do |vector|
    it "test_single_component_vector_stays_a_list_and_can_be_packed (#{vector.class})" do
      expect(get_vector_v4(vector)).to eq([0.5])
      expect(Weaviate::Collections::Grpc::Pack.single(vector)).to eq([0.5].pack("e"))
    end
  end

  [[0.5], [0.5, 0.25], []].each do |values|
    it "test_get_vector_with_array_like_preserves_list_shape (#{values.length} components)" do
      array_like = Struct.new(:values) { def to_a = values }
      expect(Weaviate::Util.get_vector(array_like.new(values))).to eq(values)
    end
  end

  it "raises WeaviateInvalidInputError for malformed vectors" do
    expect { get_vector_v4(42) }.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /malformatted/)
    expect { Weaviate::Collections::Grpc::Pack.single(["a"]) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end
end
