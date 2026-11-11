# frozen_string_literal: true

require "spec_helper"

# Port of test/collection/test_collections_sorting.py
RSpec.describe Weaviate::Collections::Config::ConfigMethods do
  let(:mock_schema) do
    {
      "classes" => [
        { "class" => "CollectionC", "description" => "Collection C" },
        { "class" => "CollectionA", "description" => "Collection A" },
        { "class" => "CollectionB", "description" => "Collection B" }
      ]
    }
  end

  it "test_collection_configs_from_json_sorting" do
    allow(described_class).to receive(:collection_config_from_json).and_return(double)

    result = described_class.collection_configs_from_json(mock_schema)

    expect(result.keys).to eq(%w[CollectionA CollectionB CollectionC])
  end

  it "test_collection_configs_simple_from_json_sorting" do
    allow(described_class).to receive(:collection_config_simple_from_json).and_return(double)

    result = described_class.collection_configs_simple_from_json(mock_schema)

    expect(result.keys).to eq(%w[CollectionA CollectionB CollectionC])
  end
end
