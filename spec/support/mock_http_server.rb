# frozen_string_literal: true

require "webrick"
require "json"
require "uri"

# Ruby stand-in for pytest-httpserver: register expectations, respond, and
# check that every request hit a handler.
class MockHTTPServer
  Request = Struct.new(:method, :path, :query, :headers, :body, keyword_init: true) do
    def json = body.to_s.empty? ? nil : JSON.parse(body)
  end

  class Handler
    attr_reader :calls

    def initialize(path, method:, query:, headers:, data:, json:)
      @path = path
      @method = method&.upcase
      @query = query
      @headers = headers&.transform_keys(&:downcase)
      @data = data
      @json = json
      @responder = ->(_req) { [500, {}, "no response configured"] }
      @calls = 0
    end

    def match?(req)
      return false unless @path.is_a?(Regexp) ? @path.match?(req.path) : @path == req.path
      return false if @method && @method != req.method
      return false if @query && URI.decode_www_form(req.query.to_s).to_h != @query.transform_keys(&:to_s).transform_values(&:to_s)
      return false if @headers && !@headers.all? { |k, v| req.headers[k] == v }
      return false if @data && req.body.to_s != @data
      return false if !@json.nil? && req.json != @json

      true
    end

    def respond_with_json(obj, status: 200, headers: {})
      @responder = ->(_req) { [status, { "content-type" => "application/json" }.merge(headers), JSON.generate(obj)] }
      self
    end

    def respond_with_data(body = "", status: 200, content_type: "text/plain", headers: {})
      @responder = ->(_req) { [status, { "content-type" => content_type }.merge(headers), body] }
      self
    end

    # block receives a MockHTTPServer::Request; return [status, headers, body]
    def respond_with_handler(&block)
      @responder = block
      self
    end

    def call(req)
      @calls += 1
      @responder.call(req)
    end
  end

  attr_reader :port, :log, :errors

  def initialize(host: "127.0.0.1", port: 23_536)
    @host = host
    @port = port
    @handlers = []
    @log = []
    @errors = []
    @lock = Mutex.new
    @server = WEBrick::HTTPServer.new(BindAddress: host, Port: port, Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [], DoNotReverseLookup: true)
    handler = WEBrick::HTTPServlet::ProcHandler.new(->(req, res) { dispatch(req, res) })
    %w[PUT DELETE PATCH OPTIONS].each do |m|
      handler.define_singleton_method(:"do_#{m}") { |req, res| do_GET(req, res) }
    end
    @server.mount("/", handler)
    @thread = Thread.new { @server.start }
    sleep 0.01 until @server.status == :Running
  end

  def url = "http://#{@host}:#{@port}"

  def expect_request(path, method: nil, query: nil, headers: nil, data: nil, json: nil)
    h = Handler.new(path, method: method, query: query, headers: headers, data: data, json: json)
    @lock.synchronize { @handlers << h }
    h
  end

  def clear
    @lock.synchronize do
      @handlers.clear
      @log.clear
      @errors.clear
    end
  end

  def check_assertions
    raise "Mock server received unexpected requests: #{@errors.map { |r| "#{r.method} #{r.path}" }.join(", ")}" unless @errors.empty?
  end

  def shutdown
    @server.shutdown
    @thread.join
  end

  private

  def dispatch(wreq, wres)
    headers = {}
    wreq.each { |k, v| headers[k.downcase] = v }
    req = Request.new(method: wreq.request_method, path: wreq.path, query: wreq.query_string, headers: headers,
                      body: wreq.body)
    handler = @lock.synchronize do
      @log << req
      @handlers.find { |h| h.match?(req) }
    end
    if handler.nil?
      @lock.synchronize { @errors << req }
      wres.status = 500
      wres.body = "No handler found for request #{req.method} #{req.path}"
      return
    end
    status, resp_headers, body = handler.call(req)
    wres.status = status
    resp_headers.each { |k, v| wres[k] = v }
    wres.body = body.to_s
  end
end
