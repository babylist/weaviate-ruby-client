# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_gql_raw_v4.py
RSpec.describe "gql raw v4", :integration do
  config = Weaviate::Classes::Config

  it "test_raw_gql_v4" do
    name = "RawGraphQlTest"
    number = 20
    client = client_factory
    client.collections.delete(name)
    collection = client.collections.create(
      name,
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    begin
      collection.data.insert_many((0...number).map { |i| { "Name" => "name #{i}" } })

      response = client.graphql_raw_query(
        "{
          Aggregate {RawGraphQlTest{meta {count}}}
          Get{RawGraphQlTest{name}}
        }"
      )

      expect(response.errors).to be_nil
      expect(response.aggregate[name][0]["meta"]["count"]).to eq(number)
      expect(response.get[name].length).to eq(number)
    ensure
      client.collections.delete(name)
    end
  end

  it "test_raw_gql_v4_error" do
    client = client_factory
    begin
      client.collections.create("dummy")
      response = client.graphql_raw_query(
        "{
          Get{IDoNotExist{name}}
        }"
      )

      expect(response.errors).not_to be_nil
      expect(response.get.length).to eq(0)
      expect(response.aggregate.length).to eq(0)
      expect(response.explore.length).to eq(0)
    ensure
      client.collections.delete("dummy")
    end
  end
end
