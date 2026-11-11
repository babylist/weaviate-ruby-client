# frozen_string_literal: true

# Port of test/collection/test_iterator.py (the async iterator is out of scope)
RSpec.describe Weaviate::Collections::Iterator::ObjectIterator do
  let(:it_mod) { Weaviate::Collections::Iterator }

  def uuid_int(int) = format("00000000-0000-0000-0000-%012x", int)

  def inputs
    it_mod::IteratorInputs.new(include_vector: true, return_metadata: nil, return_properties: ["title"],
                               return_references: nil, after: uuid_int(1))
  end

  # Records fetch_objects calls and returns the queued pages.
  class FakeQuery
    attr_reader :calls

    def initialize(pages)
      @pages = pages
      @calls = []
    end

    def fetch_objects(**kwargs)
      @calls << kwargs
      Struct.new(:objects).new(@pages.shift)
    end
  end

  [false, true].each do |initially_empty|
    it "test_iterator_stays_exhausted_until_restarted[#{initially_empty}]" do
      obj = Struct.new(:uuid).new(uuid_int(2))
      earlier_obj = Struct.new(:uuid).new(uuid_int(3))
      first_page = initially_empty ? [] : [earlier_obj, obj]
      pages = [first_page]
      pages << [] unless initially_empty
      pages << [obj]
      query = FakeQuery.new(pages)
      iterator = described_class.new(query, inputs, cache_size: 5)
      iterator.rewind

      unless initially_empty
        expect(iterator.next).to equal(earlier_obj)
        expect(iterator.next).to equal(obj)
        expect(query.calls.length).to eq(1)
      end
      expect { iterator.next }.to raise_error(StopIteration)
      terminal_call_count = query.calls.length
      2.times { expect { iterator.next }.to raise_error(StopIteration) }
      expect(query.calls.length).to eq(terminal_call_count)
      expect(query.calls[0]).to eq(limit: 5, after: uuid_int(1), include_vector: true, return_metadata: nil,
                                   return_properties: ["title"], return_references: nil)
      expect(query.calls.last[:after]).to eq(obj.uuid) unless initially_empty

      iterator.rewind
      expect(iterator.next).to equal(obj)
      expect(query.calls.last[:after]).to eq(uuid_int(1))
    end
  end

  it "is Enumerable and restarts on each iteration" do
    a = Struct.new(:uuid).new(uuid_int(5))
    query = FakeQuery.new([[a], [], [a], []])
    iterator = described_class.new(query, inputs)
    expect(iterator.to_a).to eq([a])
    expect(iterator.map(&:uuid)).to eq([uuid_int(5)])
    expect(query.calls.map { |c| c[:limit] }.uniq).to eq([100])
  end
end
