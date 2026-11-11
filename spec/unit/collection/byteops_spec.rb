# frozen_string_literal: true

# Port of test/collection/test_byteops.py
RSpec.describe Weaviate::Collections::Grpc::ByteOps do
  it "test_decode_float32s" do
    expect(described_class.decode_float32s("".b)).to eq([])
    expect(described_class.decode_float32s("\x00\x00\x80?\x00\x00\x00@\x00\x00\x00\x00".b)).to eq([1.0, 2.0, 0.0])
  end

  it "test_decode_float64s" do
    expect(described_class.decode_float64s("".b)).to eq([])
    bytes = "\x00\x00\x00\x00\x00\x00\xf0?\x00\x00\x00\x00\x00\x00\x00@\x00\x00\x00\x00\x00\x00\x00\x00".b
    expect(described_class.decode_float64s(bytes)).to eq([1.0, 2.0, 0.0])
  end

  it "test_decode_int64s" do
    expect(described_class.decode_int64s("".b)).to eq([])
    expect(described_class.decode_int64s("\x01\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00".b))
      .to eq([1, 2])
  end

  it "round-trips single and multi vectors through Pack/Unpack" do
    grpc = Weaviate::Collections::Grpc
    expect(grpc::Unpack.single(grpc::Pack.single([1.0, 2.5]))).to eq([1.0, 2.5])
    expect(grpc::Unpack.multi(grpc::Pack.multi([[1.0, 2.0], [3.0, 4.0]]))).to eq([[1.0, 2.0], [3.0, 4.0]])
    packing = grpc::Pack.parse_single_or_multi_vec([[1.0], [2.0]])
    expect(packing.type_).to eq(:VECTOR_TYPE_MULTI_FP32)
  end
end
