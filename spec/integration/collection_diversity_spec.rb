# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_diversity.py
RSpec.describe "collection diversity", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:diversity) { Weaviate::Classes::Query::Diversity }

  # Create a collection with 3 tight clusters (a, b, c) of vectors in 3D.
  def create_clustered_collection
    collection = collection_factory(
      properties: [cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)],
      vectorizer_config: cfg::Configure::Vectorizer.none
    )
    skip("Diversity selection requires Weaviate >= 1.37.0") if server_version.is_lower_than(1, 37, 0)
    data_object = Weaviate::Classes::Data::DataObject
    collection.data.insert_many(
      [
        data_object.new(properties: { "text" => "a1" }, vector: [1.0, 0.0, 0.0]),
        data_object.new(properties: { "text" => "a2" }, vector: [0.95, 0.05, 0.0]),
        data_object.new(properties: { "text" => "a3" }, vector: [0.9, 0.1, 0.0]),
        data_object.new(properties: { "text" => "b1" }, vector: [0.0, 1.0, 0.0]),
        data_object.new(properties: { "text" => "b2" }, vector: [0.05, 0.95, 0.0]),
        data_object.new(properties: { "text" => "c1" }, vector: [0.0, 0.0, 1.0])
      ]
    )
    collection
  end

  def contextionary_collection(**kw)
    skip_if_native!("requires text2vec-contextionary")
    collection = collection_factory(
      properties: [cfg::Property.new(name: "name", data_type: cfg::DataType::TEXT)],
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false),
      **kw
    )
    skip("Diversity selection requires Weaviate >= 1.37.0") if server_version.is_lower_than(1, 37, 0)
    %w[banana apple orange car truck bike].each { |name| collection.data.insert({ "name" => name }) }
    collection
  end

  it "test_near_vector_diversity_selection" do
    # Verify that the client passes diversity_selection to the server correctly:
    # - balance reaches the server: balance=0.0 produces a different UUID ordering than balance=1.0
    # - limit reaches the server: len(result) == mmr_limit
    collection = create_clustered_collection
    mmr_limit = 3

    balance0 = collection.query.near_vector([1.0, 0.0, 0.0],
                                            diversity_selection: diversity.mmr(limit: mmr_limit, balance: 0.0)).objects
    balance1 = collection.query.near_vector([1.0, 0.0, 0.0],
                                            diversity_selection: diversity.mmr(limit: mmr_limit, balance: 1.0)).objects

    expect(balance0.length).to eq(mmr_limit)
    expect(balance1.length).to eq(mmr_limit)
    expect(balance0.map(&:uuid)).not_to eq(balance1.map(&:uuid))
  end

  it "test_near_text_diversity_selection" do
    # Smoke test: diversity_selection kwarg is wired through the near_text entry point.
    collection = contextionary_collection
    result = collection.query.near_text("fruit", diversity_selection: diversity.mmr(limit: 3, balance: 0.5))
    expect(result.objects.length).to eq(3)
  end

  it "test_near_object_diversity_selection" do
    # Smoke test: diversity_selection kwarg is wired through the near_object entry point.
    collection = create_clustered_collection
    anchor = collection.query.fetch_objects.objects.first.uuid

    result = collection.query.near_object(anchor, diversity_selection: diversity.mmr(limit: 3, balance: 0.5))
    expect(result.objects.length).to eq(3)
  end

  it "test_generate_diversity_selection" do
    # Smoke test: diversity_selection kwarg is wired through the .generate namespace.
    collection = contextionary_collection(generative_config: cfg::Configure::Generative.custom("generative-dummy"))
    result = collection.generate.near_text("fruit", single_prompt: "Describe {name}",
                                                    diversity_selection: diversity.mmr(limit: 3, balance: 0.5))
    expect(result.objects.length).to eq(3)
  end

  it "test_diversity_selection_api_surface" do
    # Direct instantiation of the factory class fails
    expect { diversity.new }.to raise_error(TypeError)

    # Diversity.mmr() produces an MMR-configured selection object
    expect(diversity.mmr(limit: 3, balance: 0.5).limit).to eq(3)
  end
end
