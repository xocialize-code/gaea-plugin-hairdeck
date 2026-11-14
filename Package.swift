// swift-tools-version: 6.2
import PackageDescription

// gaea-plugin-hairdeck: HairDeck (hair for an avatar from one character picture) as a Gaea plugin, on MES
// mesh.generate_part. GaeaPluginKit over mlx-hairdeck-swift's engine package, with mlx-birefnet-swift cutting the
// character out of an opaque picture.
let kitPath = Context.environment["GAEA_PLUGIN_KIT_PATH"]
let hairdeckPath = Context.environment["MLX_HAIRDECK_PATH"]
let cxx: [SwiftSetting] = [.interoperabilityMode(.Cxx)]

let package = Package(
    name: "gaea-plugin-hairdeck",
    platforms: [.macOS(.v26)], // mlx-engine-swift's MLXToolKit requires macOS 26
    dependencies: [
        kitPath.map { .package(path: $0) }
            ?? .package(url: "https://github.com/xocialize-code/gaea-plugin-kit.git", from: "0.13.0"),
        hairdeckPath.map { .package(path: $0) }
            ?? .package(url: "https://github.com/xocialize/mlx-hairdeck-swift.git", from: "0.1.0"),
        .package(url: "https://github.com/xocialize/mlx-birefnet-swift.git", from: "0.4.0"),
        .package(url: "https://github.com/xocialize/mlx-engine-swift.git", exact: "0.78.0"),
    ],
    targets: [
        .target(
            name: "HairDeckPlugin",
            dependencies: [
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
                .product(name: "HairDeckKit", package: "mlx-hairdeck-swift"),
                .product(name: "MLXBiRefNet", package: "mlx-birefnet-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
            ],
            swiftSettings: cxx
        ),
        .executableTarget(
            name: "gaea-hairdeck-worker",
            dependencies: [
                "HairDeckPlugin",
                .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"),
            ],
            swiftSettings: cxx
        ),
        .executableTarget(
            name: "hairdeck-inproc",
            dependencies: [
                "HairDeckPlugin",
                .product(name: "HairDeckKit", package: "mlx-hairdeck-swift"),
                .product(name: "MLXBiRefNet", package: "mlx-birefnet-swift"),
                .product(name: "MLXToolKit", package: "mlx-engine-swift"),
                .product(name: "MLXServeCore", package: "mlx-engine-swift"),
            ],
            swiftSettings: cxx + [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HairDeckPluginTests",
            dependencies: ["HairDeckPlugin", .product(name: "GaeaProtocol", package: "gaea-plugin-kit"),
                           .product(name: "GaeaPluginKit", package: "gaea-plugin-kit"), .product(name: "MLXToolKit", package: "mlx-engine-swift")],
            swiftSettings: cxx
        ),
    ]
)
