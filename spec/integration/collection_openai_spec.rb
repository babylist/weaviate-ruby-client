# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_openai.py.
#
# Most tests need OPENAI_APIKEY (or COHERE_APIKEY / CONTEXTUAL_API_KEY) and the docker-compose
# instance with the OpenAI modules on (8086, 50057); they skip like the Python tests (and in native
# mode). test_openai_no_module runs against the default instance.
module Batch5Specs
  RSpec.describe "collection_openai", :integration do
    include Batch5Helpers

    def server_version = client_factory.connection.weaviate_version

    # Python: collection._connection.supports_groupby_in_bm25_and_hybrid() (gone from the Python
    # client); group_by in bm25/hybrid is supported from Weaviate 1.25.
    def supports_groupby_in_bm25_and_hybrid = server_version.is_at_least(1, 25, 0)

    [%w[text yes], %w[content no]].each do |parameter, answer|
      it "test_generative_search_single[#{parameter}-#{answer}]" do
        collection = openai_collection

        collection.data.insert_many(
          [
            DataObject.new(properties: { "text" => "bananas are great", "content" => "bananas are bad" }),
            DataObject.new(properties: { "text" => "apples are great", "content" => "apples are bad" })
          ]
        )

        res = collection.generate.fetch_objects(
          single_prompt: "is it good or bad based on {#{parameter}}? Just answer with yes or no without punctuation"
        )
        res.objects.each do |obj|
          expect(obj.generated).not_to be_nil
          expect(obj.generated.downcase).to eq(answer)
        end
        expect(res.generated).to be_nil
      end
    end

    [[["text"], "apples bananas"], [["content"], "bananas apples"]].each_with_index do |(prop, answer), i|
      it "test_fetch_objects_generate_search_grouped[prop#{i}-#{answer}]" do
        collection = openai_collection

        collection.data.insert_many(
          [
            DataObject.new(properties: { "text" => "apples are big", "content" => "apples are small" }),
            DataObject.new(properties: { "text" => "bananas are small", "content" => "bananas are big" })
          ]
        )

        res = collection.generate.fetch_objects(
          grouped_task: "What is big and what is small? write the name of the big thing first and then the name of " \
                        "the small thing after a space. Dont write anything else",
          grouped_properties: prop
        )
        expect(res.generated).to eq(answer)
      end
    end

    it "test_fetch_objects_generate_search_grouped_all_props" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: {
                           "text" => "apples are big. Apples are smaller than Teddy and bigger than bananas",
                           "content" => "Teddy is the biggest and bigger than everything else. Teddy is bigger than apples."
                         }),
          DataObject.new(properties: {
                           "text" => "bananas are small. Bananas are smaller than apples and bigger than cats",
                           "content" => "cats are the smallest and smaller than everything else. Cats are smaller than bananas"
                         })
        ]
      )

      res = collection.generate.fetch_objects(
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space. " \
                      "Dont write anything else"
      )
      expect(res.generated).to eq("Teddy cats")
    end

    it "test_fetch_objects_generate_search_grouped_specified_prop" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "bananas are small",
                                       "content" => "cats are the smallest and smaller than everything else" })
        ]
      )

      res = collection.generate.fetch_objects(
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space",
        grouped_properties: ["text"]
      )
      expect(res.generated).to eq("apples bananas")
    end

    it "test_fetch_objects_generate_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: {
                           "text" => "apples are big. Apples are smaller than Teddy and bigger than bananas",
                           "content" => "Teddy is the biggest and bigger than everything else"
                         }),
          DataObject.new(properties: {
                           "text" => "bananas are small. Bananas are smaller than apples and bigger than cats.",
                           "content" => "cats are the smallest and smaller than everything else"
                         })
        ]
      )

      res = collection.generate.fetch_objects(
        single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no if " \
                       "not without punctuation",
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space"
      )
      expect(res.generated).to eq("Teddy cats")
      res.objects.each { |obj| expect(obj.generated).to eq("Yes") }
    end

    it "test_bm25_generate_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "bananas are small",
                                       "content" => "cats are the smallest and smaller than everything else" })
        ]
      )

      res = collection.generate.bm25(
        "Teddy",
        query_properties: ["content"],
        single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no if " \
                       "not without punctuation",
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space"
      )
      expect(res.generated).to eq("Teddy apples")
      res.objects.each { |obj| expect(obj.generated).to eq("Yes") }
    end

    it "test_bm25_generate_and_group_by_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "bananas are small",
                                       "content" => "cats are the smallest and smaller than everything else" })
        ]
      )

      query = lambda do
        collection.generate.bm25(
          "Teddy",
          query_properties: ["content"],
          single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no " \
                         "if not without punctuation",
          grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space",
          group_by: GroupBy.new(prop: "text", number_of_groups: 2, objects_per_group: 1)
        )
      end
      if supports_groupby_in_bm25_and_hybrid
        res = query.call
        expect(res.generated).to eq("Teddy apples")
        expect(res.groups.length).to eq(1)
        groups = res.groups.values
        expect(groups[0].generated).to eq("Yes")
        expect(res.objects[0].belongs_to_group).to eq("apples are big")
      else
        expect { query.call }.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
      end
    end

    it "test_hybrid_generate_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big. You can eat apples",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "cats are small. You cannot eat cats",
                                       "content" => "bananas are the smallest and smaller than everything else" })
        ]
      )

      res = collection.generate.hybrid(
        "cats",
        alpha: 0,
        query_properties: ["text"],
        single_prompt: "Does {text} mention cats? Only answer yes if there is the word cat or cats in the text and no " \
                       "if not. Dont use punctuation",
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space from " \
                      "biggest to smallest"
      )
      expect(res.generated).to eq("cats bananas")
      res.objects.each do |obj|
        expect(obj.generated).not_to be_nil
        expect(obj.generated.downcase).to eq("yes")
      end
    end

    it "test_hybrid_generate_and_group_by_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "bananas are small",
                                       "content" => "cats are the smallest and smaller than everything else" })
        ]
      )

      query = lambda do
        collection.generate.hybrid(
          "Teddy",
          alpha: 0,
          query_properties: ["content"],
          single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no " \
                         "if not without punctuation",
          grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space",
          group_by: GroupBy.new(prop: "text", number_of_groups: 2, objects_per_group: 1)
        )
      end
      if supports_groupby_in_bm25_and_hybrid
        res = query.call
        expect(res.generated).to eq("Teddy apples")
        expect(res.groups.length).to eq(1)
        groups = res.groups.values
        expect(groups[0].generated).to eq("Yes")
        expect(res.objects[0].belongs_to_group).to eq("apples are big")
      else
        expect { query.call }.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
      end
    end

    it "test_near_object_generate_with_everything" do
      collection = openai_collection(
        vectorizer_config: Config::Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false)
      )

      ret = collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "cats are small. you cannot eat cats.",
                                       "content" => "bananas are the smallest and smaller than everything else" })
        ]
      )

      res = collection.generate.near_object(
        ret.uuids[1],
        single_prompt: "Are cats mentioned in {text} of the given object? Only answer yes if there is the word cat or " \
                       "cats and no if not. Dont use punctuation",
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space from " \
                      "biggest to smallest",
        grouped_properties: ["text"]
      )
      expect(res.generated).to eq("apples cats")
      expect(res.objects[0].generated).not_to be_nil
      expect(res.objects[1].generated).not_to be_nil
    end

    it "test_near_object_generate_and_group_by_with_everything" do
      collection = openai_collection(
        vectorizer_config: Config::Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false)
      )

      ret = collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big. you can eat apples",
                                       "content" => "Teddy is the biggest and bigger than everything else" }),
          DataObject.new(properties: { "text" => "cats are small. you cannot eat cats",
                                       "content" => "bananas are the smallest and smaller than everything else" })
        ]
      )

      res = collection.generate.near_object(
        ret.uuids[1],
        single_prompt: "Is there something to eat in {text} in the given object? Only answer yes if there is " \
                       "something to eat or no if not without punctuation",
        grouped_task: "What is the biggest and what is the smallest? Only write the names separated by a space from " \
                      "biggest to smallest",
        grouped_properties: ["text"],
        group_by: GroupBy.new(prop: "text", number_of_groups: 2, objects_per_group: 1)
      )
      expect(res.generated).to eq("apples cats")
      expect(res.groups.length).to eq(2)
      groups = res.groups.values
      expect(groups[0].generated).not_to be_nil
      expect(groups[1].generated).not_to be_nil
    end

    it "test_near_text_generate_with_everything" do
      collection = openai_collection(
        vectorizer_config: Config::Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false)
      )

      collection.data.insert_many(
        [
          DataObject.new(properties: {
                           "text" => "melons are big",
                           "content" => "Teddy is the biggest and bigger than everything else. Teddy is not a fruit"
                         }),
          DataObject.new(properties: {
                           "text" => "cats are small. You cannot eat cats. Cats are not fruit",
                           "content" => "bananas are the smallest and smaller than everything else"
                         })
        ]
      )

      res = collection.generate.near_text(
        "small fruit",
        single_prompt: "Is there something to eat in {text} of the given object? Only answer yes if there is " \
                       "something to eat and no if not. Dont use punctuation",
        grouped_task: "Write out the fruit in alphabetical order. Only write the names separated by a space"
      )
      expect(res.generated).to eq("bananas melons")
      expect(res.objects[0].generated).not_to be_nil
      expect(res.objects[1].generated).not_to be_nil
      expect(res.objects[0].generated.downcase).to eq("no")
      expect(res.objects[1].generated.downcase).to eq("yes")
    end

    it "test_near_text_generate_and_group_by_with_everything" do
      collection = openai_collection(
        vectorizer_config: Config::Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false)
      )

      collection.data.insert_many(
        [
          DataObject.new(properties: {
                           "text" => "apples are big",
                           "content" => "Teddy is the biggest and bigger than everything else. Teddy is not a fruit"
                         }),
          DataObject.new(properties: {
                           "text" => "cats are small. you cannot eat cats. Cats are not fruit",
                           "content" => "bananas are the smallest and smaller than everything else"
                         })
        ]
      )

      res = collection.generate.near_text(
        "small fruit",
        single_prompt: "Is there something to eat in {text} of the given object? Only answer yes if there is " \
                       "something to eat and no if not. Dont use punctuation",
        grouped_task: "Write out the fruit in alphabetical order. Only write the names separated by a space",
        group_by: GroupBy.new(prop: "text", number_of_groups: 2, objects_per_group: 1)
      )
      expect(res.generated).to eq("apples bananas")
      expect(res.groups.length).to eq(2)
      groups = res.groups.values
      expect(groups[0].generated).not_to be_nil
      expect(groups[1].generated).not_to be_nil
      expect(groups[0].generated.downcase).to eq("no")
      expect(groups[1].generated.downcase).to eq("yes")
    end

    it "test_near_vector_generate_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" },
                         vector: [0.1, 0.2, 0.3, 0.4, 0.5]),
          DataObject.new(properties: { "text" => "cats are small. Cats are not fruit. You cannot eat cats",
                                       "content" => "bananas are the smallest and smaller than everything else" },
                         vector: [0.6, 0.7, 0.8, 0.9, 0.99])
        ]
      )

      res = collection.generate.near_vector(
        [0.1, 0.2, 0.3, 0.4, 0.6],
        single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no if " \
                       "not without punctuation",
        grouped_task: "Write out the fruit in the order in which they appear in the provided list. Only write the " \
                      "names separated by a space"
      )
      expect(res.generated).to eq("apples bananas")
      expect(res.objects[0].generated).to eq("Yes")
      expect(res.objects[1].generated).to eq("No")
    end

    it "test_near_vector_generate_and_group_by_with_everything" do
      collection = openai_collection

      collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big",
                                       "content" => "Teddy is the biggest and bigger than everything else" },
                         vector: [0.1, 0.2, 0.3, 0.4, 0.5]),
          DataObject.new(properties: { "text" => "cats are small. Cats are not a fruit, you cannot eat cats.",
                                       "content" => "bananas are the smallest and smaller than everything else" },
                         vector: [0.6, 0.7, 0.8, 0.9, 0.99])
        ]
      )

      res = collection.generate.near_vector(
        [0.1, 0.2, 0.3, 0.4, 0.6],
        single_prompt: "Is there something to eat in {text}? Only answer yes if there is something to eat or no if " \
                       "not without punctuation",
        grouped_task: "Write out the fruit in the order in which they appear in the provided list. Only write the " \
                      "names separated by a space",
        group_by: GroupBy.new(prop: "text", number_of_groups: 2, objects_per_group: 1)
      )
      expect(res.generated).to eq("apples bananas")
      expect(res.groups.length).to eq(2)
      expect(res.groups.values[0].generated).to eq("Yes")
      expect(res.groups.values[1].generated).to eq("No")
    end

    it "test_openai_invalid_key" do
      connect_to_docker_local(port: 8086, grpc_port: 50_057, headers: { "X-OpenAI-Api-Key" => "IamNotValid" }) do |client|
        client.collections.delete(node_name)
        collection = client.collections.create(
          node_name,
          properties: [Config::Property.new(name: "text", data_type: Config::DataType::TEXT)],
          generative_config: Config::Configure::Generative.openai,
          vectorizer_config: Config::Configure::Vectorizer.none
        )
        collection.data.insert({ "text" => "test" })
        expect do
          collection.generate.fetch_objects(single_prompt: "tell a joke based on {text}")
        end.to raise_error(Weaviate::Exceptions::WeaviateQueryError)
      end
    end

    it "test_openai_no_module" do
      connect_to_default_local(headers: { "X-OpenAI-Api-Key" => "doesnt matter" }) do |client|
        collection = client.collections.create(
          node_name,
          properties: [Config::Property.new(name: "text", data_type: Config::DataType::TEXT)],
          generative_config: Config::Configure::Generative.openai,
          vectorizer_config: Config::Configure::Vectorizer.none
        )
        begin
          collection.data.insert({ "text" => "test" })
          expect do
            collection.generate.fetch_objects(single_prompt: "tell a joke based on {text}")
          end.to raise_error(Weaviate::Exceptions::WeaviateQueryError)
        ensure
          client.collections.delete(node_name)
        end
      end
    end

    it "test_openai_batch_upload" do
      collection = openai_collection(vectorizer_config: Config::Configure::Vectorizer.text2vec_openai)

      ret = collection.data.insert_many(
        [
          DataObject.new(properties: { "text" => "apples are big" }),
          DataObject.new(properties: { "text" => "bananas are small" })
        ]
      )
      puts ret.errors if ret.has_errors
      expect(ret.has_errors).to be false

      objects = collection.query.fetch_objects(include_vector: true).objects
      expect(objects[0].vector).to include("default")
      expect(objects[0].vector["default"].length).to be > 0
    end

    # Runs the five generative queries with reranking shared by the Cohere / Contextual AI tests.
    def check_rerank_and_generative(collection)
      insert = collection.data.insert_many([{ "text" => "This is a test" }, { "text" => "This is another test" }])
      uuid1 = insert.uuids[0]
      vector1 = collection.query.fetch_object_by_id(uuid1, include_vector: true).vector
      expect(vector1).not_to be_nil

      rerank = Rerank.new(prop: "text", query: "another")
      [
        -> { collection.generate.bm25("test", rerank: rerank, single_prompt: "What is it? {text}") },
        -> { collection.generate.hybrid("test", rerank: rerank, single_prompt: "What is it? {text}") },
        -> { collection.generate.near_object(uuid1, rerank: rerank, single_prompt: "What is it? {text}") },
        -> { collection.generate.near_vector(vector1["default"], rerank: rerank, single_prompt: "What is it? {text}") },
        -> { collection.generate.near_text("test", rerank: rerank, single_prompt: "What is it? {text}") }
      ].each do |query|
        objects = query.call.objects
        expect(objects.length).to eq(2)
        expect(objects[0].metadata.rerank_score).not_to be_nil
        expect(objects[0].generated).not_to be_nil
        expect(objects[1].metadata.rerank_score).not_to be_nil
        expect(objects[1].generated).not_to be_nil

        with_another = objects.find { |obj| obj.properties["text"].include?("another") }
        without_another = objects.find { |obj| !obj.properties["text"].include?("another") }
        expect(with_another.metadata.rerank_score).to be > without_another.metadata.rerank_score
      end
    end

    it "test_queries_with_rerank_and_generative" do
      api_key = ENV.fetch("COHERE_APIKEY", nil)
      skip("No Cohere API key found.") if api_key.nil?

      collection = collection_factory(
        name: "Test_test_queries_with_rerank_and_generative",
        generative_config: Config::Configure::Generative.cohere,
        reranker_config: Config::Configure::Reranker.cohere,
        vectorizer_config: Config::Configure::Vectorizer.text2vec_cohere,
        properties: [Config::Property.new(name: "text", data_type: Config::DataType::TEXT)],
        ports: [8086, 50_057],
        headers: { "X-Cohere-Api-Key" => api_key }
      )
      skip("Generative reranking requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

      check_rerank_and_generative(collection)
    end

    grouped_variants = [
      ["string", lambda {
        "Write out the fruit in alphabetical order. Only write the names separated by a space"
      }],
      ["object", lambda {
        GenerativeParameters.grouped_task(
          "Write out the fruit in alphabetical order. Only write the names separated by a space", metadata: true
        )
      }]
    ]
    single_prompt = "Is there something to eat in {text} of the given object? Only answer yes if there is something " \
                    "to eat and no if not. Dont use punctuation"
    single_variants = [
      ["string", -> { single_prompt }],
      ["object", -> { GenerativeParameters.single_prompt(single_prompt, metadata: true, debug: true) }]
    ]
    # Python stacks parametrize(grouped) under parametrize(single): ids are single-grouped.
    single_variants.each do |single_id, make_single|
      grouped_variants.each do |grouped_id, make_grouped|
        it "test_near_text_generate_with_dynamic_rag[#{single_id}-#{grouped_id}]" do
          single = make_single.call
          grouped = make_grouped.call
          collection = openai_collection(
            vectorizer_config: Config::Configure::Vectorizer.text2vec_openai(vectorize_collection_name: false)
          )

          collection.data.insert_many(
            [
              DataObject.new(properties: {
                               "text" => "melons are big",
                               "content" => "Teddy is the biggest and bigger than everything else. Teddy is not a fruit"
                             }),
              DataObject.new(properties: {
                               "text" => "cats are small. You cannot eat cats. Cats are not fruit",
                               "content" => "bananas are the smallest and smaller than everything else"
                             })
            ]
          )

          query = lambda do
            collection.generate.near_text(
              "small fruit",
              single_prompt: single,
              grouped_task: grouped,
              generative_provider: GenerativeConfig.openai(temperature: 0.1)
            )
          end

          if server_version.is_lower_than(1, 30, 0)
            expect { query.call }.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
          else
            res = query.call
            # deprecated usage
            expect(res.generated).to eq("bananas melons")
            expect(res.objects[0].generated).not_to be_nil
            expect(res.objects[1].generated).not_to be_nil

            expect(res.generative).not_to be_nil
            expect(res.generative.text).to eq("bananas melons")

            if grouped.is_a?(String)
              expect(res.generative.metadata).to be_nil
            else
              expect(res.generative.metadata).to be_a(Weaviate::V1::GenerativeOpenAIMetadata)
            end

            g0 = res.objects[0].generative
            g1 = res.objects[1].generative

            expect(g0).not_to be_nil
            expect(g0.text).not_to be_nil
            expect(g1).not_to be_nil
            expect(g1.text).not_to be_nil

            if single.is_a?(String)
              expect(g0.debug).to be_nil
              expect(g0.metadata).to be_nil
              expect(g1.metadata).to be_nil
            else
              expect(g0.debug).not_to be_nil
              expect(g0.metadata).to be_a(Weaviate::V1::GenerativeOpenAIMetadata)
              expect(g1.debug).not_to be_nil
              expect(g1.metadata).to be_a(Weaviate::V1::GenerativeOpenAIMetadata)
            end
          end
        end
      end
    end

    [%w[text yes], %w[content no]].each do |parameter, answer|
      it "test_contextualai_generative_search_single[#{parameter}-#{answer}]" do
        # Contextual AI generative search with single prompt.
        api_key = ENV.fetch("CONTEXTUAL_API_KEY", nil)
        skip("No Contextual AI API key found.") if api_key.nil?

        collection = collection_factory(
          name: "TestContextualAIGenerativeSingle",
          generative_config: Config::Configure::Generative.contextualai(
            model: "v2", max_new_tokens: 100, temperature: 0.1,
            system_prompt: "You are a helpful assistant that provides accurate and informative responses based on " \
                           "the given context. Answer with yes or no only.",
            avoid_commentary: false
          ),
          vectorizer_config: Config::Configure::Vectorizer.none,
          properties: [
            Config::Property.new(name: "text", data_type: Config::DataType::TEXT),
            Config::Property.new(name: "content", data_type: Config::DataType::TEXT)
          ],
          headers: { "X-Contextual-Api-Key" => api_key },
          ports: [8086, 50_057]
        )
        skip("Generative search requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

        collection.data.insert_many(
          [
            DataObject.new(properties: { "text" => "bananas are great", "content" => "bananas are bad" }),
            DataObject.new(properties: { "text" => "apples are great", "content" => "apples are bad" })
          ]
        )

        res = collection.generate.fetch_objects(
          single_prompt: "is it good or bad based on {#{parameter}}? Just answer with yes or no without punctuation"
        )
        res.objects.each do |obj|
          expect(obj.generated).not_to be_nil
          expect(obj.generated.downcase).to eq(answer)
        end
        expect(res.generated).to be_nil
      end
    end

    it "test_contextualai_generative_with_knowledge_parameter" do
      # Contextual AI generative search with knowledge parameter override.
      api_key = ENV.fetch("CONTEXTUAL_API_KEY", nil)
      skip("No Contextual AI API key found.") if api_key.nil?

      collection = collection_factory(
        name: "TestContextualAIGenerativeKnowledge",
        generative_config: Config::Configure::Generative.contextualai(
          model: "v2", max_new_tokens: 100, temperature: 0.1, system_prompt: "You are a helpful assistant.",
          avoid_commentary: false
        ),
        vectorizer_config: Config::Configure::Vectorizer.none,
        properties: [Config::Property.new(name: "text", data_type: Config::DataType::TEXT)],
        headers: { "X-Contextual-Api-Key" => api_key },
        ports: [8086, 50_057]
      )
      skip("Generative search requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

      collection.data.insert_many([DataObject.new(properties: { "text" => "base knowledge" })])

      # Test with knowledge parameter override. Python passes `config=`, which generate.fetch_objects
      # does not accept; the runtime provider keyword is `generative_provider`.
      res = collection.generate.fetch_objects(
        single_prompt: "What is the custom knowledge?",
        generative_provider: GenerativeConfig.contextualai(knowledge: ["Custom knowledge override",
                                                                       "Additional context"])
      )
      res.objects.each do |obj|
        expect(obj.generated).not_to be_nil
        expect(obj.generated).to be_a(String)
      end
    end

    it "test_contextualai_generative_and_rerank_combined" do
      # Contextual AI generative search combined with reranking.
      contextual_api_key = ENV.fetch("CONTEXTUAL_API_KEY", nil)
      skip("No Contextual AI API key found.") if contextual_api_key.nil?

      collection = collection_factory(
        name: "TestContextualAIGenerativeAndRerank",
        generative_config: Config::Configure::Generative.contextualai(
          model: "v2", max_new_tokens: 100, temperature: 0.1,
          system_prompt: "You are a helpful assistant that provides accurate and informative responses based on the " \
                         "given context.",
          avoid_commentary: false
        ),
        reranker_config: Config::Configure::Reranker.contextualai(
          model: "ctxl-rerank-v2-instruct-multilingual",
          instruction: "Prioritize documents that contain the query term"
        ),
        vectorizer_config: Config::Configure::Vectorizer.text2vec_openai,
        properties: [Config::Property.new(name: "text", data_type: Config::DataType::TEXT)],
        headers: { "X-Contextual-Api-Key" => contextual_api_key },
        ports: [8086, 50_057]
      )
      skip("Generative reranking requires Weaviate 1.23.1 or higher") if server_version.is_lower_than(1, 23, 1)

      check_rerank_and_generative(collection)
    end
  end
end
