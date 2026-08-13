// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TLEWhereIsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "TLEWhereIsCore", targets: ["TLEWhereIsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gavineadie/SatelliteKit.git", .upToNextMajor(from: "2.1.2")),
    ],
    targets: [
        .target(
            name: "TLEWhereIsCore",
            dependencies: [
                .product(name: "SatelliteKit", package: "SatelliteKit"),
            ]
        ),
        .testTarget(
            name: "TLEWhereIsCoreTests",
            dependencies: ["TLEWhereIsCore"]
        ),
    ]
)
