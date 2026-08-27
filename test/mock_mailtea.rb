# A tiny stand-in for the Mailtea API, so the tests run with no credentials and
# no network. It records every request it receives, which is what the
# assertions read.
#
# This is the Ruby port of examples/.shared/node/mock-mailtea.mjs. WEBrick left
# Ruby's default gems in 3.0, so this uses TCPServer from the stdlib rather than
# asking the example to install a gem just to run its tests.

require "json"
require "socket"

class MockMailtea
  EMAIL_ID = "txemail_00000000000000000000000000000000".freeze

  Request = Struct.new(:method, :path, :authorization, :body, keyword_init: true)

  attr_reader :url

  def self.start
    server = new
    return server unless block_given?

    begin
      yield server
    ensure
      server.close
    end
  end

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @requests = []
    @mutex = Mutex.new
    @thread = Thread.new { accept_loop }
  end

  def requests
    @mutex.synchronize { @requests.dup }
  end

  # The most recent request, which is what most assertions want.
  def last
    requests.last
  end

  def close
    @server.close
    @thread.kill
  end

  private

  def accept_loop
    loop do
      socket = @server.accept
      Thread.new(socket) { |s| handle(s) }
    end
  rescue IOError, Errno::EBADF
    nil # the server was closed
  end

  def handle(socket)
    method, path = socket.gets.to_s.split(" ")

    headers = {}
    while (line = socket.gets) && line != "\r\n"
      key, value = line.split(":", 2)
      headers[key.to_s.strip.downcase] = value.to_s.strip
    end

    length = headers["content-length"].to_i
    raw = length.positive? ? socket.read(length) : nil
    body = raw ? (JSON.parse(raw) rescue raw) : nil

    authorization = headers["authorization"]
    @mutex.synchronize do
      @requests << Request.new(method: method, path: path, authorization: authorization, body: body)
    end

    status, payload = route(method, path, authorization)
    respond(socket, status, payload)
  ensure
    socket.close
  end

  def route(method, path, authorization)
    # Auth is checked first, the same way the real API does it - an example that
    # forgets the key should fail its test, not silently "send".
    return [401, { error: "Unauthorized" }] unless authorization.to_s.start_with?("Bearer ")

    return [200, { id: EMAIL_ID }] if method == "POST" && path == "/v1/emails"

    if method == "GET" && path =~ %r{\A/v1/emails/[^/]+\z}
      return [200, { object: "email", id: path.split("/").last, last_event: "delivered", subject: "Mock email" }]
    end

    # Cancel is POST /v1/emails/:id/cancel. There is no DELETE on emails - the
    # real API does not define one (apps/api/src/email-rest.ts).
    if method == "POST" && path =~ %r{\A/v1/emails/[^/]+/cancel\z}
      return [200, { object: "email", id: path.split("/")[3] }]
    end

    [404, { error: "Not Found", path: path }]
  end

  def respond(socket, status, payload)
    body = JSON.generate(payload)
    socket.print("HTTP/1.1 #{status}\r\n")
    socket.print("Content-Type: application/json\r\n")
    socket.print("Content-Length: #{body.bytesize}\r\n")
    # The real API stamps every response with one, and Mailtea::Error carries it
    # through for support tickets.
    socket.print("x-request-id: req_mock_1\r\n")
    socket.print("Connection: close\r\n\r\n")
    socket.print(body)
  end
end
