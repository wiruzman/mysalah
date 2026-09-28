// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MySalahCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MySalahCore", targets: ["MySalahCore"])],
    dependencies: [.package(url: "https://github.com/batoulapps/adhan-swift.git", exact: "1.5.0")],
    targets: [
        .target(name: "MySalahCore", dependencies: [.product(name: "Adhan", package: "adhan-swift")], resources: [.process("Resources")]),
        .testTarget(name: "MySalahCoreTests", dependencies: ["MySalahCore"], resources: [.copy("Fixtures")])
    ]
)
