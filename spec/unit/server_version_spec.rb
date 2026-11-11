# frozen_string_literal: true

# Port of test/test_server_version.py
RSpec.describe Weaviate::ServerVersion do
  sv = ->(a, b, c) { described_class.new(a, b, c) }

  {
    "1.2.3.a" => [1, 2, 3], "1.2.3.4" => [1, 2, 3], "v1.2.3.4" => [1, 2, 3], "1.2.3" => [1, 2, 3],
    "v1.2.3" => [1, 2, 3], "1.2" => [1, 2, 0], "v1.2" => [1, 2, 0], "1" => [1, 0, 0], "v1" => [1, 0, 0],
    "" => [0, 0, 0]
  }.each do |version_string, expected|
    it "test_server_version_successful_parsing #{version_string.inspect}" do
      expect(described_class.from_string(version_string)).to eq(sv.call(*expected))
    end
  end

  ["v", "1.v2.3", "1.2.b3"].each do |version_string|
    it "test_server_version_unsuccessful_parsing #{version_string}" do
      expect { described_class.from_string(version_string) }.to raise_error(ArgumentError)
    end
  end

  it "test_server_version_is_at_least" do
    v = sv.call(1, 2, 3)
    [[1, 2, 3], [1, 2, 2], [1, 1, 3], [1, 1, 2], [0, 2, 3], [0, 2, 2], [0, 1, 3], [0, 1, 2]].each do |m|
      expect(v.is_at_least(*m)).to be(true)
    end
    [[1, 2, 4], [1, 3, 3], [1, 3, 4], [2, 2, 3], [2, 2, 4], [2, 3, 3], [2, 3, 4]].each do |m|
      expect(v.is_at_least(*m)).to be(false)
    end
    expect(sv.call(0, 0, 0).is_at_least(0, 0, 1)).to be(false)
  end

  { "1.36.9" => false, "1.37.14" => false, "1.37.15" => true, "1.38.7" => false, "1.38.8" => true,
    "1.39.0" => true, "1.40.0" => true }.each do |version, expected|
    it "test_server_version_is_at_least_any #{version}" do
      expect(described_class.from_string(version).is_at_least_any([1, 37, 15], [1, 38, 8], [1, 39, 0])).to be(expected)
    end
  end

  it "test_server_version_magic_methods" do
    expect(sv.call(1, 2, 3)).to eq(sv.call(1, 2, 3))
    expect(sv.call(1, 2, 3)).not_to eq(sv.call(1, 2, 2))
    expect(sv.call(1, 2, 2)).to be < sv.call(1, 2, 3)
    expect(sv.call(1, 1, 3)).to be < sv.call(1, 2, 3)
    expect(sv.call(0, 2, 3)).to be < sv.call(1, 2, 3)
    expect(sv.call(1, 2, 3)).to be <= sv.call(1, 2, 3)
    expect(sv.call(1, 2, 4)).to be > sv.call(1, 2, 3)
    expect(sv.call(1, 3, 3)).to be > sv.call(1, 2, 3)
    expect(sv.call(2, 2, 3)).to be > sv.call(1, 2, 3)
    expect(sv.call(2, 2, 3)).to be >= sv.call(1, 2, 3)
  end
end
