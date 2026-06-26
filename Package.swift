// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conan",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
    ],
    targets: [
        // Pure, testable logic + watson integration. No SwiftUI app entry point here.
        .target(name: "ConanCore"),
        // Menu-bar app: @main + SwiftUI views, thin shell over ConanCore.
        .executableTarget(
            name: "Conan",
            dependencies: [
                "ConanCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                // Resolve the embedded Sparkle.framework inside the .app bundle at runtime.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ConanTests",
            dependencies: ["ConanCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
