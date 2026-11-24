// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "linkroute",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LinkRoute", targets: ["LinkRoute"]),
    ],
    targets: [
        // Pure logic: patterns, rules, config, Chrome profile discovery. No AppKit.
        .target(name: "LinkRouteCore"),
        // The menu bar app.
        .executableTarget(name: "LinkRoute", dependencies: ["LinkRouteCore"]),
        // Test runner. A plain executable, because XCTest and swift-testing need full Xcode;
        // this runs with the Command Line Tools alone: `swift run linkroute-tests`.
        .executableTarget(name: "linkroute-tests", dependencies: ["LinkRouteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
