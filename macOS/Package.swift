// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeekQool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SeekQool", targets: ["SeekQool"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "SeekQool",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/SeekQool"
        )
    ]
)
