#!/usr/bin/env ruby

require "date"
require "json"
require "net/http"
require "uri"

ROOT = File.expand_path("..", __dir__)
OUTPUT_PATH = File.join(ROOT, "CryptoLens/Resources/CuratedStockTokens.json")
API_URL = "https://api.coingecko.com/api/v3/coins/markets"
PER_PAGE = 250
VERIFIED_AT = ENV.fetch("CATALOG_VERIFIED_AT", Date.today.iso8601)

SOURCES = {
  "backed" => {
    category: "xstocks-ecosystem",
    issuer_url: "https://assets.backed.fi/products",
    minimum_count: 100
  },
  "ondo" => {
    category: "ondo-tokenized-assets",
    issuer_url: "https://docs.ondo.finance/ondo-stocks/available-assets",
    minimum_count: 400
  }
}.freeze

def fetch_category(category)
  rows = []
  page = 1

  loop do
    uri = URI(API_URL)
    uri.query = URI.encode_www_form(
      vs_currency: "usd",
      category: category,
      per_page: PER_PAGE,
      page: page
    )
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "CryptoLensCatalogUpdater/1.0"
    response = request_with_retry(uri, request, category)

    batch = JSON.parse(response.body)
    abort "Unexpected CoinGecko response for #{category}" unless batch.is_a?(Array)

    rows.concat(batch)
    break if batch.length < PER_PAGE

    sleep 2
    page += 1
  end

  rows
end

def request_with_retry(uri, request, category)
  4.times do |attempt|
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    return response if response.is_a?(Net::HTTPSuccess)

    retryable = response.code == "429" || response.code.start_with?("5")
    abort "CoinGecko request failed for #{category}: HTTP #{response.code}" unless retryable && attempt < 3

    retry_after = response["retry-after"].to_i
    wait_seconds = [retry_after, 5 * (attempt + 1)].max
    warn "CoinGecko HTTP #{response.code} for #{category}; retrying in #{wait_seconds}s"
    sleep wait_seconds
  end
end

entries = SOURCES.flat_map do |issuer, source|
  rows = fetch_category(source.fetch(:category))
  abort "#{issuer} inventory unexpectedly small: #{rows.length}" if rows.length < source.fetch(:minimum_count)

  rows.map do |row|
    coin_gecko_id = row.fetch("id")
    {
      "coinGeckoId" => coin_gecko_id,
      "symbol" => row.fetch("symbol").upcase,
      "name" => row.fetch("name"),
      "issuer" => issuer,
      "platform" => nil,
      "contractAddress" => nil,
      "verification" => {
        "verifiedAt" => VERIFIED_AT,
        "coinGeckoURL" => "https://www.coingecko.com/en/coins/#{coin_gecko_id}",
        "issuerURL" => source.fetch(:issuer_url)
      },
      "notes" => "CoinGecko category snapshot: #{source.fetch(:category)}"
    }
  end
end

duplicates = entries.group_by { |entry| entry.fetch("coinGeckoId") }.select { |_, matches| matches.length > 1 }
abort "Duplicate CoinGecko IDs: #{duplicates.keys.join(", ")}" unless duplicates.empty?

catalog = {
  "version" => 1,
  "updatedAt" => VERIFIED_AT,
  "entries" => entries.sort_by { |entry| [entry.fetch("issuer"), entry.fetch("coinGeckoId")] }
}

File.write(OUTPUT_PATH, JSON.pretty_generate(catalog) + "\n")
puts "Wrote #{entries.length} entries to #{OUTPUT_PATH}"
SOURCES.each_key do |issuer|
  puts "  #{issuer}: #{entries.count { |entry| entry.fetch("issuer") == issuer }}"
end
