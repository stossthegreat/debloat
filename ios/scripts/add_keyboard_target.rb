#!/usr/bin/env ruby
# frozen_string_literal: true

# add_keyboard_target.rb
#
# Idempotent installer for the ImHimKeyboard custom-keyboard target. Run
# this once locally (or in CI before xcodebuild) and the target is
# added to ios/Runner.xcodeproj alongside the main Runner app.
#
# Usage (from repo root):
#   sudo gem install xcodeproj   # one-time
#   ruby ios/scripts/add_keyboard_target.rb
#
# Safe to re-run — the script checks for existing target + file refs
# before adding anything, so it's safe to wire into a CI step.

require 'xcodeproj'

PROJECT_PATH       = File.expand_path('../Runner.xcodeproj', __dir__)
EXTENSION_NAME     = 'ImHimKeyboard'
EXTENSION_BUNDLE_ID = 'com.mirrorly.app.keyboard'
APP_GROUP          = 'group.com.mirrorly.app.shared'
DEPLOYMENT_TARGET  = '15.5'
SWIFT_VERSION      = '5.0'
SOURCE_FILES = %w[
  KeyboardViewController.swift
  ScreenshotScanner.swift
  RizzClient.swift
  Theme.swift
].freeze

abort "project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

# ── 1. Locate / create the extension target ──────────────────────────────────
target = project.targets.find { |t| t.name == EXTENSION_NAME }
if target.nil?
  puts "+ creating new target #{EXTENSION_NAME}"
  target = project.new_target(
    :app_extension,
    EXTENSION_NAME,
    :ios,
    DEPLOYMENT_TARGET
  )
else
  puts "= target #{EXTENSION_NAME} already exists"
end

# ── 2. Group + file references ───────────────────────────────────────────────
group = project.main_group.find_subpath(EXTENSION_NAME, true)
group.set_source_tree('SOURCE_ROOT')
group.set_path(EXTENSION_NAME)

SOURCE_FILES.each do |fname|
  existing = group.files.find { |f| f.path == fname }
  next if existing
  file_ref = group.new_reference(fname)
  target.add_file_references([file_ref])
  puts "+ added source #{fname}"
end

# Info.plist + entitlements as file refs (not in build phases — they're
# referenced via INFOPLIST_FILE / CODE_SIGN_ENTITLEMENTS build settings).
%w[Info.plist ImHimKeyboard.entitlements].each do |fname|
  next if group.files.any? { |f| f.path == fname }
  group.new_reference(fname)
end

# ── 3. Build settings for the extension target ───────────────────────────────
target.build_configurations.each do |cfg|
  cfg.build_settings.merge!({
    'PRODUCT_NAME'                        => EXTENSION_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'           => EXTENSION_BUNDLE_ID,
    'INFOPLIST_FILE'                      => "#{EXTENSION_NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS'              => "#{EXTENSION_NAME}/#{EXTENSION_NAME}.entitlements",
    'SWIFT_VERSION'                       => SWIFT_VERSION,
    'IPHONEOS_DEPLOYMENT_TARGET'          => DEPLOYMENT_TARGET,
    'TARGETED_DEVICE_FAMILY'              => '1,2',
    'SKIP_INSTALL'                        => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS'             => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    'CODE_SIGN_STYLE'                     => 'Automatic',
  })
end

# ── 4. Embed extension into Runner.app/PlugIns ───────────────────────────────
runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found — is this a Flutter project?' if runner.nil?

embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
if embed_phase.nil?
  puts '+ creating Embed App Extensions copy phase on Runner'
  embed_phase = runner.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
embed_phase.symbol_dst_subfolder_spec ||= :plug_ins

product = target.product_reference
unless embed_phase.files_references.include?(product)
  build_file = embed_phase.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts '+ embedded ImHimKeyboard.appex into Runner.app/PlugIns'
end

# ── 5. Runner depends on extension so xcodebuild orders them right ───────────
unless runner.dependencies.any? { |d| d.target == target }
  runner.add_dependency(target)
  puts '+ Runner now depends on ImHimKeyboard'
end

# ── 6. Wire the App Group entitlements onto the Runner target ────────────────
#     The file already lives at ios/Runner/Runner.entitlements; we just need
#     the build setting to reference it.
runner.build_configurations.each do |cfg|
  cur = cfg.build_settings['CODE_SIGN_ENTITLEMENTS']
  if cur.nil? || cur.empty?
    cfg.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  end
end

# ── 7. Save ──────────────────────────────────────────────────────────────────
project.save
puts
puts 'OK — ImHimKeyboard target wired into Runner.xcodeproj.'
puts "App Group: #{APP_GROUP}"
puts 'Next:'
puts '  1. Open ios/Runner.xcworkspace in Xcode.'
puts '  2. Select Runner target → Signing & Capabilities → ensure App Group'
puts "     #{APP_GROUP} is checked. Repeat for ImHimKeyboard target."
puts '  3. Pick your team, let Xcode generate provisioning profiles.'
puts '  4. Build & run on a device (extensions can be flaky on simulator).'
