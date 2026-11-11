# frozen_string_literal: true

require "tempfile"

# Port of test/test_util.py
RSpec.describe Weaviate::Util do
  let(:logo) { File.join(__dir__, "..", "fixtures", "weaviate-logo.png") }

  schema_set = {
    "classes" => [
      { "class" => "Ollie", "properties" => [{ "name" => "height" }] },
      { "class" => "Shuvit", "properties" => [{ "name" => "direction" }] },
      { "class" => "Board", "properties" => [{ "name" => "brand" }, { "name" => "art" }, { "name" => "size" }] },
      { "class" => "Truck", "properties" => [{ "name" => "name" }, { "name" => "height" }] }
    ]
  }
  schema_set_extended_prop = JSON.parse(JSON.generate(schema_set)).tap do |s|
    s["classes"][0]["properties"] = [{ "name" => "weight" }]
  end
  schema_sub_set = { "classes" => [schema_set["classes"][0], schema_set["classes"][2]] }
  disjoint_set = {
    "classes" => [{ "class" => "Manual", "properties" => [{ "name" => "nose" }] },
                  { "class" => "Bearings", "properties" => [{ "name" => "brand" }] }]
  }
  partial_set = {
    "classes" => [schema_set["classes"][2], { "class" => "Skateboard", "properties" => [{ "name" => "wheels" }] }]
  }

  it "test_is_weaviate_object_url" do
    expect(described_class.is_weaviate_object_url("weaviate://localhost/28f3f61b-b524-45e0-9bbe-2c1550bf73d2")).to be(true)
    expect(described_class.is_weaviate_object_url("weaviate://some-domain.com/28f3f61b-b524-45e0-9bbe-2c1550bf73d2")).to be(true)
    expect(described_class.is_weaviate_object_url(["weaviate://localhost/28f3f61b-b524-45e0-9bbe-2c1550bf73d2"])).to be(false)
    expect(described_class.is_weaviate_object_url("http://some-domain.com/28f3f61b-b524-45e0-9bbe-2c1550bf73d2")).to be(false)
    expect(described_class.is_weaviate_object_url("weaviate://localhost/things/f61b-b524-45e0-9bbe-2c1550bf73d2")).to be(false)
    expect(described_class.is_weaviate_object_url("weaviate://some-INVALID-domain/28f3f61b-b524-45e0-9bbe-2c1550bf73d2")).to be(false)
    expect(described_class.is_weaviate_object_url("weaviate://localhost/UUID")).to be(false)
  end

  it "test_is_object_url" do
    expect(described_class.is_object_url("http://localhost:8080/v1/objects/1c9cd584-88fe-5010-83d0-017cb3fcb446")).to be(true)
    expect(described_class.is_object_url("http://ramalamadingdong/v1/objects/1c9cd584-88fe-5010-83d0-017cb3fcb446")).to be(true)
    expect(described_class.is_object_url("objects/1c9cd584-88fe-5010-83d0-017cb3fcb446")).to be(false)
    expect(described_class.is_object_url("http://localhost:8080/v2/objects/1c9cd584-88fe-5010-83d0-017cb3fcb446")).to be(false)
    expect(described_class.is_object_url("http://ramalamadingdong/v1/objects/1c9cd584-88fe-5010-83d0")).to be(false)
    expect(described_class.is_object_url("http://localhost:8080/v1/passions/1c9cd584-88fe-5010-83d0-017cb3fcb446")).to be(false)
  end

  it "test_get_valid_uuid" do
    {
      "weaviate://localhost/28f3f61b-b524-45e0-9bbe-2c1550bf73d2" => "28f3f61b-b524-45e0-9bbe-2c1550bf73d2",
      "weaviate://otherhost.com/28f3f61b-b524-45e0-9bbe-2c1550bf73d2" => "28f3f61b-b524-45e0-9bbe-2c1550bf73d2",
      "http://localhost:8080/v1/objects/1c9cd584-88fe-5010-83d0-017cb3fcb446" => "1c9cd584-88fe-5010-83d0-017cb3fcb446",
      "http://otherhost_2:8080/v1/objects/1c9cd584-88fe-5010-83d0-017cb3fcb446" => "1c9cd584-88fe-5010-83d0-017cb3fcb446",
      "http://otherhost_2:8080/v1/objects/1c9cd58488fe501083d0017cb3fcb446" => "1c9cd584-88fe-5010-83d0-017cb3fcb446",
      "1c9cd584-88fe-5010-83d0-017cb3fcb446" => "1c9cd584-88fe-5010-83d0-017cb3fcb446",
      "1c9cd58488fe501083d0017cb3fcb446" => "1c9cd584-88fe-5010-83d0-017cb3fcb446"
    }.each { |input, expected| expect(described_class.get_valid_uuid(input)).to eq(expected) }

    msg = "Not valid 'uuid' or 'uuid' can not be extracted from value"
    ["http://localhost:8080/v1/1c9cd584-88fe-5010-83d0-017cb3fcb",
     "http://localhost:8080/v1/objects/some-UUID",
     "http://localhost:8080/v2/objects/1c9cd584-88fe-5010-83d0-017cb3fcb",
     "weaviate://INVALID_URL//1c9cd584-88fe-5010-83d0-017cb3fcb"].each do |bad|
      expect { described_class.get_valid_uuid(bad) }.to raise_error(ArgumentError, msg)
    end
    expect { described_class.get_valid_uuid(12) }
      .to raise_error(TypeError, "'uuid' must be of type str or uuid.UUID, but was: Integer")
  end

  it "test_get_vector" do
    expect(described_class.get_vector([1.0, 2.0, 3.0])).to eq([1.0, 2.0, 3.0])
    tensor = Struct.new(:data) { def to_a = data }.new([1.0, 2.0, 3.0])
    expect(described_class.get_vector(tensor)).to eq([1.0, 2.0, 3.0])
    expect { described_class.get_vector("[1., 2., 3.]") }.to raise_error(TypeError, described_class::VECTOR_TYPE_ERROR)
  end

  it "test_get_domain_from_weaviate_url" do
    uuid = "28f3f61b-b524-45e0-9bbe-2c1550bf73d2"
    expect(described_class.get_domain_from_weaviate_url("weaviate://localhost/#{uuid}")).to eq("localhost")
    expect(described_class.get_domain_from_weaviate_url("weaviate://otherhost/#{uuid}")).to eq("otherhost")
  end

  it "test__is_sub_schema" do
    expect(described_class.is_sub_schema(schema_set, schema_set)).to be(true)
    expect(described_class.is_sub_schema(schema_set["classes"][0], schema_set)).to be(true)
    expect(described_class.is_sub_schema(schema_sub_set, schema_set)).to be(true)
    lower = JSON.parse(JSON.generate(schema_set)).tap { |s| s["classes"].each { |c| c["class"] = c["class"].downcase } }
    expect(described_class.is_sub_schema(lower, schema_set)).to be(true)
    expect(described_class.is_sub_schema(schema_set, lower)).to be(true)
    expect(described_class.is_sub_schema(lower, lower)).to be(true)
    expect(described_class.is_sub_schema({ "class" => "A" }, schema_set)).to be(false)
    expect(described_class.is_sub_schema(disjoint_set, schema_set)).to be(false)
    expect(described_class.is_sub_schema(partial_set, schema_set)).to be(false)
    expect(described_class.is_sub_schema(schema_set_extended_prop, schema_set)).to be(false)
    expect { described_class.is_sub_schema({}, schema_set) }
      .to raise_error(Weaviate::Exceptions::SchemaValidationError, "The sub schema class/es MUST have a 'class' keyword each!")
  end

  %i[image_encoder_b64 file_encoder_b64].each do |encoder|
    it "test_#{encoder}" do
      expected = [File.binread(logo)].pack("m0")
      expect { described_class.public_send(encoder, "non-existingfile.png") }
        .to raise_error(ArgumentError, "No file found at location non-existingfile.png")
      expect { described_class.public_send(encoder, true) }.to raise_error(TypeError, described_class::ENCODER_TYPE_ERROR)
      Tempfile.create("image.png") do |f|
        wf = File.open(f.path, "wb")
        expect { described_class.public_send(encoder, wf) }.to raise_error(TypeError, described_class::ENCODER_TYPE_ERROR)
        wf.close
      end
      expect(described_class.public_send(encoder, logo)).to eq(expected)
      File.open(logo, "rb") { |f| expect(described_class.public_send(encoder, f)).to eq(expected) }
    end
  end

  %i[image_decoder_b64 file_decoder_b64].each do |decoder|
    it "test_#{decoder}" do
      encoded = [File.binread(logo)].pack("m0")
      expect(described_class.public_send(decoder, encoded)).to eq(File.binread(logo))
    end
  end

  it "test_generate_uuid5" do
    result = described_class.generate_uuid5("TestID!", "Test!")
    expect(result).to be_a(String)
    # same value the Python client produces: uuid5(NAMESPACE_DNS, "Test!TestID!")
    expect(result).to eq("33a3e702-3326-5960-b775-67242c81de78")
  end

  it "test_parse_version_string" do
    expect(described_class.parse_version_string("v1.18.1")).to eq(described_class.parse_version_string("1.18.1"))
    expect(described_class.parse_version_string("v1.18.1")).to eq(described_class.parse_version_string("1.18.5"))
    expect(described_class.parse_version_string("v1.18.3")).to eq([1, 18])
    expect(described_class.parse_version_string("1.1.5")).to eq([1, 1])
    expect(described_class.parse_version_string("2")).to eq([2, 0])
    expect(described_class.parse_version_string("2.0.0")).to eq([2, 0])
    expect(described_class.parse_version_string("v2.05.5")).to eq([2, 5])
  end

  major, minor = described_class.parse_version_string(described_class::MINIMUM_NO_WARNING_VERSION)
  {
    "v#{major - 1}.#{minor - 1}.1" => true, "v#{major - 1}.#{minor + 1}.2" => true, "v#{major}.#{minor - 1}.3" => true,
    described_class::MINIMUM_NO_WARNING_VERSION => false, "v#{major}.#{minor + 1}.0" => false,
    "v#{major + 1}.#{minor - 1}.0" => false, "v#{major + 1}.#{minor + 1}.0" => false
  }.each do |version, too_old|
    it "test_is_weaviate_too_old #{version}" do
      expect(described_class.is_weaviate_too_old(version)).to be(too_old)
    end
  end

  {
    "2023-01-15T14:30:45.123456Z" => Time.utc(2023, 1, 15, 14, 30, Rational(45_123_456, 1_000_000)),
    "2023-01-15T14:30:45Z" => Time.utc(2023, 1, 15, 14, 30, 45),
    "2023-01-15T14:30:45.123456+02:00" => Time.new(2023, 1, 15, 14, 30, Rational(45_123_456, 1_000_000), "+02:00"),
    "2023-01-15T14:30:45.123456789Z" => Time.utc(2023, 1, 15, 14, 30, Rational(45_123_456, 1_000_000)),
    "0000-01-15T14:30:45.123456Z" => described_class::DATETIME_MIN,
    "" => nil
  }.each do |input, expected|
    it "test_datetime_from_weaviate_str #{input.inspect}" do
      result = described_class.datetime_from_weaviate_str(input)
      expect(result).to eq(expected)
      expect(result.utc_offset).to eq(expected.utc_offset) if expected
    end
  end

  it "test_datetime_from_weaviate_str_empty_string_warns" do
    result, warnings = Weaviate::Warnings.capture { described_class.datetime_from_weaviate_str("") }
    expect(result).to be_nil
    expect(warnings.first).to include("Con006")
  end

  [
    ["v1.18.1", "v1.18.1", false], ["v1.0.0", "v1.3.1", false], ["v1.0.0", "v1.4.0", true],
    ["unknown", "v1.4.0", false], ["v1.4.0", "unknown", false], ["v0.4.0", "v1.16.16", true],
    ["v0.4.0", "v1.4.0", true], ["v0.4.0", "v1.0.0", true]
  ].each do |current, latest, too_old|
    it "test_is_weaviate_client_too_old #{current} #{latest}" do
      expect(described_class.is_weaviate_client_too_old(current, latest)).to be(too_old)
    end
  end

  [['"', '\\"'], ['\\"', '\\"'], ['\\\\"', '\\\\\\"'], ['\\\\\\"', '\\\\\\"']].each do |in_str, out_str|
    it "test_sanitize_str #{in_str}" do
      expect(described_class.sanitize_str(in_str)).to eq("\"#{out_str}\"")
    end
  end
end
