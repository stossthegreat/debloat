#!/usr/bin/env ruby
# frozen_string_literal: true

# add_share_target.rb
#
# Wires the ImHimShare Share Extension target into
# ios/Runner.xcodeproj. Idempotent — re-running is safe.
#
# Usage (from repo root):
#   sudo gem install xcodeproj      # one-time on a fresh machine
#   ruby ios/scripts/add_share_target.rb
#
# After running:
#   1. Register the bundle id com.mirrorly.app.share AND the App Group
#      group.com.mirrorly.app.shared on the Apple Developer portal.
#      Apple Developer iOS app on a phone works.
#   2. Make sure your provisioning workflow regenerates profiles that
#      include the new bundle id + the App Groups capability.
#   3. Run the next CI build.

require 'xcodeproj'

PROJECT_PATH       = File.expand_path('../Runner.xcodeproj', __dir__)
EXTENSION_NAME     = 'ImHimShare'
EXTENSION_BUNDLE_ID = 'com.mirrorly.app.share'
DEPLOYMENT_TARGET  = '15.5'
SWIFT_VERSION      = '5.0'
APP_GROUP          = 'group.com.mirrorly.app.shared'
SOURCE_FILES = %w[ShareViewController.swift].freeze

abort "project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' if runner.nil?
runner_team = runner.build_configurations.map { |cfg|
  cfg.build_settings['DEVELOPMENT_TEAM']
}.compact.first || '7T3XFY333F'

# ── 1. Create / locate the extension target ─────────────────────────────────
target = project.targets.find { |t| t.name == EXTENSION_NAME }
if target.nil?
  puts "creating new target #{EXTENSION_NAME}"
  target = project.new_target(
    :app_extension,
    EXTENSION_NAME,
    :ios,
    DEPLOYMENT_TARGET
  )
else
  puts "target #{EXTENSION_NAME} already exists"
end

# Apple's Share Extension entry point requires Social.framework +
# UniformTypeIdentifiers (autolinks from Swift on iOS 15+).
%w[Social.framework].each do |fname|
  next if target.frameworks_build_phase.files_references.any? { |f| f.path&.end_with?(fname) }
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fname}")
  ref.source_tree = 'SDKROOT'
  target.frameworks_build_phase.add_file_reference(ref)
  puts "linked #{fname}"
end

# ── 2. Source group + file references ───────────────────────────────────────
group = project.main_group.find_subpath(EXTENSION_NAME, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(EXTENSION_NAME)

SOURCE_FILES.each do |fname|
  next if group.files.any? { |f| f.path == fname }
  file_ref = group.new_reference(fname)
  target.add_file_references([file_ref])
  puts "added source #{fname}"
end
%w[Info.plist ImHimShare.entitlements].each do |fname|
  next if group.files.any? { |f| f.path == fname }
  group.new_reference(fname)
end

# ── 3. Build settings ───────────────────────────────────────────────────────
target.build_configurations.each do |cfg|
  cfg.build_settings.merge!({
    'PRODUCT_NAME'                          => EXTENSION_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'             => EXTENSION_BUNDLE_ID,
    'INFOPLIST_FILE'                        => "#{EXTENSION_NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'                => "#{EXTENSION_NAME}/#{EXTENSION_NAME}.entitlements",
    'SWIFT_VERSION'                         => SWIFT_VERSION,
    'IPHONEOS_DEPLOYMENT_TARGET'            => DEPLOYMENT_TARGET,
    'TARGETED_DEVICE_FAMILY'                => '1,2',
    'SKIP_INSTALL'                          => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS'               => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    'CODE_SIGN_STYLE'                       => 'Automatic',
    'DEVELOPMENT_TEAM'                      => runner_team,
  })
end

# ── 4. Embed extension into Runner.app/PlugIns ──────────────────────────────
embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
if embed_phase.nil?
  puts 'creating Embed App Extensions copy phase on Runner'
  embed_phase = runner.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
embed_phase.symbol_dst_subfolder_spec ||= :plug_ins

product = target.product_reference
unless embed_phase.files_references.include?(product)
  build_file = embed_phase.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts 'embedded ImHimShare.appex into Runner.app/PlugIns'
end

# ── 5. Wire Runner → ImHimShare dependency ──────────────────────────────────
unless runner.dependencies.any? { |d| d.target && d.target.name == EXTENSION_NAME }
  runner.add_dependency(target)
  puts 'Runner now depends on ImHimShare'
end

# ── 6. Runner needs Runner.entitlements pointed at the App Group ────────────
runner.build_configurations.each do |cfg|
  cur = cfg.build_settings['CODE_SIGN_ENTITLEMENTS']
  if cur.nil? || cur.empty?
    cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  end
end

project.save
puts
puts "OK - #{EXTENSION_NAME} target wired into Runner.xcodeproj."
puts "Bundle id: #{EXTENSION_BUNDLE_ID}"
puts "App Group: #{APP_GROUP}"
puts
puts 'Before the next CI build, the Apple Developer portal needs:'
puts "  1. App ID #{EXTENSION_BUNDLE_ID} registered (App IDs / +)."
puts "  2. App Group #{APP_GROUP} registered (App Groups / +)."
puts "  3. App ID com.mirrorly.app capability ticked: App Groups."
puts '  Automatic provisioning regenerates the profile after that.'
