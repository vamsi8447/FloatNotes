// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FloatNotes",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "FloatNotes", targets: ["FloatNotes"])],
    targets: [
        .executableTarget(name: "FloatNotes"),
        .testTarget(name: "FloatNotesTests", dependencies: ["FloatNotes"])
    ],
    swiftLanguageModes: [.v5]
)
