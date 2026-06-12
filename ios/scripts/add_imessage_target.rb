#!/usr/bin/env ruby
# frozen_string_literal: true

# add_imessage_target.rb
#
# Adds the ImHimMessages iMessage-app extension target to
# ios/Runner.xcodeproj. Idempotent — safe to re-run.
#
# This is the RIGHT extension type for the "screenshot scan inside
# iMessage" feature, the way WingAI ships it. The earlier
# add_keyboard_target.rb (deleted) built a custom keyboard, which
# was the wrong surface.
#
# Usage (from repo root):
#   sudo gem install xcodeproj   # one-time
#   ruby ios/scripts/add_imessage_target.rb
#
# After running, Codemagic / Xcode still need:
#   1. The bundle id com.mirrorly.app.imessage registered on the
#      Apple Developer portal (App IDs → +). Can be done from the
#      Apple Developer iOS app on a phone.
#   2. A provisioning profile that covers that bundle id. Automatic
#      signing (Codemagic dashboard or Xcode) handles this once the
#      bundle id exists.

require 'xcodeproj'

PROJECT_PATH       = File.expand_path('../Runner.xcodeproj', __dir__)
EXTENSION_NAME     = 'ImHimMessages'
EXTENSION_BUNDLE_ID = 'com.mirrorly.app.imessage'
DEPLOYMENT_TARGET  = '15.5'
SWIFT_VERSION      = '5.0'
# Pull from Runner's existing build settings so we don't hardcode.
SOURCE_FILES = %w[
  MessagesViewController.swift
  ScreenshotScanner.swift
  RizzClient.swift
  Theme.swift
].freeze

abort "project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

# Inherit DEVELOPMENT_TEAM from Runner so signing has a chance.
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' if runner.nil?
runner_team = runner.build_configurations.map { |cfg|
  cfg.build_settings['DEVELOPMENT_TEAM']
}.compact.first || '7T3XFY333F'

# ── 1. Locate / create the extension target ──────────────────────────────────
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

# Link AGAINST the Messages framework — the iMessage app point identifier
# requires it, otherwise the loader refuses to instantiate the principal
# class at runtime.
%w[Messages.framework].each do |fname|
  next if target.frameworks_build_phase.files_references.any? { |f| f.path&.end_with?(fname) }
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fname}")
  ref.source_tree = 'SDKROOT'
  target.frameworks_build_phase.add_file_reference(ref)
  puts "linked #{fname}"
end

# ── 2. Group + file references ───────────────────────────────────────────────
group = project.main_group.find_subpath(EXTENSION_NAME, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(EXTENSION_NAME)

SOURCE_FILES.each do |fname|
  next if group.files.any? { |f| f.path == fname }
  file_ref = group.new_reference(fname)
  target.add_file_references([file_ref])
  puts "added source #{fname}"
end
unless group.files.any? { |f| f.path == 'Info.plist' }
  group.new_reference('Info.plist')
end

# ── 3. Build settings ────────────────────────────────────────────────────────
target.build_configurations.each do |cfg|
  cfg.build_settings.merge!({
    'PRODUCT_NAME'                          => EXTENSION_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'             => EXTENSION_BUNDLE_ID,
    'INFOPLIST_FILE'                        => "#{EXTENSION_NAME}/Info.plist",
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

# ── 4. Embed into Runner.app/PlugIns ─────────────────────────────────────────
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
  puts 'embedded ImHimMessages.appex into Runner.app/PlugIns'
end

# ── 5. Runner depends on extension so build order is right ───────────────────
unless runner.dependencies.any? { |d| d.target && d.target.name == EXTENSION_NAME }
  runner.add_dependency(target)
  puts 'Runner now depends on ImHimMessages'
end

project.save
puts
puts "OK - #{EXTENSION_NAME} target wired into Runner.xcodeproj."
puts "Bundle id: #{EXTENSION_BUNDLE_ID}"
puts 'Before the next Codemagic build:'
puts "  Register #{EXTENSION_BUNDLE_ID} on the Apple Developer portal."
puts '  (Certificates / IDs / App IDs / + - takes 30 seconds on phone.)'
puts '  Then Codemagic auto-fetches a profile on the next build.'
