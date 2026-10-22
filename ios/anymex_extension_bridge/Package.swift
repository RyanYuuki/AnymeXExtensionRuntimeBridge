// swift-tools-version: 5.9
import Foundation
import PackageDescription

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
            path: "Frameworks/ios-runtime-v1/OpenJDKRuntime.xcframework.zip"
        ),
        .binaryTarget(
            name: "TorrServerKit",
            url: "https://github.com/YouROK/TorrServer/releases/download/MatriX.146.1/TorrServer-ios-TorrServerKit.xcframework.zip",
            checksum: "20d0f1e705f72cc87209330570b058eb6368a8800a4ad7cc694802b11b9a2700"
        ),
        .target(
            name: "anymex_embedded_jvm",
            dependencies: ["OpenJDKRuntime"],
            resources: [
                .copy("Runtime"),
            ],
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("jdk"),
            ]
        ),
        .target(
            name: "anymex_extension_bridge",
            dependencies: ["anymex_embedded_jvm", "TorrServerKit"],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx20
)
