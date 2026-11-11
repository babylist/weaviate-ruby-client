# frozen_string_literal: true

require "net/http"
require "openssl"
require "json"
require "uri"

module Weaviate
  module Connect
    # Minimal response wrapper used across the client (mirrors the bits of
    # httpx.Response the Python client relies on).
    class HTTPResponse
      attr_reader :status_code, :body, :headers

      def initialize(status_code, body, headers = {})
        @status_code = status_code
        @body = body
        @headers = headers
      end

      def json
        return nil if body.nil? || body.empty?

        JSON.parse(body)
      end

      def text = body.to_s
      def ok? = status_code.between?(200, 299)

      def inspect = "#<HTTPResponse #{status_code}>"
    end

    # Thread-safe keep-alive HTTP client built on Net::HTTP. Each thread keeps its
    # own persistent connection per origin.
    class HTTPClient
      class ConnectError < StandardError; end
      class ReadTimeout < StandardError; end

      METHODS = {
        "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PUT" => Net::HTTP::Put,
        "PATCH" => Net::HTTP::Patch, "DELETE" => Net::HTTP::Delete, "HEAD" => Net::HTTP::Head
      }.freeze

      attr_reader :default_headers

      def initialize(headers: {}, proxies: {}, connect_timeout: 5, retries: 3, ssl_ca_file: nil)
        @default_headers = headers
        @proxies = proxies
        @connect_timeout = connect_timeout
        @retries = retries
        @ssl_ca_file = ssl_ca_file
        @key = :"weaviate_http_#{object_id}"
        @all_connections = []
        @lock = Mutex.new
        @closed = false
      end

      def request(method, url, json: nil, params: nil, headers: nil, timeout: nil, body: nil, form: nil)
        raise RuntimeError, "client has been closed" if @closed

        uri = URI.parse(url)
        uri.query = URI.encode_www_form(params.compact) if params && !params.empty?
        req = METHODS.fetch(method).new(uri.request_uri)
        (headers || default_headers).each { |k, v| req[k.to_s] = v.to_s }
        if form
          req.set_form_data(form)
        elsif !json.nil?
          req.body = JSON.generate(json)
          req["content-type"] = "application/json"
        elsif body
          req.body = body
        end
        perform(uri, req, timeout)
      end

      def get(url, **opts) = request("GET", url, **opts)
      def post(url, **opts) = request("POST", url, **opts)

      def close
        @closed = true
        @lock.synchronize do
          @all_connections.each { |c| c.finish if c.started? rescue nil } # rubocop:disable Style/RescueModifier
          @all_connections.clear
        end
      end

      private

      def perform(uri, req, timeout)
        attempts = 0
        begin
          attempts += 1
          http = connection_for(uri)
          http.read_timeout = timeout if timeout
          http.write_timeout = timeout if timeout && http.respond_to?(:write_timeout=)
          res = http.request(req)
          HTTPResponse.new(res.code.to_i, res.body, res.each_header.to_h)
        rescue Net::ReadTimeout, Net::WriteTimeout => e
          drop_connection(uri)
          raise ReadTimeout, e.message
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, Net::OpenTimeout => e
          drop_connection(uri)
          raise ConnectError, e.message
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError => e
          drop_connection(uri)
          retry if attempts <= @retries
          raise ConnectError, e.message
        end
      end

      def conn_key(uri) = "#{uri.scheme}://#{uri.host}:#{uri.port}"

      def connection_for(uri)
        pool = (Thread.current[@key] ||= {})
        http = pool[conn_key(uri)]
        return http if http&.started?

        proxy = @proxies[uri.scheme]
        http =
          if proxy
            p = URI.parse(proxy)
            Net::HTTP.new(uri.host, uri.port, p.host, p.port, p.user, p.password)
          else
            Net::HTTP.new(uri.host, uri.port, nil)
          end
        http.use_ssl = uri.scheme == "https"
        http.ca_file = @ssl_ca_file if @ssl_ca_file
        http.open_timeout = @connect_timeout
        http.keep_alive_timeout = 30
        http.start
        pool[conn_key(uri)] = http
        @lock.synchronize { @all_connections << http }
        http
      end

      def drop_connection(uri)
        pool = Thread.current[@key] || {}
        http = pool.delete(conn_key(uri))
        http&.finish if http&.started?
      rescue StandardError
        nil
      end
    end
  end
end
