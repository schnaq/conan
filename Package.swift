// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conan",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, testable logic + watson integration. No SwiftUI app entry point here.
        .target(name: "ConanCore"),
        // Menu-bar app: @main + SwiftUI views, thin shell over ConanCore.
        .executableTarget(
            name: "Conan",
            dependencies: ["ConanCore"]
        ),
        .testTarget(
            name: "ConanTests",
            dependencies: ["ConanCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
