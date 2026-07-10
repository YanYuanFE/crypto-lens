#!/usr/bin/env ruby

release_path = File.expand_path("../docs/release.md", __dir__)
release = File.read(release_path)

abort "Release remains BLOCKED" if release.match?(/Status:\s+\*\*BLOCKED\*\*/)
abort "Release Owner is unassigned" if release.include?("Release Owner: **Unassigned**")
abort "Release checklist is incomplete" if release.include?("- [ ]")

required_urls = %w[
  https://www.coingecko.com/en/api_terms
  https://www.coingecko.com/en/terms
  https://www.coingecko.com/en/api/pricing
]
missing = required_urls.reject { |url| release.include?(url) }
abort "Release evidence is missing URLs: #{missing.join(", ")}" unless missing.empty?

puts "Release evidence gate passed"
