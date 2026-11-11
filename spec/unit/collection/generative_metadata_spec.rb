# frozen_string_literal: true

# Port of test/collection/test_generative_metadata.py
RSpec.describe Weaviate::Collections::Queries::BaseExecutor do
  v1 = Weaviate::V1

  let(:connection) do
    con = Weaviate::Connect::Connection.new(
      connection_params: Weaviate::Connect::ConnectionParams.from_url("http://localhost:8080", 50_051)
    )
    con.instance_variable_set(:@connected, true)
    con.weaviate_version = Weaviate::ServerVersion.new(1, 39, 0)
    con
  end

  { "digitalocean" => v1::GenerativeDigitalOceanMetadata, "meta" => v1::GenerativeMetaMetadata }.each do |provider, type|
    [false, true].each do |grouped|
      it "test_metadata_is_preserved_in_generative_results[#{grouped ? "grouped" : "single"}-#{provider}]" do
        executor = described_class.new(connection: connection, name: "Test", validate_arguments: true)
        usage_class = type.descriptor.lookup("usage").subtype.msgclass
        expected = type.new(usage: usage_class.new(prompt_tokens: 10, completion_tokens: 20, total_tokens: 30))
        generative = v1::GenerativeResult.new(
          values: [v1::GenerativeReply.new(result: "generated",
                                           metadata: v1::GenerativeMetadata.new(provider => expected))]
        )
        response = if grouped
                     v1::SearchReply.new(generative_grouped_results: generative)
                   else
                     v1::SearchReply.new(results: [v1::SearchResult.new(generative: generative)])
                   end

        options = Weaviate::Collections::Grpc::QueryOptions.new(include_metadata: false, include_properties: false,
                                                                include_references: false, include_vector: false,
                                                                is_group_by: false)
        actual = executor.result_to_generative_query_return(response, options)

        metadata = grouped ? actual.generative.metadata : actual.objects[0].generative.metadata
        expect(metadata).to be_a(type)
        expect(metadata).to eq(expected)
        expect(metadata.usage.prompt_tokens).to eq(10)
        expect(metadata.usage.completion_tokens).to eq(20)
        expect(metadata.usage.total_tokens).to eq(30)
      end
    end
  end
end
