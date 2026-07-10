#!/usr/bin/env ruby

require "json"

root = File.expand_path("..", __dir__)
icon_dir = File.join(root, "CryptoLens/Resources/Assets.xcassets/AppIcon.appiconset")
manifest = JSON.parse(File.read(File.join(icon_dir, "Contents.json")))
images = manifest.fetch("images")
abort "AppIcon must define 10 macOS slots" unless images.length == 10

images.each do |image|
  abort "AppIcon slot must use the mac idiom" unless image.fetch("idiom") == "mac"
  logical_size = Integer(image.fetch("size").split("x").first)
  scale = Integer(image.fetch("scale").delete_suffix("x"))
  expected_pixels = logical_size * scale
  path = File.join(icon_dir, image.fetch("filename"))
  abort "Missing AppIcon image: #{path}" unless File.file?(path)

  data = File.binread(path)
  abort "Invalid PNG signature: #{path}" unless data.start_with?("\x89PNG\r\n\x1A\n".b)
  width, height = data.byteslice(16, 8).unpack("NN")
  abort "Wrong AppIcon size for #{path}: #{width}x#{height}" unless [width, height] == [expected_pixels, expected_pixels]
  abort "AppIcon image is unexpectedly small: #{path}" unless data.bytesize > 100
end

puts "Asset gate passed: 10 macOS AppIcon slots are present and dimensionally valid"
