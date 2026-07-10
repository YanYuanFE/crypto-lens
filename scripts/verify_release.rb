#!/usr/bin/env ruby

release_path = File.expand_path("../docs/release.md", __dir__)
release = File.read(release_path)

required_urls = %w[
  https://www.coingecko.com/en/api_terms
  https://www.coingecko.com/en/terms
  https://www.coingecko.com/en/api/pricing
]
missing = required_urls.reject { |url| release.include?(url) }
abort "Release evidence is missing URLs: #{missing.join(", ")}" unless missing.empty?

if ARGV == ["--preflight"]
  abort "Release Owner is unassigned" if release.include?("Release Owner: **Unassigned**")
  abort "CoinGecko shipping/display conclusion is pending" if release.include?("Shipping/display conclusion: **Pending")
  abort "Release Owner preflight checklist is incomplete" unless release.include?(
    "- [x] Release Owner is named and has recorded the CoinGecko shipping/display conclusion."
  )
  puts "Release preflight passed"
  exit
end

abort "Usage: ruby scripts/verify_release.rb [--preflight]" unless ARGV.empty?
abort "Release status must be READY" unless release.match?(/^Status:\s+\*\*READY\*\*\s*$/)
abort "Release Owner is unassigned" if release.include?("Release Owner: **Unassigned**")
abort "Release checklist is incomplete" if release.include?("- [ ]")

puts "Release evidence gate passed"
