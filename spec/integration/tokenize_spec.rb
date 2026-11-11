# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_tokenize.py
#
# These tests cover the client's responsibilities:
# - Correct serialization of inputs (enums, TextAnalyzerConfigCreate, StopwordsCreate)
# - Correct deserialization of responses into the TokenizeResult object
# - Client-side validation (TextAnalyzerConfigCreate, stopwords/stopword_presets mutex)
# - Version gate (>= 1.37.0)
#
# Server-side behavior this client relies on:
# - Word tokenization defaults to preset "en" when no stopword config is sent.
# - Both endpoints return only `indexed` and `query`.
# - `stopwords` and `stopword_presets` are mutually exclusive on the generic
#   endpoint — the server rejects requests that set both.
RSpec.describe "tokenize", :integration do # rubocop:disable RSpec/DescribeClass
  tok = Weaviate::Classes::Tokenization
  cfg = Weaviate::Classes::Config

  let(:client) { client_factory }

  def require_1_37
    skip("Tokenization requires Weaviate >= 1.37.0") if client.connection.weaviate_version.is_lower_than(1, 37, 0)
  end

  # Collection with a `recipe` word-tokenized property and an en + ["quick"] stopwords config.
  def recipe_collection
    cfg = Weaviate::Classes::Config
    tok = Weaviate::Classes::Tokenization
    collection_factory(
      properties: [
        cfg::Property.new(name: "recipe", data_type: cfg::DataType::TEXT, tokenization: tok::Tokenization::WORD)
      ],
      inverted_index_config: cfg::Configure.inverted_index(
        stopwords_preset: tok::StopwordsPreset::EN, stopwords_additions: ["quick"]
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  describe "TestSerialization" do
    before { require_1_37 }

    describe "test_tokenization_enum" do
      [
        # "the" is an English stopword — filtered from the query output
        # by the server's default "en" preset for word tokenization.
        [tok::Tokenization::WORD, "The quick brown fox", %w[the quick brown fox], %w[quick brown fox]],
        # Non-word tokenizations do not apply the default "en" preset.
        [tok::Tokenization::LOWERCASE, "Hello World Test", %w[hello world test], %w[hello world test]],
        [tok::Tokenization::WHITESPACE, "Hello World Test", %w[Hello World Test], %w[Hello World Test]],
        [tok::Tokenization::FIELD, "  Hello World  ", ["Hello World"], ["Hello World"]],
        [tok::Tokenization::TRIGRAM, "Hello", %w[hel ell llo], %w[hel ell llo]]
      ].each do |tokenization, text, expected_indexed, expected_query|
        it "test_tokenization_enum[#{tokenization}]" do
          result = client.tokenization.text(text: text, tokenization: tokenization)
          expect(result).to be_a(tok::TokenizeResult)
          expect(result.indexed).to eq(expected_indexed)
          expect(result.query).to eq(expected_query)
        end
      end
    end

    describe "test_text_tokenize" do
      cases = lambda do
        {
          "default_en_applied_for_word" => [
            { text: "The quick brown fox" }, %w[the quick brown fox], %w[quick brown fox]
          ],
          "opt_out_of_default_en" => [
            { text: "The quick brown fox",
              analyzer_config: tok::TextAnalyzerConfigCreate.new(stopword_preset: tok::StopwordsPreset::NONE) },
            %w[the quick brown fox], %w[the quick brown fox]
          ],
          "ascii_fold" => [
            { text: "L'école est fermée", analyzer_config: tok::TextAnalyzerConfigCreate.new(ascii_fold: true) },
            %w[l ecole est fermee], %w[l ecole est fermee]
          ],
          "ascii_fold_with_ignore" => [
            { text: "L'école est fermée",
              analyzer_config: tok::TextAnalyzerConfigCreate.new(ascii_fold: true, ascii_fold_ignore: ["é"]) },
            %w[l école est fermée], %w[l école est fermée]
          ],
          "stopword_preset_enum" => [
            { text: "The quick brown fox",
              analyzer_config: tok::TextAnalyzerConfigCreate.new(stopword_preset: tok::StopwordsPreset::EN) },
            %w[the quick brown fox], %w[quick brown fox]
          ],
          "stopword_preset_string" => [
            { text: "The quick brown fox", analyzer_config: tok::TextAnalyzerConfigCreate.new(stopword_preset: "en") },
            %w[the quick brown fox], %w[quick brown fox]
          ],
          "ascii_fold_combined_with_stopwords" => [
            { text: "The école est fermée",
              analyzer_config: tok::TextAnalyzerConfigCreate.new(
                ascii_fold: true, ascii_fold_ignore: ["é"], stopword_preset: tok::StopwordsPreset::EN
              ) },
            %w[the école est fermée], %w[école est fermée]
          ],
          "stopwords_fallback" => [
            { text: "the quick brown fox",
              stopwords: tok::StopwordsCreate.new(preset: tok::StopwordsPreset::EN, additions: ["quick"],
                                                  removals: nil) },
            %w[the quick brown fox], %w[brown fox]
          ],
          "stopwords_additions_default_preset_to_en" => [
            { text: "the quick hello world",
              stopwords: tok::StopwordsCreate.new(preset: nil, additions: ["hello"], removals: nil) },
            %w[the quick hello world], %w[quick world]
          ],
          "stopwords_removals_default_preset_to_en" => [
            { text: "the quick is fast",
              stopwords: tok::StopwordsCreate.new(preset: nil, additions: nil, removals: ["the"]) },
            %w[the quick is fast], %w[the quick fast]
          ],
          "stopword_presets_named_reference" => [
            { text: "hello world test", analyzer_config: tok::TextAnalyzerConfigCreate.new(stopword_preset: "custom"),
              stopword_presets: { "custom" => ["test"] } },
            %w[hello world test], %w[hello world]
          ],
          "stopword_presets_override_builtin_en" => [
            { text: "the quick hello world", stopword_presets: { "en" => ["hello"] } },
            %w[the quick hello world], %w[the quick world]
          ]
        }
      end

      %w[default_en_applied_for_word opt_out_of_default_en ascii_fold ascii_fold_with_ignore stopword_preset_enum
         stopword_preset_string ascii_fold_combined_with_stopwords stopwords_fallback
         stopwords_additions_default_preset_to_en stopwords_removals_default_preset_to_en
         stopword_presets_named_reference stopword_presets_override_builtin_en].each do |id|
        it "test_text_tokenize[#{id}]" do
          call_kwargs, expected_indexed, expected_query = cases.call.fetch(id)
          result = client.tokenization.text(tokenization: tok::Tokenization::WORD, **call_kwargs)
          expect(result).to be_a(tok::TokenizeResult)
          expect(result.indexed).to eq(expected_indexed)
          expect(result.query).to eq(expected_query)
        end
      end
    end

    # Values round-tripped through config.get() feed back into tokenization.text().
    it "test_text_from_collection_config" do
      collection = recipe_collection
      config = collection.config.get
      recipe = config.properties.find { |p| p.name == "recipe" }
      stopwords = config.inverted_index_config.stopwords
      result = client.tokenization.text(
        text: "the quick brown fox", tokenization: recipe.tokenization, stopwords: stopwords
      )
      expect(result.indexed).to eq(%w[the quick brown fox])
      expect(result.query).to eq(%w[brown fox])
    end

    # Property endpoint (server resolves config from schema) produces the same indexed/query as the
    # generic endpoint fed the same config.
    it "test_property_and_generic_endpoints_agree" do
      collection = recipe_collection
      config = collection.config.get
      recipe = config.properties.find { |p| p.name == "recipe" }
      stopwords = config.inverted_index_config.stopwords

      text = "the quick brown fox"
      via_property = client.tokenization.for_property(collection: collection.name, property_name: "recipe", text: text)
      via_generic = client.tokenization.text(text: text, tokenization: recipe.tokenization, stopwords: stopwords)

      expect(via_property.indexed).to eq(via_generic.indexed)
      expect(via_property.query).to eq(via_generic.query)
    end
  end

  # ---------------------------------------------------------------------------
  # Deserialization
  # ---------------------------------------------------------------------------

  describe "TestDeserialization" do
    before { require_1_37 }

    # Property endpoint response deserializes into TokenizeResult — server resolves tokenization from
    # the property's schema.
    it "test_property_result_shape" do
      client.collections.delete("TestDeserPropTypes")
      begin
        client.collections.create_from_dict(
          {
            "class" => "TestDeserPropTypes",
            "vectorizer" => "none",
            "properties" => [{ "name" => "tag", "dataType" => ["text"], "tokenization" => "field" }]
          }
        )
        result = client.tokenization.for_property(collection: "TestDeserPropTypes", property_name: "tag",
                                                  text: "  Hello World  ")
        expect(result).to be_a(tok::TokenizeResult)
        expect(result.indexed).to eq(["Hello World"])
      ensure
        client.collections.delete("TestDeserPropTypes")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Client-side validation
  # ---------------------------------------------------------------------------

  describe "TestClientSideValidation" do
    # Python ValueError -> Ruby ArgumentError (ValidationError < ArgumentError).
    { "explicit_false" => { ascii_fold: false, ascii_fold_ignore: ["é"] },
      "default" => { ascii_fold_ignore: ["é"] } }.each do |id, kwargs|
      it "test_ascii_fold_ignore_without_fold_raises[#{id}]" do
        expect { tok::TextAnalyzerConfigCreate.new(**kwargs) }.to raise_error(ArgumentError, /asciiFoldIgnore/)
      end
    end

    {
      "fold_with_ignore" => [{ ascii_fold: true, ascii_fold_ignore: %w[é ñ] },
                             { asciiFold: true, asciiFoldIgnore: %w[é ñ] }],
      "fold_without_ignore" => [{ ascii_fold: true }, { asciiFold: true, asciiFoldIgnore: nil }],
      "stopword_preset_only" => [{ stopword_preset: "en" }, { stopwordPreset: "en" }],
      "empty" => [{}, { asciiFold: nil, asciiFoldIgnore: nil, stopwordPreset: nil }]
    }.each do |id, (kwargs, expected)|
      it "test_valid_config[#{id}]" do
        config = tok::TextAnalyzerConfigCreate.new(**kwargs)
        expected.each { |attr, value| expect(config.public_send(attr)).to eq(value) }
      end
    end

    # Client rejects the mutex violation locally with ValueError, before sending the request (which the
    # server would also reject with 422).
    it "test_stopwords_and_stopword_presets_mutex" do
      skip("Tokenization requires Weaviate >= 1.37.0") if client.connection.weaviate_version.is_lower_than(1, 37, 0)
      expect do
        client.tokenization.text(
          text: "hello",
          tokenization: tok::Tokenization::WORD,
          stopwords: tok::StopwordsCreate.new(preset: tok::StopwordsPreset::EN, additions: nil, removals: nil),
          stopword_presets: { "custom" => ["hello"] }
        )
      end.to raise_error(ArgumentError, /mutually exclusive/)
    end

    # Client rejects malformed stopword_presets values locally before sending — str would silently split
    # into characters; a pydantic model would serialize to field tuples.
    {
      "str_value" => -> { [{ "custom" => "hello" }, "must be a list of strings"] },
      "pydantic_model_value" => lambda {
        [{ "custom" => tok::StopwordsCreate.new(preset: tok::StopwordsPreset::EN, additions: nil, removals: nil) },
         "must be a list of strings"]
      },
      "non_string_element" => -> { [{ "custom" => ["hello", 123] }, "must contain only strings"] }
    }.each do |id, params|
      it "test_stopword_presets_invalid_shape_raises[#{id}]" do
        stopword_presets, match = params.call
        skip("Tokenization requires Weaviate >= 1.37.0") if client.connection.weaviate_version.is_lower_than(1, 37, 0)
        expect do
          client.tokenization.text(text: "hello", tokenization: tok::Tokenization::WORD,
                                   stopword_presets: stopword_presets)
        end.to raise_error(ArgumentError, Regexp.new(Regexp.escape(match)))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Version gate
  # ---------------------------------------------------------------------------

  # On Weaviate < 1.37 the client must raise before sending the request.
  describe "TestVersionGate" do
    it "test_text_raises_on_old_server" do
      if client.connection.weaviate_version.is_at_least(1, 37, 0)
        skip("Version gate only applies to Weaviate < 1.37.0")
      end
      expect do
        client.tokenization.text(text: "hello", tokenization: tok::Tokenization::WORD)
      end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
    end

    it "test_tokenize_property_raises_on_old_server" do
      if client.connection.weaviate_version.is_at_least(1, 37, 0)
        skip("Version gate only applies to Weaviate < 1.37.0")
      end
      expect do
        client.tokenization.for_property(collection: "Any", property_name: "title", text: "hello")
      end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
    end
  end

  # ---------------------------------------------------------------------------
  # Async client
  # ---------------------------------------------------------------------------

  # The Ruby port has no async client (PORTING.md: sync API only); these exercise the same calls
  # through the sync client.
  describe "TestAsyncClient" do
    before { require_1_37 }

    it "test_text_tokenize" do
      result = client.tokenization.text(text: "The quick brown fox", tokenization: tok::Tokenization::WORD)
      expect(result).to be_a(tok::TokenizeResult)
      expect(result.indexed).to eq(%w[the quick brown fox])
      # default "en" applied server-side.
      expect(result.query).to eq(%w[quick brown fox])
    end

    it "test_text_with_stopwords_fallback" do
      sw = tok::StopwordsCreate.new(preset: tok::StopwordsPreset::EN, additions: ["quick"], removals: nil)
      result = client.tokenization.text(text: "the quick brown fox", tokenization: tok::Tokenization::WORD,
                                        stopwords: sw)
      expect(result.indexed).to eq(%w[the quick brown fox])
      expect(result.query).to eq(%w[brown fox])
    end

    it "test_property_tokenize" do
      client.collections.delete("TestAsyncPropTokenize")
      begin
        client.collections.create_from_dict(
          {
            "class" => "TestAsyncPropTokenize",
            "vectorizer" => "none",
            "properties" => [
              { "name" => "title", "dataType" => ["text"], "tokenization" => "word",
                "textAnalyzer" => { "stopwordPreset" => "en" } }
            ]
          }
        )
        result = client.tokenization.for_property(collection: "TestAsyncPropTokenize", property_name: "title",
                                                  text: "The quick brown fox")
        expect(result).to be_a(tok::TokenizeResult)
        expect(result.indexed).to eq(%w[the quick brown fox])
        expect(result.query).to eq(%w[quick brown fox])
      ensure
        client.collections.delete("TestAsyncPropTokenize")
      end
    end
  end
end
