// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Daywell",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "DaywellCore", targets: ["DaywellCore"]),
    .executable(name: "Daywell", targets: ["Daywell"]),
    .executable(name: "DaywellDev", targets: ["DaywellDev"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")
  ],
  targets: [
    .target(name: "DaywellCore"),
    .target(name: "DaywellKit", dependencies: ["DaywellCore"]),
    .executableTarget(name: "Daywell", dependencies: ["DaywellKit", "DaywellCore"]),
    // Never shipped: fixtures, demo, snapshots, UI checks, benchmarks, live check.
    .target(name: "DaywellFixtures", dependencies: ["DaywellKit", "DaywellCore"]),
    .executableTarget(
      name: "DaywellDev", dependencies: ["DaywellKit", "DaywellCore", "DaywellFixtures"]),
    .testTarget(
      name: "DaywellKitTests",
      dependencies: [
        "DaywellKit", "DaywellFixtures", .product(name: "Testing", package: "swift-testing"),
      ]),
    .testTarget(
      name: "DaywellCoreTests",
      dependencies: [
        "DaywellCore", .product(name: "Testing", package: "swift-testing"),
      ]),
  ]
)
