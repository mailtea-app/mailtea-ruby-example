# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.1"

# The official Mailtea Ruby SDK. It has no runtime dependencies of its own.
# Git coordinates until the gem is on RubyGems - switch to the registry form
# (gem "mailtea", "~> 0.1") once published.
gem "mailtea", git: "https://github.com/mailtea-app/mailtea-ruby", tag: "v0.1.0"

group :development, :test do
  # Ships with Ruby as a default gem; pinned here so CI resolves a known version.
  gem "minitest", "~> 5.20"
end
