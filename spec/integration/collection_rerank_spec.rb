# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_rerank.py
RSpec.describe "collection rerank", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }

  def text_prop = cfg::Property.new(name: "text", data_type: cfg::DataType::TEXT)
  def rerank = q::Rerank.new(prop: "text", query: "another")

  def insert_and_vector(collection)
    insert = collection.data.insert_many([{ "text" => "This is a test" }, { "text" => "This is another test" }])
    uuid1 = insert.uuids[0]
    vector1 = collection.query.fetch_object_by_id(uuid1, include_vector: true).vector
    expect(vector1).not_to be_nil
    [uuid1, vector1]
  end

  def expect_reranked_objects(objects)
    expect(objects.length).to eq(2)
    expect(objects[0].metadata.rerank_score).not_to be_nil
    expect(objects[1].metadata.rerank_score).not_to be_nil

    with_another = objects.find { |obj| obj.properties["text"].include?("another") }
    without_another = objects.find { |obj| !obj.properties["text"].include?("another") }
    expect(with_another.metadata.rerank_score).to be > without_another.metadata.rerank_score
  end

  def all_query_lambdas(collection, uuid1, vector1)
    [
      -> { collection.query.bm25("test", rerank: rerank) },
      -> { collection.query.hybrid("test", rerank: rerank) },
      -> { collection.query.near_object(uuid1, rerank: rerank) },
      -> { collection.query.near_vector(vector1["default"], rerank: rerank) },
      -> { collection.query.near_text("test", rerank: rerank) }
    ]
  end

  it "test_query_using_rerank_with_old_server" do
    collection = collection_factory(
      reranker_config: cfg::Configure::Reranker.custom("reranker-dummy"),
      vectorizer_config: cfg::Configure::Vectorizer.none,
      properties: [text_prop]
    )
    if server_version.is_at_least(1, 23, 1)
      skip("Reranking works with 1.23.1 or higher so no need to test this")
    end

    collection.data.insert_many([{ "text" => "This is a test" }, { "text" => "This is another test" }])

    objs, warnings = Weaviate::Warnings.capture { collection.query.bm25("test", rerank: rerank).objects }
    expect(warnings).not_to be_empty
    expect(objs.length).to eq(2)
    expect(objs[0].metadata.rerank_score).to be_nil
    expect(objs[1].metadata.rerank_score).to be_nil
  end

  it "test_queries_with_rerank" do
    api_key = ENV.fetch("COHERE_APIKEY", nil)
    skip("No Cohere API key found.") if api_key.nil?

    collection = collection_factory(
      name: "Test_test_queries_with_rerank",
      reranker_config: cfg::Configure::Reranker.cohere,
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_cohere,
      properties: [text_prop],
      headers: { "X-Cohere-Api-Key" => api_key },
      ports: [8086, 50_057]
    )
    skip("Reranking requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

    uuid1, vector1 = insert_and_vector(collection)

    all_query_lambdas(collection, uuid1, vector1).each do |query|
      expect_reranked_objects(query.call.objects)
    end
  end

  it "test_queries_with_rerank_and_group_by" do
    api_key = ENV.fetch("COHERE_APIKEY", nil)
    skip("No Cohere API key found.") if api_key.nil?

    collection = collection_factory(
      name: "Test_test_queries_with_rerank_and_group_by",
      reranker_config: cfg::Configure::Reranker.cohere,
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_cohere(vectorize_collection_name: false),
      properties: [text_prop],
      headers: { "X-Cohere-Api-Key" => api_key },
      ports: [8086, 50_057]
    )
    skip("Reranking requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

    uuid1, vector1 = insert_and_vector(collection)
    group_by = q::GroupBy.new(prop: "text", objects_per_group: 1, number_of_groups: 2)

    [
      -> { collection.query.near_object(uuid1, rerank: rerank, group_by: group_by) },
      -> { collection.query.near_vector(vector1["default"], rerank: rerank, group_by: group_by) },
      -> { collection.query.near_text("test", rerank: rerank, group_by: group_by) }
    ].each do |query|
      ret = query.call
      expect(ret.groups.length).to eq(2)
      expect(ret.objects.length).to eq(2)
      expect(ret.groups.values[0].objects.length).to eq(1)
      expect(ret.groups.values[1].objects.length).to eq(1)
      expect(ret.objects[0].belongs_to_group).not_to be_nil
      expect(ret.objects[1].belongs_to_group).not_to be_nil

      with_another = ret.groups.find { |prop, _group| prop.include?("another") }[1]
      without_another = ret.groups.find { |prop, _group| !prop.include?("another") }[1]
      expect(with_another.rerank_score).to be > without_another.rerank_score
    end
  end

  it "test_queries_with_rerank_contextualai" do
    # Test Contextual AI reranker with various query types.
    api_key = ENV.fetch("CONTEXTUAL_API_KEY", nil)
    skip("No Contextual AI API key found.") if api_key.nil?

    collection = collection_factory(
      name: "Test_test_queries_with_rerank_contextualai",
      reranker_config: cfg::Configure::Reranker.contextualai(
        model: "ctxl-rerank-v2-instruct-multilingual",
        instruction: "Prioritize documents that contain the query term"
      ),
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_openai,
      properties: [text_prop],
      headers: { "X-Contextual-Api-Key" => api_key },
      ports: [8086, 50_057]
    )
    skip("Reranking requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

    uuid1, vector1 = insert_and_vector(collection)

    all_query_lambdas(collection, uuid1, vector1).each do |query|
      expect_reranked_objects(query.call.objects)
    end
  end
end
