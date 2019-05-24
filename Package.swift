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
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.2.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.1.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.1.0"),
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
