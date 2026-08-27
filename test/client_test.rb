# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

require "mailtea"
require_relative "mock_mailtea"

class ClientTest < Minitest::Test
  def setup
    @mock = MockMailtea.new
    @mailtea = Mailtea::Client.new("mt_pat_test", base_url: @mock.url)
  end

  def teardown
    @mock.close
  end

  def test_send_posts_to_the_configured_base_url
    result = @mailtea.emails.send(
      from: "Acme <hello@acme.com>",
      to: "reader@acme.com",
      subject: "Hello from Ruby",
      html: "<p>Hi</p>"
    )

    request = @mock.last
    assert_equal "POST", request.method
    assert_equal "/v1/emails", request.path
    assert_equal "Bearer mt_pat_test", request.authorization
    assert_equal "Acme <hello@acme.com>", request.body["from"]
    assert_equal "reader@acme.com", request.body["to"]
    assert_equal "Hello from Ruby", request.body["subject"]
    assert_equal "<p>Hi</p>", request.body["html"]

    assert_equal MockMailtea::EMAIL_ID, result["id"]
  end

  def test_send_passes_optional_fields_through
    @mailtea.emails.send(
      from: "Acme <hello@acme.com>",
      to: ["one@acme.com", "two@acme.com"],
      subject: "Hello",
      text: "Hi",
      reply_to: "support@acme.com",
      tags: [{ name: "example", value: "ruby" }],
      scheduled_at: "2026-09-01T09:00:00Z"
    )

    body = @mock.last.body
    assert_equal ["one@acme.com", "two@acme.com"], body["to"]
    assert_equal "Hi", body["text"]
    assert_equal "support@acme.com", body["reply_to"]
    assert_equal [{ "name" => "example", "value" => "ruby" }], body["tags"]
    assert_equal "2026-09-01T09:00:00Z", body["scheduled_at"]
  end

  def test_get_reads_the_delivery_status
    email = @mailtea.emails.get("txemail_abc123")

    assert_equal "GET", @mock.last.method
    assert_equal "/v1/emails/txemail_abc123", @mock.last.path
    assert_equal "Bearer mt_pat_test", @mock.last.authorization
    # The SDK aliases the wire's last_event to a friendlier `status`.
    assert_equal "delivered", email["last_event"]
    assert_equal "delivered", email["status"]
  end

  def test_cancel_hits_the_cancel_route
    @mailtea.emails.cancel("txemail_abc123")

    assert_equal "POST", @mock.last.method
    assert_equal "/v1/emails/txemail_abc123/cancel", @mock.last.path
  end

  def test_a_non_2xx_response_raises_with_the_api_status_and_message
    # Pointed at a base URL the API does not serve, so the request 404s - the
    # branch send.rb rescues. It also proves a base URL with a path prefix
    # (a self-hosted Mailtea behind a proxy) is preserved.
    wrong = Mailtea::Client.new("mt_pat_test", base_url: "#{@mock.url}/not-the-api")

    error = assert_raises(Mailtea::Error) { wrong.emails.get("txemail_abc123") }

    assert_equal 404, error.status
    assert_equal "Not Found", error.message
    assert_equal "req_mock_1", error.request_id
    assert_equal "/not-the-api/v1/emails/txemail_abc123", @mock.last.path
  end

  # The README promises one rescue covers the send path, so a connection that
  # never lands has to surface as Mailtea::Error too - not a bare
  # Errno::ECONNREFUSED that send.rb would let through as a backtrace.
  def test_an_unreachable_api_raises_the_same_error_class
    dead = MockMailtea.new
    dead_url = dead.url
    dead.close

    client = Mailtea::Client.new("mt_pat_test", base_url: dead_url)

    error = assert_raises(Mailtea::Error) do
      client.emails.send(from: "Acme <hello@acme.com>", to: "reader@acme.com", subject: "Hello")
    end

    assert_equal 0, error.status
    assert_includes error.message, "Could not reach Mailtea at"
  end

  # MAILTEA_API_KEY has to be cleared for the duration. `Client.new(nil)` falls
  # back to the environment by design, so without this the assertion reads the
  # developer's shell instead of the code - and fails on the machine of anyone
  # who exported a key, which is exactly what setting this example up does.
  def test_the_client_refuses_to_start_without_an_api_key
    previous = ENV.delete("MAILTEA_API_KEY")

    assert_raises(Mailtea::Error) { Mailtea::Client.new(nil, base_url: @mock.url) }
    assert_raises(Mailtea::Error) { Mailtea::Client.new("", base_url: @mock.url) }
  ensure
    ENV["MAILTEA_API_KEY"] = previous
  end

  # send.rb is the file people copy, so run it end to end and check it prints
  # the id the API returned rather than trusting the client alone.
  def test_send_rb_runs_against_the_mock_and_prints_the_id
    root = File.expand_path("..", __dir__)
    env = {
      "MAILTEA_API_KEY" => "mt_pat_test",
      "MAILTEA_API_BASE_URL" => @mock.url,
      "MAILTEA_FROM" => "Acme <hello@acme.com>",
      "MAILTEA_TO" => "reader@acme.com",
      "MAILTEA_SUBJECT" => "Hello from Ruby"
    }

    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "send.rb", chdir: root)

    assert status.success?, "send.rb failed: #{stderr}"
    assert_includes stdout, "Sent: #{MockMailtea::EMAIL_ID}"
    assert_includes stdout, "Status: delivered"
    assert_includes stdout, "Cancelled: #{MockMailtea::EMAIL_ID}"

    routes = @mock.requests.map { |r| "#{r.method} #{r.path}" }
    assert_equal "POST /v1/emails", routes.first
    assert_includes routes, "GET /v1/emails/#{MockMailtea::EMAIL_ID}"
    assert_includes routes, "POST /v1/emails/#{MockMailtea::EMAIL_ID}/cancel"
    assert(@mock.requests.all? { |r| r.authorization == "Bearer mt_pat_test" })
  end
end
