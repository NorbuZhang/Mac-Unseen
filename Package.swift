// swift-tools-version: 6.2
// SPDX-License-Identifier: MPL-2.0


import PackageDescription

let package = Package(
    name: "MacUnseen",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MacUnseen", targets: ["MacUnseen"])
    ],
    targets: [
        .target(
            name: "TrackpadBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("dl")
            ]
        ),
        .executableTarget(
            name: "MacUnseen",
            dependencies: ["TrackpadBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
