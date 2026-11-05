// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlomentumsolutionsCapacitorHealthExtended",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "FlomentumsolutionsCapacitorHealthExtended",
            targets: ["HealthPluginPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor.git", from: "9.0.0-beta.0")
    ],
    targets: [
        .target(
            name: "HealthPluginPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor"),
            ],
            path: "ios/Sources/HealthPluginPlugin"
        )
    ]
)
