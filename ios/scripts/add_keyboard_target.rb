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
DEPLOYMENT_TARGET  = '15.5'
SWIFT_VERSION      = '5.0'
# Same team as Runner. Look this up once via:
#   xcrun security find-identity -v -p codesigning | grep "Apple Distribution"
# or read it off the Runner target's DEVELOPMENT_TEAM build setting.
DEVELOPMENT_TEAM   = '7T3XFY333F'
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

# Info.plist as a file ref (referenced via INFOPLIST_FILE build setting).
# No entitlements file in v187 — App Groups + bundle ID would need to
# be registered on the Apple Developer Portal first. Re-add an
# entitlements file once that's done; the source it loaded was at
# ios/ImHimKeyboard/ImHimKeyboard.entitlements in v186.
%w[Info.plist].each do |fname|
  next if group.files.any? { |f| f.path == fname }
  group.new_reference(fname)
end

# ── 3. Build settings for the extension target ───────────────────────────────
target.build_configurations.each do |cfg|
  cfg.build_settings.merge!({
    'PRODUCT_NAME'                        => EXTENSION_NAME,
    'PRODUCT_BUNDLE_IDENTIFIER'           => EXTENSION_BUNDLE_ID,
    'INFOPLIST_FILE'                      => "#{EXTENSION_NAME}/Info.plist",
    'SWIFT_VERSION'                       => SWIFT_VERSION,
    'IPHONEOS_DEPLOYMENT_TARGET'          => DEPLOYMENT_TARGET,
    'TARGETED_DEVICE_FAMILY'              => '1,2',
    'SKIP_INSTALL'                        => 'YES',
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS'             => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
    'CODE_SIGN_STYLE'                     => 'Automatic',
    'DEVELOPMENT_TEAM'                    => DEVELOPMENT_TEAM,
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

# ── 6. Save ──────────────────────────────────────────────────────────────────
project.save
puts
puts 'OK — ImHimKeyboard target wired into Runner.xcodeproj.'
puts 'Before the next Codemagic build:'
puts "  1. Register bundle id #{EXTENSION_BUNDLE_ID} on the Apple Developer"
puts '     portal (Certificates / IDs / App IDs). Can be done from the'
puts '     Apple Developer iOS app on your phone.'
puts '  2. Have Codemagic / Xcode regenerate the App Store provisioning'
puts '     profile so it includes the new bundle id.'
puts '  3. (Optional, only if you want shared state between the main app'
puts '     and the keyboard) register App Group group.com.mirrorly.app.shared'
puts '     on the same dev portal, then add the entitlements files back'
puts '     and uncomment the App Group lookup in RizzClient.swift.'
