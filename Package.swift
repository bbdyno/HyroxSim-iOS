// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HyroxSim",
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.12.0")
    ]
)
