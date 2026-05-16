// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RefineClone",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RefineClone", targets: ["RefineClone"])
    ],
    targets: [
        .executableTarget(
            name: "RefineClone",
            path: ".",
            exclude: [
                "Resources/Info.plist",
                "Resources/RefineClone.entitlements",
                "PopClip",
                "Package.swift",
                "README.md",
                ".gitignore",
                "Tests",
                ".build",
                "setup-dev.sh"
            ]
        ),
        .testTarget(
            name: "RefineCloneTests",
            dependencies: ["RefineClone"],
            path: "Tests"
        )
    ]
)
