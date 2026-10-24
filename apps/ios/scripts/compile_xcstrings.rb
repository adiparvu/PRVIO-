#!/usr/bin/env ruby
# Generates <lang>.lproj/Localizable.strings into the built product from
# Resources/Localizable.xcstrings, merged over the legacy .lproj tables
# (the catalog wins on conflicts) — the same merge the Fastfile performs
# for the archive. Running it as a build phase means EVERY build ships the
# localization tables: the unit-test host, simulator runs, and the archive.
# Without it, only Fastfile-built archives were localized, which is exactly
# what LanguageResolutionTests caught failing in CI.
#
# Usage: invoked by Xcode build phases with no arguments (destination comes
# from TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH), or manually with
# an explicit destination directory as ARGV[0].

require "json"
require "fileutils"

project_dir = ENV["PROJECT_DIR"] || File.expand_path("..", __dir__)
dest_root = ARGV[0] || File.join(ENV.fetch("TARGET_BUILD_DIR"),
                                 ENV.fetch("UNLOCALIZED_RESOURCES_FOLDER_PATH"))

catalog = JSON.parse(File.read(File.join(project_dir, "Resources", "Localizable.xcstrings"),
                               encoding: "UTF-8"))

# A catalog entry is either a plain stringUnit or a plural `variations`
# block. .strings tables can't express plurals, so the best honest
# projection is the `other` form (falling back through the plural cases) —
# without this, plural keys silently vanished from every compiled table.
def unit_value(localization)
  return nil unless localization
  direct = localization.dig("stringUnit", "value")
  return direct if direct
  plural = localization.dig("variations", "plural")
  return nil unless plural
  %w[other many few two one zero].each do |form|
    v = plural.dig(form, "stringUnit", "value")
    return v if v
  end
  nil
end

%w[en ro fr nl de].each do |lang|
  merged = {}

  legacy = File.join(project_dir, "Resources", "#{lang}.lproj", "Localizable.strings")
  if File.exist?(legacy)
    # Explicit UTF-8: under a C/ASCII locale (CI runners) the default
    # external encoding made diacritics in the legacy tables a hard crash.
    File.read(legacy, encoding: "UTF-8").scan(/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";/m).each do |k, v|
      un = ->(s) { s.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\') }
      merged[un.call(k)] = un.call(v)
    end
  end

  catalog["strings"].each do |key, info|
    value = unit_value(info.dig("localizations", lang))
    value ||= unit_value(info.dig("localizations", "en"))
    merged[key] = value if value
  end

  lproj_dir = File.join(dest_root, "#{lang}.lproj")
  FileUtils.mkdir_p(lproj_dir)
  content = merged.map { |k, v| "#{k.to_json} = #{v.to_json};" }.join("\n") + "\n"
  File.write(File.join(lproj_dir, "Localizable.strings"), content)
  puts "xcstrings → #{lang}.lproj/Localizable.strings (#{merged.size} keys)"

  # Permission prompts: the system reads NS*UsageDescription from
  # InfoPlist.strings in the matching .lproj — without this, every
  # permission sheet showed English regardless of device language.
  # Languages without their own table fall back to the English one.
  # The watch asks for its own permissions for its own reasons — sharing
  # the phone's table would show the iPhone's purpose (Chat, Inventory) on
  # the wrist's location prompt.
  table = ENV.fetch("PLATFORM_NAME", "").start_with?("watch") ? "InfoPlist.watch.strings" : "InfoPlist.strings"
  infoplist = File.join(project_dir, "Resources", "#{lang}.lproj", table)
  infoplist = File.join(project_dir, "Resources", "en.lproj", table) unless File.exist?(infoplist)
  if File.exist?(infoplist)
    FileUtils.cp(infoplist, File.join(lproj_dir, "InfoPlist.strings"))
    puts "InfoPlist.strings → #{lang}.lproj"
  end
end
