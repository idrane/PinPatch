// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PinPatch",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PinPatch", type: .dynamic, targets: ["PinPatch"])
    ],
    targets: [
        .target(
            name: "PinPatchBootstrap",
            path: "Sources/PinPatchBootstrap",
            publicHeadersPath: "include"
        ),
        .target(
            name: "PinPatch",
            dependencies: ["PinPatchBootstrap"],
            path: "Sources/PinPatch"
        ),
        .testTarget(
            name: "PinPatchTests",
            dependencies: ["PinPatch"],
            path: "Tests/PinPatchTests"
        )
    ]
)
