#!/usr/bin/env ruby

release_path = File.expand_path("../docs/release.md", __dir__)
release = File.read(release_path)

required_urls = %w[
  https://pro.coinmarketcap.com/user-agreement-commercial/
  https://coinmarketcap.com/api/pricing/
  https://coinmarketcap.com/api/documentation/
  https://coinmarketcap.com/api/documentation/pro-api-reference/keyless-public-api
]
missing = required_urls.reject { |url| release.include?(url) }
abort "Release evidence is missing URLs: #{missing.join(", ")}" unless missing.empty?

if ARGV == ["--preflight"]
  abort "Release Owner is unassigned" if release.include?("Release Owner: **Unassigned**")
  abort "CoinMarketCap shipping/display conclusion is pending" if release.include?("Shipping/display conclusion: **Pending")
  abort "Release Owner preflight checklist is incomplete" unless release.include?(
    "- [x] Release Owner is named and has recorded the CoinMarketCap shipping/display conclusion."
  )
  puts "Release preflight passed"
  exit
end

abort "Usage: ruby scripts/verify_release.rb [--preflight]" unless ARGV.empty?
abort "Release status must be READY" unless release.match?(/^Status:\s+\*\*READY\*\*\s*$/)
abort "Release Owner is unassigned" if release.include?("Release Owner: **Unassigned**")
abort "Release checklist is incomplete" if release.include?("- [ ]")

puts "Release evidence gate passed"
