// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PRsAndIssuesPreview",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PRsAndIssuesPreview", targets: ["PRsAndIssuesPreview"])
    ],
    targets: [
        .executableTarget(
            name: "PRsAndIssuesPreview",
            path: "Sources/PRsAndIssuesPreview",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "PRsAndIssuesPreviewTests",
            dependencies: ["PRsAndIssuesPreview"],
            path: "Tests/PRsAndIssuesPreviewTests"
        )
    ]
)
