// swift-tools-version:5.9
import PackageDescription

// jbforge/mac-fan-control, ae14180df9d3c762601e1b0126214049c16a7945 (MIT).
let package = Package(name: "MacUnseenFanService", platforms: [.macOS("15.0")], targets: [
    .target(name: "SMC"),
    .target(name: "FanCore"),
    .executableTarget(name: "fanctld", dependencies: ["SMC", "FanCore"])
])
