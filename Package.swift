// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "modbus-swift",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .macCatalyst(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "ModbusCore", targets: ["ModbusCore"]),
        .library(name: "ModbusKit", targets: ["ModbusKit"]),
        .library(name: "ModbusSerial", targets: ["ModbusSerial"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.91.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.7.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.9.1"),
    ],
    targets: [
        // MARK: - ModbusCore (Zero Dependencies)

        // Protocol primitives: PDU builders/parsers, CRC-16, RTU framing
        .target(name: "ModbusCore"),

        // MARK: - ModbusKit (SwiftNIO TCP/TLS/UDP)

        // Async/await clients for Modbus TCP, TLS, and UDP
        .target(
            name: "ModbusKit",
            dependencies: [
                "ModbusCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
        ),

        // MARK: - ModbusSerial (POSIX Serial RTU/ASCII)

        // Async/await clients for Serial RTU and ASCII (no SwiftNIO)
        .target(
            name: "ModbusSerial",
            dependencies: [
                "ModbusCore",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
        ),

        // MARK: - Tests

        .testTarget(
            name: "ModbusCoreTests",
            dependencies: ["ModbusCore"],
        ),
        .testTarget(
            name: "ModbusKitTests",
            dependencies: [
                "ModbusKit",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ],
        ),
        .testTarget(
            name: "ModbusSerialTests",
            dependencies: ["ModbusSerial"],
        ),
    ],
)
