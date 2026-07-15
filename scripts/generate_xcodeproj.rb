#!/usr/bin/env ruby

require "digest"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
PROJECT_DIR = File.join(ROOT, "CryptoLens.xcodeproj")
PROJECT_FILE = File.join(PROJECT_DIR, "project.pbxproj")

def pbx_id(key)
  Digest::SHA1.hexdigest(key).upcase[0, 24]
end

def quote(value)
  %Q{"#{value.gsub('\\', '\\\\').gsub('"', '\\"')}"}
end

def file_type(path)
  case path
  when /\.swift$/ then "sourcecode.swift"
  when /\.xcassets$/ then "folder.assetcatalog"
  when /\.xcstrings$/ then "text.json.xcstrings"
  when /\.json$/ then "text.json"
  when /\.plist$/ then "text.plist.xml"
  when /\.entitlements$/ then "text.plist.entitlements"
  else "text"
  end
end

app_sources = Dir.chdir(ROOT) { Dir["CryptoLens/**/*.swift"].sort }
test_sources = Dir.chdir(ROOT) { Dir["CryptoLensTests/**/*.swift"].sort }
resources = Dir.chdir(ROOT) do
  Dir["CryptoLens/Resources/*"].select do |path|
    File.directory?(path) ? path.end_with?(".xcassets") : path.match?(/\.(xcstrings|json)$/)
  end.sort
end
support_files = Dir.chdir(ROOT) do
  Dir["CryptoLens/Resources/*"].select { |path| path.match?(/\.(plist|entitlements)$/) }.sort
end
all_files = app_sources + test_sources + resources + support_files

project_id = pbx_id("project")
main_group_id = pbx_id("main-group")
app_group_id = pbx_id("app-group")
tests_group_id = pbx_id("tests-group")
products_group_id = pbx_id("products-group")
app_product_id = pbx_id("app-product")
tests_product_id = pbx_id("tests-product")
app_target_id = pbx_id("app-target")
tests_target_id = pbx_id("tests-target")
app_sources_phase_id = pbx_id("app-sources-phase")
app_resources_phase_id = pbx_id("app-resources-phase")
app_frameworks_phase_id = pbx_id("app-frameworks-phase")
tests_sources_phase_id = pbx_id("tests-sources-phase")
tests_resources_phase_id = pbx_id("tests-resources-phase")
tests_frameworks_phase_id = pbx_id("tests-frameworks-phase")
target_proxy_id = pbx_id("tests-target-proxy")
target_dependency_id = pbx_id("tests-target-dependency")
sparkle_package_id = pbx_id("package:sparkle")
sparkle_product_id = pbx_id("package-product:sparkle")
sparkle_build_file_id = pbx_id("package-build-file:sparkle")

file_refs = all_files.to_h { |path| [path, pbx_id("file-ref:#{path}")] }
build_files = (app_sources + test_sources + resources).to_h do |path|
  [path, pbx_id("build-file:#{path}")]
end

project_debug_id = pbx_id("project-debug")
project_release_id = pbx_id("project-release")
app_debug_id = pbx_id("app-debug")
app_release_id = pbx_id("app-release")
tests_debug_id = pbx_id("tests-debug")
tests_release_id = pbx_id("tests-release")
project_config_list_id = pbx_id("project-config-list")
app_config_list_id = pbx_id("app-config-list")
tests_config_list_id = pbx_id("tests-config-list")

lines = []
lines << "// !$*UTF8*$!"
lines << "{"
lines << "\tarchiveVersion = 1;"
lines << "\tclasses = {};"
lines << "\tobjectVersion = 77;"
lines << "\tobjects = {"

lines << "\n/* Begin PBXBuildFile section */"
(app_sources + test_sources + resources).each do |path|
  phase = resources.include?(path) ? "Resources" : "Sources"
  lines << "\t\t#{build_files.fetch(path)} /* #{File.basename(path)} in #{phase} */ = {isa = PBXBuildFile; fileRef = #{file_refs.fetch(path)} /* #{File.basename(path)} */; };"
end
lines << "\t\t#{sparkle_build_file_id} /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = #{sparkle_product_id} /* Sparkle */; };"
lines << "/* End PBXBuildFile section */\n"

lines << "/* Begin PBXContainerItemProxy section */"
lines << "\t\t#{target_proxy_id} /* PBXContainerItemProxy */ = {"
lines << "\t\t\tisa = PBXContainerItemProxy;"
lines << "\t\t\tcontainerPortal = #{project_id} /* Project object */;"
lines << "\t\t\tproxyType = 1;"
lines << "\t\t\tremoteGlobalIDString = #{app_target_id};"
lines << "\t\t\tremoteInfo = CryptoLens;"
lines << "\t\t};"
lines << "/* End PBXContainerItemProxy section */\n"

lines << "/* Begin PBXFileReference section */"
all_files.each do |path|
  lines << "\t\t#{file_refs.fetch(path)} /* #{File.basename(path)} */ = {isa = PBXFileReference; lastKnownFileType = #{file_type(path)}; path = #{quote(path)}; sourceTree = \"<group>\"; };"
end
lines << "\t\t#{app_product_id} /* CryptoLens.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = CryptoLens.app; sourceTree = BUILT_PRODUCTS_DIR; };"
lines << "\t\t#{tests_product_id} /* CryptoLensTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = CryptoLensTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };"
lines << "/* End PBXFileReference section */\n"

[[app_frameworks_phase_id, ["#{sparkle_build_file_id} /* Sparkle in Frameworks */"]], [tests_frameworks_phase_id, []]].each do |phase_id, files|
  lines << "/* Begin PBXFrameworksBuildPhase section */" if phase_id == app_frameworks_phase_id
  lines << "\t\t#{phase_id} /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (#{files.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };"
end
lines << "/* End PBXFrameworksBuildPhase section */\n"

app_children = (app_sources + resources + support_files).map { |path| "#{file_refs.fetch(path)} /* #{File.basename(path)} */" }
test_children = test_sources.map { |path| "#{file_refs.fetch(path)} /* #{File.basename(path)} */" }
lines << "/* Begin PBXGroup section */"
lines << "\t\t#{main_group_id} = {isa = PBXGroup; children = (#{app_group_id} /* CryptoLens */, #{tests_group_id} /* CryptoLensTests */, #{products_group_id} /* Products */); sourceTree = \"<group>\"; };"
lines << "\t\t#{app_group_id} /* CryptoLens */ = {isa = PBXGroup; children = (#{app_children.join(', ')}); name = CryptoLens; sourceTree = \"<group>\"; };"
lines << "\t\t#{tests_group_id} /* CryptoLensTests */ = {isa = PBXGroup; children = (#{test_children.join(', ')}); name = CryptoLensTests; sourceTree = \"<group>\"; };"
lines << "\t\t#{products_group_id} /* Products */ = {isa = PBXGroup; children = (#{app_product_id} /* CryptoLens.app */, #{tests_product_id} /* CryptoLensTests.xctest */); name = Products; sourceTree = \"<group>\"; };"
lines << "/* End PBXGroup section */\n"

lines << "/* Begin PBXNativeTarget section */"
lines << "\t\t#{app_target_id} /* CryptoLens */ = {isa = PBXNativeTarget; buildConfigurationList = #{app_config_list_id}; buildPhases = (#{app_sources_phase_id}, #{app_frameworks_phase_id}, #{app_resources_phase_id}); buildRules = (); dependencies = (); name = CryptoLens; packageProductDependencies = (#{sparkle_product_id} /* Sparkle */); productName = CryptoLens; productReference = #{app_product_id}; productType = \"com.apple.product-type.application\"; };"
lines << "\t\t#{tests_target_id} /* CryptoLensTests */ = {isa = PBXNativeTarget; buildConfigurationList = #{tests_config_list_id}; buildPhases = (#{tests_sources_phase_id}, #{tests_frameworks_phase_id}, #{tests_resources_phase_id}); buildRules = (); dependencies = (#{target_dependency_id}); name = CryptoLensTests; productName = CryptoLensTests; productReference = #{tests_product_id}; productType = \"com.apple.product-type.bundle.unit-test\"; };"
lines << "/* End PBXNativeTarget section */\n"

lines << "/* Begin PBXProject section */"
lines << "\t\t#{project_id} /* Project object */ = {isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2660; LastUpgradeCheck = 2660; TargetAttributes = {#{app_target_id} = {CreatedOnToolsVersion = 26.0; }; #{tests_target_id} = {CreatedOnToolsVersion = 26.0; TestTargetID = #{app_target_id}; }; }; }; buildConfigurationList = #{project_config_list_id}; compatibilityVersion = \"Xcode 15.0\"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = (zh-Hans, Base); mainGroup = #{main_group_id}; packageReferences = (#{sparkle_package_id} /* XCRemoteSwiftPackageReference \"Sparkle\" */); productRefGroup = #{products_group_id}; projectDirPath = \"\"; projectRoot = \"\"; targets = (#{app_target_id}, #{tests_target_id}); };"
lines << "/* End PBXProject section */\n"

[[app_resources_phase_id, resources], [tests_resources_phase_id, []]].each_with_index do |(phase_id, paths), index|
  lines << "/* Begin PBXResourcesBuildPhase section */" if index.zero?
  refs = paths.map { |path| "#{build_files.fetch(path)} /* #{File.basename(path)} in Resources */" }
  lines << "\t\t#{phase_id} /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (#{refs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };"
end
lines << "/* End PBXResourcesBuildPhase section */\n"

[[app_sources_phase_id, app_sources], [tests_sources_phase_id, test_sources]].each_with_index do |(phase_id, paths), index|
  lines << "/* Begin PBXSourcesBuildPhase section */" if index.zero?
  refs = paths.map { |path| "#{build_files.fetch(path)} /* #{File.basename(path)} in Sources */" }
  lines << "\t\t#{phase_id} /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (#{refs.join(', ')}); runOnlyForDeploymentPostprocessing = 0; };"
end
lines << "/* End PBXSourcesBuildPhase section */\n"

lines << "/* Begin PBXTargetDependency section */"
lines << "\t\t#{target_dependency_id} /* PBXTargetDependency */ = {isa = PBXTargetDependency; target = #{app_target_id} /* CryptoLens */; targetProxy = #{target_proxy_id} /* PBXContainerItemProxy */; };"
lines << "/* End PBXTargetDependency section */\n"

def add_build_config(lines, id, name, settings)
  lines << "\t\t#{id} /* #{name} */ = {isa = XCBuildConfiguration; buildSettings = {"
  settings.each { |key, value| lines << "\t\t\t#{key} = #{value};" }
  lines << "\t\t}; name = #{name}; };"
end

project_settings = {
  "ALWAYS_SEARCH_USER_PATHS" => "NO",
  "CLANG_ENABLE_MODULES" => "YES",
  "CLANG_ENABLE_OBJC_ARC" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "SDKROOT" => "macosx",
  "SWIFT_STRICT_CONCURRENCY" => "complete"
}
app_settings = {
  "ASSETCATALOG_COMPILER_APPICON_NAME" => "AppIcon",
  "CODE_SIGN_ENTITLEMENTS" => quote("CryptoLens/Resources/CryptoLens.entitlements"),
  "CODE_SIGN_STYLE" => "Automatic",
  "CURRENT_PROJECT_VERSION" => "1",
  "ENABLE_HARDENED_RUNTIME" => "YES",
  "GENERATE_INFOPLIST_FILE" => "NO",
  "INFOPLIST_FILE" => quote("CryptoLens/Resources/Info.plist"),
  "LD_RUNPATH_SEARCH_PATHS" => quote("@executable_path/../Frameworks"),
  "MARKETING_VERSION" => "0.1.0",
  "PRODUCT_BUNDLE_IDENTIFIER" => "app.cryptolens",
  "PRODUCT_NAME" => "CryptoLens",
  "SWIFT_EMIT_LOC_STRINGS" => "YES",
  "SWIFT_VERSION" => "6.0"
}
test_settings = {
  "BUNDLE_LOADER" => quote("$(TEST_HOST)"),
  "CODE_SIGN_STYLE" => "Automatic",
  "GENERATE_INFOPLIST_FILE" => "YES",
  "MACOSX_DEPLOYMENT_TARGET" => "14.0",
  "PRODUCT_BUNDLE_IDENTIFIER" => "app.cryptolens.tests",
  "PRODUCT_NAME" => "CryptoLensTests",
  "SWIFT_VERSION" => "6.0",
  "TEST_HOST" => quote("$(BUILT_PRODUCTS_DIR)/CryptoLens.app/Contents/MacOS/CryptoLens")
}

lines << "/* Begin XCBuildConfiguration section */"
add_build_config(lines, project_debug_id, "Debug", project_settings.merge("DEBUG_INFORMATION_FORMAT" => "dwarf", "GCC_OPTIMIZATION_LEVEL" => "0", "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "DEBUG", "SWIFT_OPTIMIZATION_LEVEL" => quote("-Onone")))
add_build_config(lines, project_release_id, "Release", project_settings.merge("DEBUG_INFORMATION_FORMAT" => quote("dwarf-with-dsym"), "SWIFT_COMPILATION_MODE" => "wholemodule"))
add_build_config(lines, app_debug_id, "Debug", app_settings.merge("ENABLE_TESTABILITY" => "YES"))
add_build_config(lines, app_release_id, "Release", app_settings.merge("CODE_SIGN_INJECT_BASE_ENTITLEMENTS" => "NO"))
add_build_config(lines, tests_debug_id, "Debug", test_settings)
add_build_config(lines, tests_release_id, "Release", test_settings)
lines << "/* End XCBuildConfiguration section */\n"

lines << "/* Begin XCConfigurationList section */"
lines << "\t\t#{project_config_list_id} /* Build configuration list for PBXProject */ = {isa = XCConfigurationList; buildConfigurations = (#{project_debug_id}, #{project_release_id}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
lines << "\t\t#{app_config_list_id} /* Build configuration list for PBXNativeTarget CryptoLens */ = {isa = XCConfigurationList; buildConfigurations = (#{app_debug_id}, #{app_release_id}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
lines << "\t\t#{tests_config_list_id} /* Build configuration list for PBXNativeTarget CryptoLensTests */ = {isa = XCConfigurationList; buildConfigurations = (#{tests_debug_id}, #{tests_release_id}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };"
lines << "/* End XCConfigurationList section */\n"

lines << "/* Begin XCRemoteSwiftPackageReference section */"
lines << "\t\t#{sparkle_package_id} /* XCRemoteSwiftPackageReference \"Sparkle\" */ = {isa = XCRemoteSwiftPackageReference; repositoryURL = \"https://github.com/sparkle-project/Sparkle\"; requirement = {kind = exactVersion; version = 2.9.4; }; };"
lines << "/* End XCRemoteSwiftPackageReference section */\n"

lines << "/* Begin XCSwiftPackageProductDependency section */"
lines << "\t\t#{sparkle_product_id} /* Sparkle */ = {isa = XCSwiftPackageProductDependency; package = #{sparkle_package_id} /* XCRemoteSwiftPackageReference \"Sparkle\" */; productName = Sparkle; };"
lines << "/* End XCSwiftPackageProductDependency section */\n"

lines << "\t};"
lines << "\trootObject = #{project_id} /* Project object */;"
lines << "}"

FileUtils.mkdir_p(PROJECT_DIR)
File.write(PROJECT_FILE, lines.join("\n") + "\n")
puts "Generated #{PROJECT_FILE} with #{app_sources.length} app sources and #{test_sources.length} test sources"
