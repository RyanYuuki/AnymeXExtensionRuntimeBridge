// swift-tools-version: 5.9
import PackageDescription
import Foundation

// PrepareEmbeddedRuntime.sh (../PrepareEmbeddedRuntime.sh) builds
// Frameworks/OpenJDKRuntime.xcframework and Sources/anymex_extension_bridge/Runtime/.
// It only runs automatically as CocoaPods' `prepare_command` — SPM has no
// equivalent hook that can do a network download (build-tool plugins are
// sandboxed with no network access). If this app also depends on any plugin
// without SPM support, CocoaPods still runs and keeps these paths populated
// as a side effect; for a pure-SPM build with no such plugin, or for `swift
// build`/`swift package resolve` run standalone, run that script by hand
// first. See runtimeManager/EMBEDDED_IOS_NOTES.md, "Swift Package Manager
// support", for the durable fix (a pinned, checksummed xcframework release
// referenced via `binaryTarget(url:checksum:)` instead of a local path).
let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let xcframeworkPath = "Frameworks/OpenJDKRuntime.xcframework"
let torrServerXCFrameworkPath = "Frameworks/TorrServerKit.xcframework"

func warnIfMissing(_ relativePath: String, prepareScript: String) {
    let exists = FileManager.default.fileExists(
        atPath: packageDir.appendingPathComponent(relativePath).path)
    guard !exists else { return }
    FileHandle.standardError.write(
        """
        warning: [anymex_extension_bridge] \(relativePath) not found.
        Run ios/\(prepareScript) before building with Swift Package \
        Manager (CocoaPods' `pod install` normally does this for you).

        """.data(using: .utf8)!)
}

warnIfMissing(xcframeworkPath, prepareScript: "PrepareEmbeddedRuntime.sh")
warnIfMissing(torrServerXCFrameworkPath, prepareScript: "PrepareTorrServerRuntime.sh")

let package = Package(
    name: "anymex_extension_bridge",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "anymex-extension-bridge", targets: ["anymex_extension_bridge"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "OpenJDKRuntime",
            path: xcframeworkPath
        ),
        .binaryTarget(
            name: "TorrServerKit",
            path: torrServerXCFrameworkPath
        ),
        .target(
            name: "anymex_extension_bridge",
            dependencies: ["OpenJDKRuntime", "TorrServerKit"],
            resources: [
                .copy("Runtime"),
                .process("PrivacyInfo.xcprivacy"),
            ],
            cSettings: [
                .headerSearchPath("include/anymex_extension_bridge")
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
