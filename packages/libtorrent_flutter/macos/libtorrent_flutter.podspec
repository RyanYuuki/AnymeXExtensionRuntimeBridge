Pod::Spec.new do |s|
  s.name             = 'libtorrent_flutter'
  s.version          = '1.7.0'
  s.summary          = 'Flutter plugin for libtorrent with built-in streaming server.'
  s.description      = <<-DESC
  Native libtorrent 2.0 bindings for Flutter with an integrated HTTP streaming server.
                       DESC
  s.homepage         = 'https://github.com/ayman708-UX/libtorrent_flutter'
  s.license          = { :type => 'GPL-3.0', :file => '../LICENSE' }
  s.author           = { 'ayman708-UX' => 'ayman@example.com' }
  s.source           = { :path => '.' }

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.osx.deployment_target = '10.14'
  s.swift_version = '5.0'

  # Check for prebuilt dylib first
  prebuilt_library  = 'liblibtorrent_flutter.dylib'
  prebuilt_absolute = File.join(__dir__, prebuilt_library)

  # ───────────────────────────────────────────────────────────────────────
  # Prebuilt binaries are NOT shipped on pub.dev. Pull the dylib from the
  # matching GitHub Release on first `pod install`. Set the env var
  # LIBTORRENT_FLUTTER_SKIP_DOWNLOAD=1 to opt out.
  # ───────────────────────────────────────────────────────────────────────
  if !File.exist?(prebuilt_absolute) && ENV['LIBTORRENT_FLUTTER_SKIP_DOWNLOAD'] != '1'
    pubspec_path = File.expand_path(File.join(__dir__, '..', 'pubspec.yaml'))
    if File.exist?(pubspec_path)
      version_match = File.read(pubspec_path).match(/^version:\s*(\S+)/)
      if version_match
        plugin_version = version_match[1]
        zip_url  = "https://github.com/ayman708-UX/libtorrent_flutter/releases/download/v#{plugin_version}/macos-native-lib.zip"
        zip_path = File.join(__dir__, '.macos-native-lib.zip')
        Pod::UI.puts "libtorrent_flutter: downloading prebuilt dylib from #{zip_url}"
        begin
          require 'open-uri'
          require 'fileutils'
          URI.open(zip_url) { |remote| File.binwrite(zip_path, remote.read) }
          # CI artifact root corresponds to prebuilt/macos/, so the zip
          # contains universal/liblibtorrent_flutter.dylib.
          system("/usr/bin/unzip -o -q '#{zip_path}' -d '#{__dir__}'") || raise('unzip failed')
          extracted = File.join(__dir__, 'universal', 'liblibtorrent_flutter.dylib')
          FileUtils.mv(extracted, prebuilt_absolute) if File.exist?(extracted)
          FileUtils.rm_rf(File.join(__dir__, 'universal'))
          File.delete(zip_path) if File.exist?(zip_path)
        rescue => e
          Pod::UI.warn "libtorrent_flutter: prebuilt download failed (#{e.message}); falling back to source build"
          File.delete(zip_path) if File.exist?(zip_path)
        end
      end
    end
  end

  if File.exist?(prebuilt_absolute)
    # Use prebuilt — bundle the dylib plus OpenSSL dependencies
    openssl_dylibs = Dir.glob(File.join(__dir__, 'lib*.dylib')).map { |f| File.basename(f) }
    s.vendored_libraries = openssl_dylibs
    s.source_files = 'Classes/**/*.swift'
  else
    # Build from source — needs Homebrew libtorrent
    s.source_files = 'Classes/**/*'
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      'HEADER_SEARCH_PATHS' => [
        '"$(PODS_TARGET_SRCROOT)/../src"',
        '"/opt/homebrew/include"',
        '"/usr/local/include"',
      ].join(' '),
      'LIBRARY_SEARCH_PATHS' => [
        '"/opt/homebrew/lib"',
        '"/usr/local/lib"',
      ].join(' '),
      'OTHER_LDFLAGS' => '-ltorrent-rasterbar -lboost_system -lssl -lcrypto',
      'OTHER_CPLUSPLUSFLAGS' => '-std=c++17 -DTORRENT_BRIDGE_EXPORTS -DTORRENT_NO_DEPRECATE',
      'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    }
  end
end
