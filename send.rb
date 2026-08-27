# Sends one email, reads its status back, then schedules and cancels another.
#
#   bundle exec ruby send.rb
#
# Everything it needs comes from the environment (or a .env file next to this
# script) - see .env.example.

require "mailtea"

# Ruby has no built-in dotenv, and this example adds no gem for one, so read the
# file directly. Anything already exported wins, which is what you want in CI.
def load_dotenv(path = File.join(__dir__, ".env"))
  return unless File.exist?(path)

  File.foreach(path) do |line|
    next if line.strip.empty? || line.strip.start_with?("#")

    key, value = line.strip.split("=", 2)
    next if key.nil? || value.nil?

    # Strip the key too, or `MAILTEA_TO = you@yourdomain.com` sets "MAILTEA_TO "
    # and the script aborts telling you to set a variable you just set.
    ENV[key.strip] ||= value.strip.gsub(/\A["']|["']\z/, "")
  end
end

load_dotenv

def require_env(name, hint)
  value = ENV[name]
  abort "Set #{name} - #{hint}" if value.nil? || value.empty?

  value
end

FROM = require_env("MAILTEA_FROM", "an address on a domain you have verified in Mailtea.")
TO = require_env("MAILTEA_TO", "an inbox you can open. Never use @example.com, it has no MX record.")
SUBJECT = ENV.fetch("MAILTEA_SUBJECT", "Hello from Ruby")

# Reads MAILTEA_API_KEY, and MAILTEA_API_BASE_URL if you point it somewhere
# other than the production API.
mailtea = Mailtea::Client.new

begin
  sent = mailtea.emails.send(
    from: FROM,
    to: TO,
    subject: SUBJECT,
    html: "<p>Sent with <strong>Ruby</strong> and the Mailtea SDK.</p>",
    text: "Sent with Ruby and the Mailtea SDK.",
    tags: [{ name: "example", value: "ruby" }]
  )
  puts "Sent: #{sent["id"]}"

  # Delivery is asynchronous, so right after a send this is usually "queued".
  # Poll it, or subscribe to webhooks if you need to react to delivery.
  email = mailtea.emails.get(sent["id"])
  puts "Status: #{email["status"]}"

  # A scheduled send stays cancellable until it goes out.
  scheduled = mailtea.emails.send(
    from: FROM,
    to: TO,
    subject: "#{SUBJECT} (scheduled)",
    html: "<p>This one was queued ahead of time.</p>",
    scheduled_at: (Time.now.utc + 3600).strftime("%Y-%m-%dT%H:%M:%SZ")
  )
  puts "Scheduled: #{scheduled["id"]}"

  mailtea.emails.cancel(scheduled["id"])
  puts "Cancelled: #{scheduled["id"]}"
rescue Mailtea::Error => e
  # This is the branch worth copying: the API's own message tells you whether
  # the domain is unverified, the plan is out of quota, or the body was wrong.
  # A dropped connection raises the same class with status 0, so one rescue
  # covers the whole send path.
  warn "#{e.message} (status #{e.status}, request #{e.request_id})"
  exit 1
end
