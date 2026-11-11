# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collections_sorting.py
RSpec.describe "collections sorting", :integration do
  it "test_collections_list_all_sorting" do
    client = client_factory
    names = %w[SortingTestCollectionA SortingTestCollectionB SortingTestCollectionC]
    begin
      # Create collections with names in non-alphabetical order
      client.collections.create("SortingTestCollectionC")
      client.collections.create("SortingTestCollectionA")
      client.collections.create("SortingTestCollectionB")

      collections = client.collections.list_all
      test_collections = collections.keys.select { |k| k.start_with?("SortingTestCollection") }
      expect(test_collections).to eq(test_collections.sort)

      collections = client.collections.list_all(simple: false)
      test_collections = collections.keys.select { |k| k.start_with?("SortingTestCollection") }
      expect(test_collections).to eq(test_collections.sort)
    ensure
      client.collections.delete(names)
    end
  end
end
