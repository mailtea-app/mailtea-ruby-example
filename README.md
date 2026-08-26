# Mailtea + Ruby Example

This example shows how to use [Mailtea](https://mailtea.app) with Ruby to send
transactional email, read a send's delivery status back, and cancel a scheduled
one — using nothing but the standard library.

There is no official Mailtea Ruby SDK. `lib/mailtea.rb` is the whole client:
about 100 lines of `net/http` and `json`, with one error class. Copy it into your
app; it needs no gems.

## Prerequisites

To get the most out of this guide, you'll need to:

- [Create an API key](https://studio.mailtea.app/api-keys)
- [Verify your domain](https://docs.mailtea.app/docs/documentation/domains)

Ruby 3.1 or newer. It was built and tested on Ruby 3.3.

## Instructions

1. Install dependencies — the example has none. For the tests:
   ```bash
   bundle install
   ```
2. Copy `.env.example` to `.env` and add your API key:
   ```bash
   cp .env.example .env
   ```
   Set `MAILTEA_FROM` to an address on your verified domain, and `MAILTEA_TO` to
   an inbox you can open.
3. Run it:
   ```bash
   ruby send.rb
   ```

```
Sent: txemail_ad6623a5f30e4639b95f7c1eb82a14e1
Status: queued
Scheduled: txemail_f387756a748249c08e88a781e30de159
Cancelled: txemail_f387756a748249c08e88a781e30de159
```

## The client

```ruby
require_relative "lib/mailtea"

mailtea = Mailtea::Client.new  # reads MAILTEA_API_KEY

sent = mailtea.send_email(
  from: "Acme <hello@acme.com>",
  to: "reader@yourdomain.com",
  subject: "Hello from Ruby",
  html: "<p>Sent with <strong>Ruby</strong> and the Mailtea API.</p>"
)

sent["id"]  # => "txemail_ad6623a5f30e4639b95f7c1eb82a14e1"
```

| Method | Endpoint |
|---|---|
| `send_email(from:, to:, subject:, **options)` | `POST /v1/emails` |
| `get_email(id)` | `GET /v1/emails/:id` |
| `cancel_email(id)` | `POST /v1/emails/:id/cancel` |

`to` takes a string or an array. Anything else the API accepts — `text`,
`reply_to`, `cc`, `bcc`, `tags`, `headers`, `scheduled_at`, `attachments` —
passes straight through as a keyword. SES caps a single message at **50
recipients combined** across `to` + `cc` + `bcc`.

`get_email` returns `last_event` — `queued`, `scheduled`, `sent`, `delivered`,
`bounced`, `complained`, `failed`, `delivery_delayed`, `suppressed` or
`canceled` — which is how you check on a send without waiting for a webhook.

`cancel_email` only works on a message whose `last_event` is still `scheduled`.
A send with no `scheduled_at` is queued for immediate delivery and cannot be
called back: it answers 422, and so does a scheduled one once its time has
passed.

### Errors

Every non-2xx response raises `Mailtea::Error`, carrying the HTTP status and the
API's own message — unverified domain, exhausted quota, malformed body. A
dropped connection raises the same class, so one rescue covers the send path:

```ruby
begin
  mailtea.send_email(from: from, to: to, subject: subject, html: html)
rescue Mailtea::Error => e
  warn e.message   # "Mailtea API error 422: Domain not verified"
  e.status         # 422
  e.body           # the parsed JSON response
end
```

### Pointing at a different Mailtea

Set `MAILTEA_API_BASE_URL` for local dev or a self-hosted instance; unset, the
client uses `https://api.mailtea.app`.

```ruby
Mailtea::Client.new(ENV["MAILTEA_API_KEY"], base_url: "http://localhost:7787")
```

## What this example covers

- Sending an email with `html`, `text`, and `tags`
- Reading a send's `last_event` back with `get_email`
- Scheduling a send with `scheduled_at`, then cancelling it
- Turning a non-2xx response into `Mailtea::Error` with the API's status and message
- Keeping the API key in the environment, never in code or in git

## Tests

```bash
ruby -Itest test/client_test.rb
```

The tests run against a bundled mock Mailtea server, so they need no API key
and make no network calls. They use minitest, which ships with Ruby, and
`test/mock_mailtea.rb` — a stdlib `TCPServer` on an ephemeral port, since
WEBrick stopped being a default gem in Ruby 3.0 and this example refuses to add
one. The last test runs `send.rb` itself against that mock and checks what it
prints.

## Learn more

- [Documentation](https://docs.mailtea.app)
- [API reference](https://docs.mailtea.app/docs/api-reference)
- [Node.js SDK](https://github.com/mailtea-app/mailtea-node) ·
  [Python SDK](https://github.com/mailtea-app/mailtea-python) ·
  [MCP server](https://github.com/mailtea-app/mailtea-mcp)
