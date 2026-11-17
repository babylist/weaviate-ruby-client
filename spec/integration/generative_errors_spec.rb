# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_generative_errors.py
RSpec.describe "generative query errors", :integration do
  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }

  it "test_generative_query_error" do
    collection = collection_factory(
      properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)],
      generative_config: cfg::Configure::Generative.anyscale
    )
    collection.data.insert({ "text" => "hello" })

    expect { collection.generate.fetch_objects(single_prompt: "Summarize {text}") }
      .to raise_error(Weaviate::Exceptions::WeaviateGenerativeQueryError) { |e|
        expect(e).to be_a(Weaviate::Exceptions::WeaviateQueryError)
        expect(e.to_s).to include("GRPC search")
      }

    expect { collection.query.fetch_objects(filters: q::Filter.by_property("missing").equal(1)) }
      .to raise_error(Weaviate::Exceptions::WeaviateQueryError) { |e|
        expect(e.class).to eq(Weaviate::Exceptions::WeaviateQueryError)
      }
  end
end
