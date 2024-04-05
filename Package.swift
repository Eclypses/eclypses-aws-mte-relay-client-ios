// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "MteRelay",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MteRelay",
            targets: ["MteRelay", "mte", "Mte", "Core", "MKE", "Kyber"]),
    ],
    targets: [
        .target(
            name: "MteRelay",
            dependencies: [
                .target(name: "Mte"),
                .target(name: "Core"),
                .target(name: "MKE"),
                .target(name: "Kyber"),
            ],
            path: "MteRelay"
        ),
        .binaryTarget(
            name: "mte",
            path: "Mte/mte.xcframework"
        ),
        .target(
            name: "Mte",
            dependencies: [
                .target(name: "mte")
            ],
            path: "Mte",
            exclude: ["mte.xcframework"]
        ),
        .target(
            name: "Core",
            dependencies: [
                .target(name: "Mte")
            ],
            path: "Core",
            swiftSettings: [
                .define("MTE_SWIFT_PACKAGE_MANAGER")
            ]
        ),
        .target(
            name: "MKE",
            dependencies: [
                .target(name: "Core")
            ],
            path: "MKE",
            swiftSettings: [
                .define("MTE_SWIFT_PACKAGE_MANAGER")
            ]
        ),
        .target(
            name: "Kyber",
            dependencies: [
                .target(name: "Mte"),
                .target(name: "Core"),
            ],
            path: "Kyber",
            swiftSettings: [
                .define("MTE_SWIFT_PACKAGE_MANAGER")
            ]
        ),
    ]
)
