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

  s.dependency 'Flutter'
  s.frameworks = 'SystemConfiguration'
  s.platform = :ios, '13.0'
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  # On iOS we must statically link — Apple does not allow dynamic libraries
  # in App Store submissions. The XCFramework contains separate static libs
  # for device (arm64-iphoneos) and simulator (arm64+x86_64-iphonesimulator).
  xcframework_path = 'libtorrent_flutter.xcframework'
  xcframework_absolute = File.join(__dir__, xcframework_path)

  # ───────────────────────────────────────────────────────────────────────
  # Prebuilt binaries are NOT shipped on pub.dev. Pull the XCFramework from
  # the matching GitHub Release on first `pod install`. Set the env var
  # LIBTORRENT_FLUTTER_SKIP_DOWNLOAD=1 to opt out.
  # ───────────────────────────────────────────────────────────────────────
  if !File.exist?(xcframework_absolute) && ENV['LIBTORRENT_FLUTTER_SKIP_DOWNLOAD'] != '1'
    pubspec_path = File.expand_path(File.join(__dir__, '..', 'pubspec.yaml'))
    if File.exist?(pubspec_path)
      version_match = File.read(pubspec_path).match(/^version:\s*(\S+)/)
      if version_match
        plugin_version = version_match[1]
        zip_url  = "https://github.com/ayman708-UX/libtorrent_flutter/releases/download/v#{plugin_version}/ios-native-lib.zip"
        zip_path = File.join(__dir__, '.ios-native-lib.zip')
        Pod::UI.puts "libtorrent_flutter: downloading prebuilt XCFramework from #{zip_url}"
        begin
          require 'open-uri'
          require 'fileutils'
          URI.open(zip_url) { |remote| File.binwrite(zip_path, remote.read) }
          # CI artifact root corresponds to the xcframework directory itself
          # (Info.plist + ios-arm64/ + ios-arm64_x86_64-simulator/), so we
          # extract directly into libtorrent_flutter.xcframework/.
          FileUtils.mkdir_p(xcframework_absolute)
          system("/usr/bin/unzip -o -q '#{zip_path}' -d '#{xcframework_absolute}'") || raise('unzip failed')
          File.delete(zip_path) if File.exist?(zip_path)
        rescue => e
          Pod::UI.warn "libtorrent_flutter: prebuilt download failed (#{e.message}); falling back to source build"
          FileUtils.rm_rf(xcframework_absolute) if Dir.exist?(xcframework_absolute) && Dir.empty?(xcframework_absolute)
          File.delete(zip_path) if File.exist?(zip_path)
        end
      end
    end
  end

  if File.exist?(xcframework_absolute)
    # Use prebuilt XCFramework — supports both device and simulator
    s.vendored_frameworks = xcframework_path
    s.source_files = 'Classes/**/*.swift'
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      # Force the linker to include all symbols from the static lib
      # so DynamicLibrary.process() can find them via dlsym().
      # Use conditional settings to select the correct XCFramework slice.
      'OTHER_LDFLAGS[sdk=iphoneos*]' => '-force_load "$(PODS_TARGET_SRCROOT)/libtorrent_flutter.xcframework/ios-arm64/liblibtorrent_flutter.a"',
      'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '-force_load "$(PODS_TARGET_SRCROOT)/libtorrent_flutter.xcframework/ios-arm64_x86_64-simulator/liblibtorrent_flutter.a"',
    }
  else
    # Fallback: build from source (requires libtorrent headers + libs)
    s.source_files = 'Classes/**/*'
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src"',
      'OTHER_CPLUSPLUSFLAGS' => '-std=c++17 -DTORRENT_BRIDGE_EXPORTS -DTORRENT_NO_DEPRECATE -DTORRENT_USE_SSL=0',
      'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    }
  end
end
