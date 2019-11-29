// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The Swift Package Manager package.
public let package = Package(
    name: "BNS",
    products: [
        .library(name: "BNS", targets: ["BNS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", .upToNextMajor(from: "2.10.1")),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", .upToNextMajor(from: "2.4.4")),
        .package(url: "https://github.com/apple/swift-nio-http2.git", .upToNextMajor(from: "1.7.2")),
        .package(url: "https://github.com/apple/swift-nio-extras.git", .upToNextMajor(from: "1.3.2")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/apple/swift-package-manager", .branch("swift-5.0-branch")),
    ],
    targets: [
        .target(
            name: "BNS",
            dependencies: ["NIO", "NIOSSL", "NIOHTTP1", "NIOHTTP2", "NIOWebSocket", "NIOHTTPCompression", "Logging"]
        ),
        .target(
            name: "ExampleUtilities",
            dependencies: ["BNS", "Logging", "NIO", "NIOHTTP1", "NIOExtras", "SPMUtility"]
        ),
        .target(
            name: "BasicExample",
            dependencies: ["BNS", "Logging", "NIO", "NIOHTTP1", "NIOExtras", "ExampleUtilities"]
        ),
        .target(
            name: "HTTPServerExample",
            dependencies: ["BNS", "Logging", "NIO", "NIOHTTP1", "NIOExtras", "ExampleUtilities"]
        ),
        .target(
            name: "WebSocketServerExample",
            dependencies: ["BNS", "Logging", "NIO", "NIOHTTP1", "NIOWebSocket", "NIOExtras", "ExampleUtilities"]
        ),
        .testTarget(
            name: "BNSTests",
            dependencies: ["BNS"]
        ),
    ]
)
