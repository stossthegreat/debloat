#!/usr/bin/env ruby
# frozen_string_literal: true

# add_imessage_target.rb
#
# Wires the ImHimMessages iMessage-app extension into
# ios/Runner.xcodeproj. Idempotent.
#
# Run AFTER the bundle id com.mirrorly.app.imessage is registered on
# the Apple Developer portal. Same single-click flow as the share
# extension's bundle id was. Without that, the next CI build fails on
# signing.

require 'xcodeproj'

PROJECT_PATH       = File.expand_path('../Runner.xcodeproj', __dir__)
EXTENSION_NAME     = 'ImHimMessages'
EXTENSION_BUNDLE_ID = 'com.mirrorly.app.imessage'
DEPLOYMENT_TARGET  = '15.5'
SWIFT_VERSION      = '5.0'
SOURCE_FILES = %w[MessagesViewController.swift].freeze

abort "project not found at #{PROJECT_PATH}" unless File.exist?(PROJECT_PATH)
project = Xcodeproj::Project.open(PROJECT_PATH)

runner = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' if runner.nil?
runner_team = runner.build_configurations.map { |cfg|
  cfg.build_settings['DEVELOPMENT_TEAM']
}.compact.first || '7T3XFY333F'

target = project.targets.find { |t| t.name == EXTENSION_NAME }
if target.nil?
  puts "creating new target #{EXTENSION_NAME}"
  target = project.new_target(:app_extension, EXTENSION_NAME, :ios, DEPLOYMENT_TARGET)
else
  puts "target #{EXTENSION_NAME} already exists"
end

# THE iMessage-specific bit. Xcodeproj gem creates the target as a
# generic com.apple.product-type.app-extension, but Apple's App Store
# Connect validator only accepts the iMessage icon set when the
# product type is .messages and the wrapper is wrapper.app-extension.
# Without this the catalog compiles fine but icons aren't recognised
# as iMessage icons → error 90649 on upload.
target.product_type = 'com.apple.product-type.app-extension.messages'
target.product_reference.explicit_file_type = 'wrapper.app-extension'
target.build_configurations.each do |cfg|
  cfg.build_settings['WRAPPER_EXTENSION'] = 'appex'
  cfg.build_settings['PRODUCT_BUNDLE_PACKAGE_TYPE'] = 'XPC!'
end

%w[Messages.framework].each do |fname|
  next if target.frameworks_build_phase.files_references.any? { |f| f.path&.end_with?(fname) }
  ref = project.frameworks_group.new_file("System/Library/Frameworks/#{fname}")
  ref.source_tree = 'SDKROOT'
  target.frameworks_build_phase.add_file_reference(ref)
  puts "linked #{fname}"
end

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

embed_phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
if embed_phase.nil?
  embed_phase = runner.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
embed_phase.symbol_dst_subfolder_spec ||= :plug_ins

# Same Xcode 15 build-cycle fix the share installer applies.
target_index = 4
current_index = runner.build_phases.index(embed_phase)
if current_index && current_index > target_index
  runner.build_phases.delete(embed_phase)
  runner.build_phases.insert(target_index, embed_phase)
end

product = target.product_reference
unless embed_phase.files_references.include?(product)
  build_file = embed_phase.add_file_reference(product)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts 'embedded ImHimMessages.appex into Runner.app/PlugIns'
end

unless runner.dependencies.any? { |d| d.target && d.target.name == EXTENSION_NAME }
  runner.add_dependency(target)
  puts 'Runner depends on ImHimMessages'
end

project.save
puts
puts "OK - #{EXTENSION_NAME} target wired."
puts "Bundle id: #{EXTENSION_BUNDLE_ID}"
puts 'Before the next build, register that bundle id on the Apple Developer portal.'
