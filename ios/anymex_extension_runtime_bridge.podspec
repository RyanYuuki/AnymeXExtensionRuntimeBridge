Pod::Spec.new do |s|
  s.name             = 'anymex_extension_runtime_bridge'
  s.version          = '0.0.1'
  s.summary          = 'Embedded OpenJDK Zero runtime and TorrServer for AnymeX on iOS.'
  s.description      = <<-DESC
Runs the extension backend JARs in-process on iOS using a lazily loaded, interpreter-only OpenJDK framework, and provides embedded TorrServer streaming.
                       DESC
  s.homepage         = 'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'RyanYuuki' => 'ryan@example.com' }
  s.source           = { :path => '.' }

  s.source_files = 'anymex_extension_bridge/Sources/anymex_extension_bridge/**/*.{h,m,mm,swift}'
  s.public_header_files = 'anymex_extension_bridge/Sources/anymex_extension_bridge/include/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.prepare_command = 'sh PrepareEmbeddedRuntime.sh && sh PrepareTorrServerRuntime.sh'
  s.vendored_frameworks = [
    'anymex_extension_bridge/Frameworks/OpenJDKRuntime.xcframework',
    'anymex_extension_bridge/Frameworks/TorrServerKit.xcframework',
  ]
  s.resource_bundles = {
    'anymex_extension_bridge_runtime' => ['anymex_extension_bridge/Sources/anymex_extension_bridge/Runtime/**/*'],
    'anymex_extension_bridge_privacy' => ['anymex_extension_bridge/Sources/anymex_extension_bridge/PrivacyInfo.xcprivacy'],
  }
  s.preserve_paths = 'RuntimeSources/**/*', 'PrepareEmbeddedRuntime.sh', 'PrepareTorrServerRuntime.sh'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++20',
    'HEADER_SEARCH_PATHS[sdk=iphoneos*]' =>
      '$(inherited) "$(PODS_TARGET_SRCROOT)/anymex_extension_bridge/Frameworks/OpenJDKRuntime.xcframework/ios-arm64/OpenJDKRuntime.framework/Headers"',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end
