#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
source_paths = Dir[File.join(root, "CryptoLens/**/*.swift")]
project_path = File.join(root, "CryptoLens.xcodeproj/project.pbxproj")
info_path = File.join(root, "CryptoLens/Resources/Info.plist")
entitlements_path = File.join(root, "CryptoLens/Resources/CryptoLens.entitlements")
searchable = (source_paths + [project_path, info_path, entitlements_path]).to_h do |path|
  [path, File.read(path)]
end

forbidden = %w[
  XCRemoteSwiftPackageReference
  Sparkle
  SMAppService
  UNUserNotificationCenter
  BGTaskScheduler
  CloudKit
  com.apple.developer.icloud
  aps-environment
  BGTaskSchedulerPermittedIdentifiers
  x-cg-pro-api-key
  pro-api.coingecko.com
]

violations = forbidden.flat_map do |term|
  searchable.each_with_object([]) do |(path, content), found|
    found << "#{term}: #{path}" if content.include?(term)
  end
end
abort "Out-of-scope capabilities found:\n#{violations.join("\n")}" unless violations.empty?
abort "Package.resolved is forbidden in v1" unless Dir[File.join(root, "**/Package.resolved")].empty?

app_source = File.read(File.join(root, "CryptoLens/App/CryptoLensApp.swift"))
abort "Expected exactly one MenuBarExtra scene" unless app_source.scan(/\bMenuBarExtra\b/).length == 1
abort "Info.plist must declare LSUIElement" unless File.read(info_path).match?(/<key>LSUIElement<\/key>\s*<true\/>/)
abort "Deployment target must remain macOS 14.0" unless File.read(project_path).include?("MACOSX_DEPLOYMENT_TARGET = 14.0")
abort "Release must not inject base entitlements" unless File.read(project_path).include?("CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO")

puts "Scope gate passed: Apple-only, local-only, Demo-only menu bar app"
