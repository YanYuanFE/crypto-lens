#!/usr/bin/env ruby

require "json"
require "set"

root = File.expand_path("..", __dir__)
derived_data = File.expand_path(ARGV.fetch(0), root)
catalog_path = File.join(root, "CryptoLens/Resources/Localizable.xcstrings")
catalog = JSON.parse(File.read(catalog_path))

abort "Localizable.xcstrings sourceLanguage must be zh-Hans" unless catalog["sourceLanguage"] == "zh-Hans"

catalog_keys = Set.new(catalog.fetch("strings").keys)
pattern = File.join(
  derived_data,
  "Build/Intermediates.noindex/CryptoLens.build/*/CryptoLens.build/Objects-normal/*/*.stringsdata"
)
extracted_keys = Set.new
Dir[pattern].each do |path|
  data = JSON.parse(File.read(path))
  entries = data.dig("tables", "Localizable") || []
  entries.each { |entry| extracted_keys << entry.fetch("key") }
end

abort "No localization extraction data found under #{derived_data}" if extracted_keys.empty?

missing = extracted_keys - catalog_keys
unless missing.empty?
  abort "Missing String Catalog keys:\n#{missing.to_a.sort.map { |key| "- #{key}" }.join("\n")}"
end

puts "Localization gate passed: #{extracted_keys.length} extracted keys are present"
