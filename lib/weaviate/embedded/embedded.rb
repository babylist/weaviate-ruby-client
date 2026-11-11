# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "logger"
require "net/http"
require "rbconfig"
require "rubygems/package"
require "socket"
require "uri"
require "zlib"

module Weaviate
  # Port of weaviate.embedded: downloads a Weaviate binary from GitHub releases,
  # caches it, and runs it as a child process.
  module Embedded
    DEFAULT_BINARY_PATH = File.join(Dir.home, ".cache/weaviate-embedded/")
    DEFAULT_PERSISTENCE_DATA_PATH = File.join(Dir.home, ".local/share/weaviate")
    GITHUB_RELEASE_DOWNLOAD_URL = "https://github.com/weaviate/weaviate/releases/download/"
    LATEST_RELEASE_URL = "https://api.github.com/repos/weaviate/weaviate/releases/latest"

    DEFAULT_PORT = 8079
    DEFAULT_GRPC_PORT = 50_060

    WEAVIATE_VERSION = "1.40.2"

    # v[one digit].[1-2 digits].[1-2 digits], optionally "-rc/alpha/beta.[1-2 digits]".
    VERSION_PATTERN = /\A\d\.\d{1,2}\.\d{1,2}?(-rc\.\d{1,2}|-beta\.\d{1,2}|-alpha\.\d{1,2}|)\z/

    class << self
      attr_writer :logger

      def logger
        @logger ||= Logger.new($stderr, level: Logger::WARN, progname: "weaviate-client")
      end

      # Python `platform.system()`: "Darwin", "Linux", "Windows", ...
      def platform_system
        case RbConfig::CONFIG["host_os"]
        when /darwin/i then "Darwin"
        when /linux/i then "Linux"
        when /mswin|mingw|cygwin/i then "Windows"
        else RbConfig::CONFIG["host_os"].to_s.capitalize
        end
      end

      # Python `platform.machine()`.
      def platform_machine
        RbConfig::CONFIG["host_cpu"]
      end

      # Python `urllib.request.urlretrieve`: download +url+ to +filename+ (following redirects).
      def urlretrieve(url, filename, redirects: 10)
        uri = URI.parse(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri)) do |res|
            case res
            when Net::HTTPRedirection
              raise Exceptions::WeaviateStartUpError, "Too many redirects downloading #{url}" if redirects.zero?

              return urlretrieve(URI.join(url, res["location"]).to_s, filename, redirects: redirects - 1)
            when Net::HTTPSuccess
              File.open(filename, "wb") { |f| res.read_body { |chunk| f.write(chunk) } }
            else
              raise Exceptions::WeaviateEmbeddedInvalidVersionError, url
            end
          end
        end
        filename
      end

      # Python `httpx.get`: returns a Weaviate::Connect::HTTPResponse.
      def http_get(url)
        uri = URI.parse(url)
        res = Net::HTTP.get_response(uri)
        Connect::HTTPResponse.new(res.code.to_i, res.body, res.each_header.to_h)
      end

      # Bind +port+ (0 lets the OS choose) on a socket that stays open until the sockets in
      # +held+ are closed. Returns the bound port.
      def hold_port(held, port = 0)
        raise RangeError, "port must be 0-65535" unless port.between?(0, 65_535)

        sock = Socket.new(:INET, :STREAM)
        held << sock
        sock.bind(Addrinfo.tcp("0.0.0.0", port))
        sock.local_address.ip_port
      end

      # Bind a free port and the port after it on sockets that stay open until +held+ is closed.
      def hold_consecutive_ports(held)
        100.times do
          first_port = Embedded.hold_port(held)
          begin
            return [first_port, Embedded.hold_port(held, first_port + 1)]
          rescue SystemCallError, SocketError, RangeError
            # The rejected first port stays held, so the OS offers a different one next.
            next
          end
        end
        raise Exceptions::WeaviateStartUpError, "Could not find two consecutive free ports for Weaviate"
      end

      # Free gossip, data, Raft, Raft internal RPC and profiling ports for one instance.
      #
      # The Weaviate server requires data = gossip + 1 and, in a local cluster, Raft internal
      # RPC = Raft + 1. All five ports are distinct and were free when chosen, but are released
      # before returning.
      def get_server_ports
        held = []
        gossip_port, data_port = Embedded.hold_consecutive_ports(held)
        raft_port, raft_internal_rpc_port = Embedded.hold_consecutive_ports(held)
        profiling_port = Embedded.hold_port(held)
        [gossip_port, data_port, raft_port, raft_internal_rpc_port, profiling_port]
      ensure
        held&.each { |s| s.close rescue nil } # rubocop:disable Style/RescueModifier
      end

      def get_random_port
        held = []
        Embedded.hold_port(held)
      ensure
        held&.each(&:close)
      end

      # Port of validators.url (simple form): an absolute http(s)/ftp URL with a host.
      def valid_url?(value)
        uri = URI.parse(value)
        %w[http https ftp].include?(uri.scheme) && !uri.host.to_s.empty?
      rescue URI::InvalidURIError
        false
      end

      # Extract the archive member +name+ from a .tar.gz file into +dest_dir+.
      def extract_tar_gz(archive, name, dest_dir)
        Zlib::GzipReader.open(archive) do |gz|
          Gem::Package::TarReader.new(gz) do |tar|
            tar.each do |entry|
              next unless entry.full_name == name || entry.full_name == "./#{name}"

              File.binwrite(File.join(dest_dir, name), entry.read.to_s)
              return
            end
          end
        end
        raise KeyError, "filename '#{name}' not found in #{archive}"
      end

      # Extract the archive member +name+ from a .zip file into +dest_dir+ (stored or deflated entries).
      def extract_zip(archive, name, dest_dir)
        data = File.binread(archive)
        eocd = data.rindex([0x06054b50].pack("V"))
        raise ArgumentError, "#{archive} is not a zip file" if eocd.nil?

        entries, cd_offset = data.byteslice(eocd + 10, 10).unpack("v x4 V")
        pos = cd_offset
        entries.times do
          raise ArgumentError, "corrupt zip central directory" unless data.byteslice(pos, 4).unpack1("V") == 0x02014b50

          method, comp_size, name_len, extra_len, comment_len, local_offset =
            data.byteslice(pos + 10, 36).unpack("v x8 V x4 v v v x8 V")
          entry_name = data.byteslice(pos + 46, name_len)
          pos += 46 + name_len + extra_len + comment_len
          next unless entry_name == name

          l_name_len, l_extra_len = data.byteslice(local_offset + 26, 4).unpack("v v")
          raw = data.byteslice(local_offset + 30 + l_name_len + l_extra_len, comp_size)
          content =
            case method
            when 0 then raw
            when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).then { |z| z.inflate(raw).tap { z.close } }
            else raise ArgumentError, "unsupported zip compression method #{method}"
            end
          File.binwrite(File.join(dest_dir, name), content)
          return
        end
        raise KeyError, "There is no item named '#{name}' in the archive"
      end

      # Terminate a child process and reap it, ignoring processes that are already gone.
      def terminate(pid)
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end

    # Port of weaviate.embedded.EmbeddedOptions.
    class EmbeddedOptions < ::Weaviate::Model
      attribute :persistence_data_path, default: -> { ENV.fetch("XDG_DATA_HOME", DEFAULT_PERSISTENCE_DATA_PATH) }
      attribute :binary_path, default: -> { ENV.fetch("XDG_CACHE_HOME", DEFAULT_BINARY_PATH) }
      attribute :version, default: WEAVIATE_VERSION
      attribute :port, default: DEFAULT_PORT
      attribute :hostname, default: "127.0.0.1"
      attribute :additional_env_vars, default: nil
      attribute :grpc_port, default: DEFAULT_GRPC_PORT

      def after_initialize
        self.persistence_data_path = DEFAULT_PERSISTENCE_DATA_PATH if persistence_data_path.nil?
        self.binary_path = DEFAULT_BINARY_PATH if binary_path.nil?
        self.version = WEAVIATE_VERSION if version.nil?
      end
    end

    # Port of weaviate.embedded._EmbeddedBase.
    class EmbeddedBase
      attr_reader :options, :grpc_port, :process, :download_url, :weaviate_binary_path, :parsed_weaviate_version

      def initialize(options)
        @options = options
        @grpc_port = options.grpc_port
        @process = nil
        # Data path that held Raft state before the most recent launch, set by #start.
        @existing_data_path = nil
        ensure_paths_exist
        self.class.check_supported_platform
        @parsed_weaviate_version = ""
        version = options.version

        if Embedded.valid_url?(version)
          raise Exceptions::WeaviateEmbeddedInvalidVersionError, version unless version.end_with?(".tar.gz", ".zip")

          # for GitHub urls we can parse the version from the url
          if version.start_with?(GITHUB_RELEASE_DOWNLOAD_URL)
            @parsed_weaviate_version = version.delete_prefix(GITHUB_RELEASE_DOWNLOAD_URL).split("/").first
          end
          @download_url = version
        elsif VERSION_PATTERN.match?(version)
          version_tag = "v#{version}"
          @parsed_weaviate_version = version_tag
          set_download_url_from_version_tag(version_tag)
        elsif version == "latest"
          response = Embedded.http_get(LATEST_RELEASE_URL)
          latest = Util.decode_json_response_dict(response, "get tag of latest weaviate release")
          version_tag = latest["tag_name"]
          @parsed_weaviate_version = version_tag
          set_download_url_from_version_tag(version_tag)
        else
          raise Exceptions::WeaviateEmbeddedInvalidVersionError, version
        end
      end

      def ensure_paths_exist
        FileUtils.mkdir_p(options.binary_path)
        FileUtils.mkdir_p(options.persistence_data_path)
      end

      def ensure_weaviate_binary_exists
        cache_key = @parsed_weaviate_version.empty? ? @download_url : @parsed_weaviate_version
        @weaviate_binary_path = File.join(
          options.binary_path, "weaviate-#{@parsed_weaviate_version}-#{Digest::SHA256.hexdigest(cache_key)}"
        )
        return if File.exist?(@weaviate_binary_path)

        Embedded.logger.info("Binary #{options.binary_path} did not exist. Downloading binary from #{@download_url}")
        if @download_url.end_with?(".tar.gz")
          archive = File.join(options.binary_path, "tmp_weaviate.tgz")
          Embedded.urlretrieve(@download_url, archive)
          Embedded.extract_tar_gz(archive, "weaviate", options.binary_path)
        else
          raise ArgumentError, "unsupported archive #{@download_url}" unless @download_url.end_with?(".zip")

          archive = File.join(options.binary_path, "tmp_weaviate.zip")
          Embedded.urlretrieve(@download_url, archive)
          Embedded.extract_zip(archive, "weaviate", options.binary_path)
        end
        FileUtils.rm_f(archive)

        File.rename(File.join(options.binary_path, "weaviate"), @weaviate_binary_path)
        # Ensuring weaviate binary is executable
        File.chmod(File.stat(@weaviate_binary_path).mode | 0o111, @weaviate_binary_path)
      end

      def wait_till_listening
        seconds = 30
        sleep_interval = 0.1
        retries = (seconds / sleep_interval).to_i
        while is_listening == false && retries.positive?
          sleep(sleep_interval)
          retries -= 1
        end
        return unless retries.zero?

        raise Exceptions::WeaviateStartUpError,
              "Embedded DB did not start listening on port #{options.port} within #{seconds} seconds"
      end

      def self.check_supported_platform
        return unless Embedded.platform_system == "Windows"

        raise Exceptions::WeaviateStartUpError,
              "Windows is not supported with EmbeddedDB. Please upvote this feature request if you want " \
              "this: https://github.com/weaviate/weaviate/issues/3315"
      end

      def stop
        return if @process.nil?

        Embedded.terminate(@process)
        @process = nil
      end

      def ensure_running
        return unless is_listening == false

        Embedded.logger.info("Embedded weaviate wasn't listening on ports http:#{options.port} & " \
                             "grpc:#{options.grpc_port}, so starting embedded weaviate again")
        start
      end

      def start
        ensure_weaviate_binary_exists
        my_env = ENV.to_h

        my_env["AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED"] ||= "true"
        my_env["QUERY_DEFAULTS_LIMIT"] ||= "20"
        my_env["PERSISTENCE_DATA_PATH"] ||= options.persistence_data_path
        # Weaviate exits at startup if any of its ports is taken, so every port is checked rather
        # than assumed free. With CLUSTER_IN_LOCALHOST, the server ignores RAFT_INTERNAL_RPC_PORT
        # when dialing and uses the Raft port + 1, so get_server_ports returns that pair.
        gossip_bind_port, data_bind_port, raft_port, raft_internal_rpc_port, profiling_port = Embedded.get_server_ports
        my_env["PROFILING_PORT"] ||= profiling_port.to_s
        my_env["CLUSTER_GOSSIP_BIND_PORT"] ||= gossip_bind_port.to_s
        my_env["CLUSTER_DATA_BIND_PORT"] ||= data_bind_port.to_s
        my_env["GRPC_PORT"] ||= grpc_port.to_s
        my_env["RAFT_BOOTSTRAP_EXPECT"] ||= "1"
        my_env["CLUSTER_IN_LOCALHOST"] ||= "True"
        my_env["RAFT_PORT"] ||= raft_port.to_s
        my_env["RAFT_INTERNAL_RPC_PORT"] ||= raft_internal_rpc_port.to_s
        my_env["ENABLE_MODULES"] ||=
          "text2vec-openai,text2vec-cohere,text2vec-huggingface,ref2vec-centroid,generative-openai,qna-openai," \
          "reranker-cohere"

        # A deterministic hostname allows running multiple parallel instances.
        cluster_hostname = "Embedded_at_#{options.port}"
        my_env["CLUSTER_HOSTNAME"] ||= cluster_hostname
        my_env["RAFT_JOIN"] ||= "#{cluster_hostname}:#{raft_port}"

        options.additional_env_vars&.each { |k, v| my_env[k.to_s] = v.to_s }

        # Check before launching, because Weaviate creates `raft/` during its own startup.
        data_path = my_env["PERSISTENCE_DATA_PATH"]
        @existing_data_path = File.directory?(File.join(data_path, "raft")) ? data_path : nil

        pid = Process.spawn(
          my_env, @weaviate_binary_path.to_s, "--host", options.hostname, "--port", options.port.to_s,
          "--scheme", "http", "--read-timeout=600s", "--write-timeout=600s"
        )
        @process = pid
        at_exit { Embedded.terminate(pid) if @process == pid }
        Embedded.logger.info("Started #{options.binary_path}: process ID #{pid}")
        wait_till_listening
      end

      # A hint to append to a startup timeout, or nil if the hint does not apply.
      def existing_data_hint
        return nil if @existing_data_path.nil?

        "The data path `#{@existing_data_path}` already holds data, which may have been created with a " \
          "different `port`. To run a separate instance, pass a different `persistence_data_path` and ports. " \
          "To use the existing data, pass the `port` it was created with."
      end

      def is_listening # rubocop:disable Naming/PredicatePrefix
        raise NotImplementedError
      end
      alias listening? is_listening

      private

      def set_download_url_from_version_tag(version)
        system = Embedded.platform_system
        if system == "Darwin"
          machine_type = "all"
          package_format = "zip"
        else
          machine_type = Embedded.platform_machine
          machine_type = "amd64" if machine_type == "x86_64"
          machine_type = "arm64" if machine_type == "aarch64"
          package_format = "tar.gz"
        end
        @download_url = "#{GITHUB_RELEASE_DOWNLOAD_URL}#{version}/weaviate-#{version}-#{system}-#{machine_type}." \
                        "#{package_format}"
      end

      def port_open?(port)
        Socket.tcp(options.hostname, port, connect_timeout: 1) { true }
      rescue SystemCallError, SocketError, IOError
        false
      end
    end

    # Port of weaviate.embedded.EmbeddedV3 (only checks the HTTP port).
    class EmbeddedV3 < EmbeddedBase
      def is_listening # rubocop:disable Naming/PredicatePrefix
        port_open?(options.port)
      end
      alias listening? is_listening

      def start
        if is_listening
          Embedded.logger.info("embedded weaviate is already listening on port #{options.port}")
          return
        end
        super
      end
    end
    EmbeddedDB = EmbeddedV3

    # Port of weaviate.embedded.EmbeddedV4 (checks both the HTTP and gRPC ports).
    class EmbeddedV4 < EmbeddedBase
      def is_listening # rubocop:disable Naming/PredicatePrefix
        http, grpc = listening_ports
        http && grpc
      end
      alias listening? is_listening

      def start
        http, grpc = listening_ports
        if http && grpc
          raise Exceptions::WeaviateStartUpError,
                "Embedded DB did not start because processes are already listening on ports " \
                "http:#{options.port} and grpc:#{grpc_port}" \
                "use Weaviate.connect_to_local(port: #{options.port}, grpc_port: #{options.grpc_port}) to connect " \
                "to the existing instance"
        elsif http
          raise Exceptions::WeaviateStartUpError,
                "Embedded DB did not start because a process is already listening on port http:#{options.port}" \
                "look for another free port for the HTTP connection to you embedded instance"
        elsif grpc
          raise Exceptions::WeaviateStartUpError,
                "Embedded DB did not start because a process is already listening on port grpc:#{grpc_port}" \
                "look for another free port for the gRPC connection to your embedded instance"
        end
        super
      end

      private

      def listening_ports
        [port_open?(options.port), port_open?(grpc_port)]
      end
    end
  end
end
