#!/usr/bin/env ruby

require "json"

root = File.expand_path("..", __dir__)
source_paths = Dir[File.join(root, "CryptoLens/**/*.swift")]
project_path = File.join(root, "CryptoLens.xcodeproj/project.pbxproj")
info_path = File.join(root, "CryptoLens/Resources/Info.plist")
entitlements_path = File.join(root, "CryptoLens/Resources/CryptoLens.entitlements")
searchable = (source_paths + [project_path, info_path, entitlements_path]).to_h do |path|
  [path, File.read(path)]
end

forbidden = %w[
  SMAppService
  UNUserNotificationCenter
  BGTaskScheduler
  CloudKit
  com.apple.developer.icloud
  aps-environment
  BGTaskSchedulerPermittedIdentifiers
  x-cg-pro-api-key
  api.coingecko.com
  pro-api.coingecko.com
]

violations = forbidden.flat_map do |term|
  searchable.each_with_object([]) do |(path, content), found|
    found << "#{term}: #{path}" if content.include?(term)
  end
end
abort "Out-of-scope capabilities found:\n#{violations.join("\n")}" unless violations.empty?

project = File.read(project_path)
package_urls = project.scan(/repositoryURL = "([^"]+)";/).flatten
abort "Sparkle must be the only Swift package" unless package_urls == ["https://github.com/sparkle-project/Sparkle"]
abort "Sparkle must be pinned to 2.9.4" unless project.include?("kind = exactVersion; version = 2.9.4;")
abort "Sparkle product dependency is missing" unless project.include?("productName = Sparkle;")

resolved_paths = Dir[File.join(root, "**/Package.resolved")].reject { |path| path.include?("/.build/") }
abort "Expected one committed Package.resolved" unless resolved_paths.length == 1
pins = JSON.parse(File.read(resolved_paths.first)).fetch("pins")
expected_pin = pins.length == 1 &&
  pins.first["identity"] == "sparkle" &&
  pins.first.dig("state", "version") == "2.9.4"
abort "Package.resolved must pin only Sparkle 2.9.4" unless expected_pin

app_source = File.read(File.join(root, "CryptoLens/App/CryptoLensApp.swift"))
abort "Expected exactly one MenuBarExtra scene" unless app_source.scan(/\bMenuBarExtra\b/).length == 1
abort "Info.plist must declare LSUIElement" unless File.read(info_path).match?(/<key>LSUIElement<\/key>\s*<true\/>/)
abort "Deployment target must remain macOS 14.0" unless File.read(project_path).include?("MACOSX_DEPLOYMENT_TARGET = 14.0")
abort "Release must not inject base entitlements" unless File.read(project_path).include?("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO")
info = File.read(info_path)
abort "Sparkle feed must use the repository appcast" unless info.include?("https://raw.githubusercontent.com/YanYuanFE/crypto-lens/main/appcast.xml")
abort "Sparkle public key is missing" unless info.match?(/<key>SUPublicEDKey<\/key>\s*<string>[A-Za-z0-9+\/=]{40,}<\/string>/)

puts "Scope gate passed: local-only CoinMarketCap menu bar app with pinned Sparkle updates"
