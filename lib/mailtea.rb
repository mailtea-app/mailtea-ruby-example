# A minimal Mailtea API client built on Ruby's standard library.
#
# There is no official Mailtea Ruby SDK, so this file is the whole client:
# net/http for the request, json for the body, and one error class. Copy it
# into your app and it works with no gems at all.

require "json"
require "net/http"
require "uri"

module Mailtea
  DEFAULT_BASE_URL = "https://api.mailtea.app"

  # Raised for any non-2xx response. `status` is the HTTP code and the message
  # is whatever the API said went wrong, so a rescue block can log something
  # actionable instead of "the request failed".
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      @status = status
      @body = body
      super(status ? "Mailtea API error #{status}: #{message}" : message)
    end
  end

  class Client
    # `base_url` only matters for local dev or a self-hosted Mailtea; in
    # production leave MAILTEA_API_BASE_URL unset and this falls back to the
    # public API.
    def initialize(api_key = ENV["MAILTEA_API_KEY"], base_url: ENV["MAILTEA_API_BASE_URL"])
      raise ArgumentError, "Missing API key. Set MAILTEA_API_KEY - see .env.example" if api_key.nil? || api_key.empty?

      @api_key = api_key
      @base_url = (base_url.nil? || base_url.empty? ? DEFAULT_BASE_URL : base_url).chomp("/")
    end

    # POST /v1/emails -> { "id" => "txemail_..." }
    #
    # `from`, `to` and `subject` are required; everything else the API accepts
    # (`html`, `text`, `reply_to`, `cc`, `bcc`, `tags`, `headers`,
    # `scheduled_at`, `attachments`) passes straight through as keywords.
    def send_email(from:, to:, subject:, **options)
      request(Net::HTTP::Post, "/v1/emails", { from: from, to: to, subject: subject }.merge(options))
    end

    # GET /v1/emails/:id -> the stored message, including `last_event`, which
    # is where the send got to: "queued", "scheduled", "sent", "delivered",
    # "bounced", "complained", "failed", "delivery_delayed", "suppressed" or
    # "canceled".
    def get_email(id)
      request(Net::HTTP::Get, "/v1/emails/#{URI.encode_www_form_component(id)}")
    end

    # POST /v1/emails/:id/cancel -> cancels a scheduled send. Only a message
    # still sitting at `last_event` "scheduled" can be cancelled: a send with no
    # `scheduled_at` is already on its way and answers 422, and so does a
    # scheduled one once its time has passed.
    def cancel_email(id)
      request(Net::HTTP::Post, "/v1/emails/#{URI.encode_www_form_component(id)}/cancel")
    end

    private

    def request(verb, path, payload = nil)
      uri = URI.join("#{@base_url}/", path.delete_prefix("/"))

      req = verb.new(uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"] = "application/json"
      if payload
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(payload)
      end

      response = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 10,
        read_timeout: 30
      ) { |http| http.request(req) }

      parsed = parse_body(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        message = parsed.is_a?(Hash) ? (parsed["error"] || parsed["message"]) : nil
        raise Error.new(message || response.message, status: response.code.to_i, body: parsed)
      end

      parsed
    rescue Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError => e
      # A dropped connection is as much a failed send as a 500, and callers
      # should only have to rescue one thing.
      raise Error, "Could not reach Mailtea at #{@base_url}: #{e.class}: #{e.message}"
    end

    def parse_body(raw)
      return nil if raw.nil? || raw.empty?

      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
