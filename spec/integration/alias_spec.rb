# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_alias.py
RSpec.describe "alias", :integration do # rubocop:disable RSpec/DescribeClass
  let(:client) { client_factory }
  let(:none_vectorizer) { Weaviate::Classes::Config::Configure::Vectorizer.none }

  def node_name = RSpec.current_example.description
  def sanitize(name) = IntegrationContext.sanitize_collection_name(name)

  before do
    if client.connection.weaviate_version.is_lower_than(1, 32, 0)
      skip("Aliases are not supported in Weaviate versions < 1.32.0")
    end
  end

  it "test_alias_creation_and_deletion" do
    name = sanitize(node_name)
    name2 = sanitize("#{node_name}_2")
    alias1 = "Alias#{sanitize(node_name)}"
    alias2 = "Alias#{sanitize("#{node_name}_2")}"

    client.collections.delete(name)
    client.collections.delete(name2)
    client.alias.delete(alias_name: alias1)
    client.alias.delete(alias_name: alias2)

    begin
      client.collections.create(name, vectorizer_config: none_vectorizer)
      client.collections.create(name2, vectorizer_config: none_vectorizer)

      client.alias.create(alias_name: alias1, target_collection: name)
      client.alias.create(alias_name: alias2, target_collection: name2)
      all_alias = client.alias.list_all.select { |_, a| [name, name2].include?(a.collection) }
      expect(all_alias.length).to eq(2)
      expect(all_alias[alias1].alias).to eq(alias1)
      expect(all_alias[alias1].collection).to eq(name)

      collection_alias = client.alias.list_all(collection: name2)
      expect(collection_alias.length).to eq(1)
      expect(collection_alias[alias2].alias).to eq(alias2)

      expect(all_alias[alias2].alias).to eq(alias2)
      expect(all_alias[alias2].collection).to eq(name2)

      # Delete existing aliases
      expect(client.alias.delete(alias_name: alias1)).to be(true) if client.alias.exists(alias_name: alias1)
      expect(client.alias.delete(alias_name: alias2)).to be(true) if client.alias.exists(alias_name: alias2)
      all_alias = client.alias.list_all(collection: name2).select { |_, a| [name, name2].include?(a.collection) }
      expect(all_alias.length).to eq(0)

      expect(client.alias.delete(alias_name: alias1)).to be(false)
    ensure
      client.collections.delete(name)
      client.collections.delete(name2)
    end
  end

  it "test_alias_creation_and_update" do
    name = sanitize(node_name)
    name2 = sanitize("#{node_name}_2")
    alias1 = "Alias#{sanitize(node_name)}"

    client.collections.delete(name)
    client.collections.delete(name2)
    client.alias.delete(alias_name: alias1)

    begin
      client.collections.create(name, vectorizer_config: none_vectorizer)
      client.collections.create(name2, vectorizer_config: none_vectorizer)

      client.alias.create(alias_name: alias1, target_collection: name)
      alias_ = client.alias.get(alias_name: alias1)
      expect(alias_).not_to be_nil
      expect(alias_.alias).to eq(alias1)
      expect(alias_.collection).to eq(name)

      expect(client.alias.update(alias_name: alias1, new_target_collection: name2)).to be(true)
      alias_ = client.alias.get(alias_name: alias1)
      expect(alias_).not_to be_nil
      expect(alias_.alias).to eq(alias1)
      expect(alias_.collection).to eq(name2)

      # return status code not yet correct
      expect(client.alias.update(alias_name: "does_not_exist", new_target_collection: name2)).to be(false)
    ensure
      client.collections.delete(name)
      client.collections.delete(name2)
      client.alias.delete(alias_name: alias1)
    end
  end

  it "test_alias_get" do
    name = sanitize(node_name)
    alias1 = "Alias#{sanitize(node_name)}"

    client.collections.delete(name)
    client.alias.delete(alias_name: alias1)
    begin
      client.collections.create(name, vectorizer_config: none_vectorizer)

      client.alias.create(alias_name: alias1, target_collection: name)
      alias_ = client.alias.get(alias_name: alias1)
      expect(alias_).not_to be_nil
      expect(alias_.alias).to eq(alias1)
      expect(alias_.collection).to eq(name)
    ensure
      client.collections.delete(name)
      client.alias.delete(alias_name: alias1)
    end
  end

  it "test_alias_exists" do
    name = sanitize(node_name)
    alias1 = "Alias#{sanitize(node_name)}"

    client.collections.delete(name)
    client.alias.delete(alias_name: alias1)
    begin
      client.collections.create(name, vectorizer_config: none_vectorizer)

      client.alias.create(alias_name: alias1, target_collection: name)
      expect(client.alias.exists(alias_name: alias1)).to be(true)
    ensure
      client.collections.delete(name)
      client.alias.delete(alias_name: alias1)
      expect(client.alias.exists(alias_name: alias1)).to be(false)
    end
  end
end
