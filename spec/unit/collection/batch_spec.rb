# frozen_string_literal: true

require "spec_helper"

# Port of test/collection/test_batch.py
RSpec.describe "collection batch" do
  max_stored = Weaviate::Outputs::Batch::MAX_STORED_RESULTS
  uuid4 = -> { Weaviate::Util.generate_uuid4 }

  def error_object(index)
    Weaviate::Outputs::Batch::ErrorObject.new(
      message: "something went wrong",
      object_: Weaviate::Classes::Batch::BatchObject.new(collection: "Test", properties: { "name" => "test" },
                                                         index: index)
    )
  end

  def error_reference(index)
    Weaviate::Outputs::Batch::ErrorReference.new(
      message: "something went wrong",
      reference: Weaviate::Classes::Batch::BatchReference.new(
        from_object_collection: "Test", from_object_uuid: Weaviate::Util.generate_uuid4,
        from_property_name: "other", to_object_uuid: Weaviate::Util.generate_uuid4, index: index
      )
    )
  end

  [
    [500, 0, 31],
    [100, 0, 6.2],
    [100, 2, 4.2],
    [100, -62, 68.2],
    [100, 7, 0],
    [0, 0, 0]
  ].each do |number_objects, elapsed_time, expected_sleep_time|
    it "test_rate_limited_batching_sleep_time_uses_previous_batch_size[#{number_objects}-#{elapsed_time}]" do
      batching = Weaviate::Collections::Batch::RateLimitedBatching.new(requests_per_minute: 1000)
      expect(batching.get_sleep_time(number_objects: number_objects, elapsed_time: elapsed_time, base_time: 62))
        .to be_within(1e-9).of(expected_sleep_time)
    end
  end

  it "test_rate_limited_batching_rejects_non_positive" do
    expect { Weaviate::Collections::Batch::RateLimitedBatching.new(requests_per_minute: 0) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  it "test_batch_object_return_add" do
    lhs_uuids = Array.new(max_stored) { uuid4.call }
    lhs = Weaviate::Outputs::Batch::BatchObjectReturn.new(
      _all_responses: lhs_uuids.dup, elapsed_seconds: 0.1, errors: {}, has_errors: false,
      uuids: lhs_uuids.each_with_index.to_h { |u, i| [i, u] }
    )
    rhs_uuids = Array.new(2) { uuid4.call }
    rhs = Weaviate::Outputs::Batch::BatchObjectReturn.new(
      _all_responses: rhs_uuids.dup, elapsed_seconds: 0.1, errors: {}, has_errors: false,
      uuids: { max_stored => rhs_uuids[0], max_stored + 1 => rhs_uuids[1] }
    )
    result = lhs + rhs
    expect(result.all_responses.length).to eq(max_stored)
    expect(result.uuids.length).to eq(max_stored)
    expected = (lhs_uuids[rhs_uuids.length...max_stored] + rhs_uuids).each_with_index.to_h do |v, idx|
      [idx + rhs_uuids.length, v]
    end
    expect(result.uuids).to eq(expected)
  end

  it "test_batch_object_return_has_errors_when_constructed_with_errors" do
    err = error_object(0)
    result = Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [err], errors: { 0 => err })
    expect(result.has_errors).to be(true)
  end

  it "test_batch_object_return_add_sets_has_errors" do
    err = error_object(1)
    result = Weaviate::Outputs::Batch::BatchObjectReturn.new
    result += Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [uuid4.call], uuids: { 0 => uuid4.call })
    result += Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [err], errors: { 1 => err })
    expect(result.has_errors).to be(true)
    expect(result.errors.length).to eq(1)
  end

  it "test_batch_object_return_has_no_errors_when_all_succeed" do
    uid = uuid4.call
    result = Weaviate::Outputs::Batch::BatchObjectReturn.new
    result += Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [uid], uuids: { 0 => uid })
    expect(result.has_errors).to be(false)
  end

  it "test_batch_reference_return_has_errors_when_constructed_with_errors" do
    err = error_reference(0)
    result = Weaviate::Outputs::Batch::BatchReferenceReturn.new(errors: { 0 => err })
    expect(result.has_errors).to be(true)
  end

  it "test_batch_reference_return_add_sets_has_errors" do
    err = error_reference(0)
    result = Weaviate::Outputs::Batch::BatchReferenceReturn.new
    result += Weaviate::Outputs::Batch::BatchReferenceReturn.new(errors: { 0 => err })
    expect(result.has_errors).to be(true)
    expect(result.errors.length).to eq(1)
  end

  describe "validate_props" do
    let(:grpc) { Weaviate::Collections::Batch::BatchGRPC }

    it "test_validate_props_raises_for_top_level_id" do
      expect { grpc.validate_props({ "id" => "abc123" }) }
        .to raise_error(Weaviate::Exceptions::WeaviateInsertInvalidPropertyError)
    end

    it "test_validate_props_allows_nested_id" do
      expect { grpc.validate_props({ "id" => "abc123" }, nested: true) }.not_to raise_error
    end

    it "test_validate_props_raises_for_top_level_vector" do
      expect { grpc.validate_props({ "vector" => [0.1, 0.2] }) }
        .to raise_error(Weaviate::Exceptions::WeaviateInsertInvalidPropertyError)
    end

    it "test_validate_props_raises_for_nested_vector" do
      expect { grpc.validate_props({ "vector" => [0.1, 0.2] }, nested: true) }
        .to raise_error(Weaviate::Exceptions::WeaviateInsertInvalidPropertyError)
    end
  end

  # Extra coverage of the Ruby port (not in the Python file).
  describe "BatchObject / BatchReference" do
    it "capitalizes the collection and generates a uuid" do
      obj = Weaviate::Classes::Batch::BatchObject.new(collection: "test", index: 0)
      expect(obj.collection).to eq("Test")
      expect(Weaviate::Util.valid_uuid?(obj.uuid)).to be(true)
    end

    it "round-trips references through the internal representation" do
      from = uuid4.call
      to = uuid4.call
      ref = Weaviate::Classes::Batch::BatchReference.new(from_object_collection: "a", from_object_uuid: from,
                                                         from_property_name: "p", to_object_uuid: to,
                                                         to_object_collection: "b", index: 3)
      internal = ref.to_internal
      expect(internal.from_).to eq("weaviate://localhost/A/#{from}/p")
      expect(internal.to).to eq("weaviate://localhost/B/#{to}")
      expect(Weaviate::Classes::Batch::BatchReference.from_internal(internal)).to eq(ref)
    end

    it "raises a ValidationError for an empty collection" do
      expect { Weaviate::Classes::Batch::BatchObject.new(collection: "", index: 0) }
        .to raise_error(Weaviate::Classes::Batch::ValidationError)
    end
  end

  describe "BatchGRPC.grpc_object" do
    let(:grpc) do
      Weaviate::Collections::Batch::BatchGRPC.new(weaviate_version: Weaviate::ServerVersion.from_string("1.36.0"),
                                                  consistency_level: nil, grpc_max_msg_size: nil)
    end

    it "translates properties of all kinds" do
      t = Time.utc(2024, 1, 2, 3, 4, 5)
      obj = Weaviate::Classes::Batch::BatchObjectInternal.new(
        collection: "Test", vector: [1.0, 2.0], uuid: uuid4.call, tenant: nil, references: { "ref" => uuid4.call },
        index: 0,
        properties: {
          "text" => "a", "num" => 1.5, "texts" => %w[a b], "ints" => [1, 2], "floats" => [1.5, 2.5],
          "bools" => [true], "dates" => [t], "date" => t, "empty" => [], "nested" => { "x" => 1 },
          "nesteds" => [{ "y" => "z" }], "geo" => Weaviate::Classes::Data::GeoCoordinate.new(latitude: 1, longitude: 2)
        }
      )
      proto = grpc.grpc_object(obj)
      props = proto.properties
      expect(props.text_array_properties.map(&:prop_name)).to contain_exactly("texts", "dates")
      expect(props.int_array_properties.first.values.to_a).to eq([1, 2])
      expect(props.number_array_properties.first.values_bytes.unpack("E*")).to eq([1.5, 2.5])
      expect(props.boolean_array_properties.first.values.to_a).to eq([true])
      expect(props.empty_list_props.to_a).to eq(["empty"])
      expect(props.object_properties.first.prop_name).to eq("nested")
      expect(props.object_array_properties.first.values.length).to eq(1)
      expect(props.single_target_ref_props.first.prop_name).to eq("ref")
      fields = props.non_ref_properties.to_h
      expect(fields["date"]).to eq(Weaviate::Util.datetime_to_string(t))
      expect(fields["geo"]).to eq({ "latitude" => 1.0, "longitude" => 2.0 })
      expect(proto.vector_bytes.unpack("e*")).to eq([1.0, 2.0])
    end

    it "packs named and multi vectors" do
      obj = Weaviate::Classes::Batch::BatchObjectInternal.new(
        collection: "Test", vector: { "a" => [1.0], "b" => [[1.0, 2.0], [3.0, 4.0]] }, uuid: uuid4.call,
        tenant: nil, references: nil, index: 0, properties: nil
      )
      proto = grpc.grpc_object(obj)
      expect(proto.vector_bytes).to eq("")
      expect(proto.vectors.map(&:type)).to eq(%i[VECTOR_TYPE_SINGLE_FP32 VECTOR_TYPE_MULTI_FP32])
      expect(proto.vectors[1].vector_bytes.unpack1("v")).to eq(2)
    end
  end
end
