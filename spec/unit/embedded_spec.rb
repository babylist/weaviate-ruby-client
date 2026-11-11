# frozen_string_literal: true

require "digest"
require "rubygems/package"
require "stringio"
require "tmpdir"
require "zlib"

# Port of test/test_embedded.py and test/test_embedded_cache.py
RSpec.describe Weaviate::Embedded do
  describe "server ports" do
    it "test_server_ports_are_distinct_with_consecutive_cluster_pairs" do
      gossip, data, raft, raft_rpc, profiling = described_class.get_server_ports

      expect(data).to eq(gossip + 1)
      expect(raft_rpc).to eq(raft + 1)
      expect([gossip, data, raft, raft_rpc, profiling].uniq.length).to eq(5)
    end

    it "test_server_ports_skip_gossip_port_when_next_port_is_taken" do
      calls = []
      allow(described_class).to receive(:hold_port).and_wrap_original do |original, held, port = 0|
        calls << port
        raise Errno::EADDRINUSE, "address already in use" if calls.length == 2

        original.call(held, port)
      end

      gossip, data, = described_class.get_server_ports

      rejected_gossip = calls[1] - 1
      expect(gossip).not_to eq(rejected_gossip)
      expect(data).to eq(gossip + 1)
    end
  end

  describe "binary cache" do
    # Minimal single-entry zip writer (stored, no compression).
    def write_zip(filename, name, payload)
      crc = Zlib.crc32(payload)
      local = [0x04034b50, 20, 0, 0, 0, 0, crc, payload.bytesize, payload.bytesize, name.bytesize, 0]
              .pack("VvvvvvVVVvv") + name + payload
      central = [0x02014b50, 20, 20, 0, 0, 0, 0, crc, payload.bytesize, payload.bytesize, name.bytesize, 0, 0, 0, 0,
                 0, 0].pack("VvvvvvvVVVvvvvvVV") + name
      eocd = [0x06054b50, 0, 0, 1, 1, central.bytesize, local.bytesize, 0].pack("VvvvvVVv")
      File.binwrite(filename, local + central + eocd)
    end

    def write_tar_gz(filename, name, payload)
      File.open(filename, "wb") do |f|
        Zlib::GzipWriter.wrap(f) do |gz|
          Gem::Package::TarWriter.new(gz) do |tar|
            tar.add_file_simple(name, 0o755, payload.bytesize) { |io| io.write(payload) }
          end
        end
      end
    end

    let!(:tmp_path) { Dir.mktmpdir }
    let(:downloads) { [] }

    after { FileUtils.remove_entry(tmp_path) }

    before do
      allow(described_class).to receive(:platform_system).and_return("Linux")
      allow(described_class).to receive(:urlretrieve) do |url, filename|
        downloads << url
        url.end_with?(".zip") ? write_zip(filename, "weaviate", url) : write_tar_gz(filename, "weaviate", url)
        filename
      end
    end

    def instance(version)
      Weaviate::Embedded::EmbeddedV4.new(
        Weaviate::Embedded::EmbeddedOptions.new(
          version: version, binary_path: File.join(tmp_path, "bin"), persistence_data_path: File.join(tmp_path, "data")
        )
      )
    end

    %w[tar.gz zip].each do |extension|
      [false, true].each do |different_host|
        it "test_custom_urls_select_their_own_binary[#{extension}-#{different_host}]" do
          urls = [
            "https://downloads.example.org/build-a/weaviate.#{extension}",
            if different_host
              "https://mirror.example.org/build-a/weaviate.#{extension}"
            else
              "https://downloads.example.org/build-b/weaviate.#{extension}"
            end
          ]
          selected = urls.map do |url|
            inst = instance(url)
            inst.ensure_weaviate_binary_exists
            File.binread(inst.weaviate_binary_path)
          end

          expect(selected).to eq(urls)
          expect(downloads).to eq(urls)
        end
      end

      it "test_repeated_custom_url_reuses_its_binary[#{extension}]" do
        url = "https://downloads.example.org/build-a/weaviate.#{extension}"
        2.times do
          inst = instance(url)
          inst.ensure_weaviate_binary_exists
          expect(File.binread(inst.weaviate_binary_path)).to eq(url)
          expect(File.executable?(inst.weaviate_binary_path)).to be(true)
        end

        expect(downloads).to eq([url])
      end

      it "test_custom_url_does_not_reuse_anonymous_legacy_binary[#{extension}]" do
        url = "https://downloads.example.org/build-a/weaviate.#{extension}"
        inst = instance(url)
        legacy = File.join(tmp_path, "bin", "weaviate--#{Digest::SHA256.hexdigest("")}")
        File.binwrite(legacy, "a different custom build")

        inst.ensure_weaviate_binary_exists

        expect(File.binread(inst.weaviate_binary_path)).to eq(url)
        expect(downloads).to eq([url])
        expect(File.binread(legacy)).to eq("a different custom build")
      end
    end

    [
      "1.39.7",
      "https://github.com/weaviate/weaviate/releases/download/v1.39.7/weaviate-v1.39.7-linux-amd64.tar.gz",
      "latest"
    ].each do |version|
      it "test_known_version_reuses_existing_cache[#{version}]" do
        allow(described_class).to receive(:http_get)
          .and_return(Weaviate::Connect::HTTPResponse.new(200, '{"tag_name": "v1.39.7"}'))
        inst = instance(version)
        cached = File.join(tmp_path, "bin", "weaviate-v1.39.7-#{Digest::SHA256.hexdigest("v1.39.7")}")
        File.binwrite(cached, "the cached official version")

        inst.ensure_weaviate_binary_exists

        expect(inst.weaviate_binary_path).to eq(cached)
        expect(File.binread(inst.weaviate_binary_path)).to eq("the cached official version")
        expect(downloads).to eq([])
      end
    end

    it "test_latest_resolves_current_version_before_reusing_cache" do
      tags = %w[v1.39.7 v1.40.0].each
      allow(described_class).to receive(:http_get) do
        Weaviate::Connect::HTTPResponse.new(200, JSON.generate({ "tag_name" => tags.next }))
      end
      FileUtils.mkdir_p(File.join(tmp_path, "bin"))
      %w[v1.39.7 v1.40.0].each do |tag|
        File.binwrite(File.join(tmp_path, "bin", "weaviate-#{tag}-#{Digest::SHA256.hexdigest(tag)}"), tag)
      end

      %w[v1.39.7 v1.40.0].each do |expected|
        inst = instance("latest")
        inst.ensure_weaviate_binary_exists
        expect(File.binread(inst.weaviate_binary_path)).to eq(expected)
      end

      expect(downloads).to eq([])
    end
  end

  describe "options and versions" do
    it "mirrors the Python defaults" do
      expect(described_class::WEAVIATE_VERSION).to eq("1.40.2")
      opts = Weaviate::Embedded::EmbeddedOptions.new
      expect(opts.port).to eq(8079)
      expect(opts.grpc_port).to eq(50_060)
      expect(opts.hostname).to eq("127.0.0.1")
    end

    it "builds platform download urls" do
      Dir.mktmpdir do |dir|
        opts = { binary_path: File.join(dir, "b"), persistence_data_path: File.join(dir, "d") }
        allow(described_class).to receive(:platform_system).and_return("Darwin")
        expect(Weaviate::Embedded::EmbeddedV4.new(Weaviate::Embedded::EmbeddedOptions.new(version: "1.30.1", **opts))
          .download_url).to eq("https://github.com/weaviate/weaviate/releases/download/v1.30.1/weaviate-v1.30.1-Darwin-all.zip")
        allow(described_class).to receive_messages(platform_system: "Linux", platform_machine: "x86_64")
        expect(Weaviate::Embedded::EmbeddedV4.new(Weaviate::Embedded::EmbeddedOptions.new(version: "1.30.1", **opts))
          .download_url).to eq("https://github.com/weaviate/weaviate/releases/download/v1.30.1/weaviate-v1.30.1-Linux-amd64.tar.gz")
        expect { Weaviate::Embedded::EmbeddedV4.new(Weaviate::Embedded::EmbeddedOptions.new(version: "bogus", **opts)) }
          .to raise_error(Weaviate::Exceptions::WeaviateEmbeddedInvalidVersionError)
        expect do
          Weaviate::Embedded::EmbeddedV4.new(Weaviate::Embedded::EmbeddedOptions.new(version: "https://x.org/w.exe", **opts))
        end.to raise_error(Weaviate::Exceptions::WeaviateEmbeddedInvalidVersionError)
      end
    end
  end
end
