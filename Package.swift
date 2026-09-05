// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Toaster",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(name: "Toaster", targets: ["Toaster"])
    ],
    targets: [
        .target(
            name: "Toaster"
        ),
        .testTarget(
            name: "ToasterTests",
            dependencies: ["Toaster"]
        ),
    ]
)
