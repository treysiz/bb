// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniBridgeCameraCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "MiniBridgeCameraCore", targets: ["MiniBridgeCameraCore"])],
    targets: [
        .target(name: "MiniBridgeCameraCore"),
        .testTarget(name: "MiniBridgeCameraCoreTests", dependencies: ["MiniBridgeCameraCore"])
    ]
)
