// swift-tools-version: 6.2

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
        .target(name: "SystemMonitorBridge", publicHeadersPath: "include"),
        .target(name: "AccordionDSP", publicHeadersPath: "include"),
        .target(
            name: "TrackpadBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("dl")
            ]
        ),
        .executableTarget(
            name: "MacUnseen",
            dependencies: ["TrackpadBridge", "AccordionDSP", "SystemMonitorBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal")
            ]
        ),
        .testTarget(
            name: "MacUnseenTests",
            dependencies: ["MacUnseen", "AccordionDSP", "SystemMonitorBridge"]
        )
    ]
)
