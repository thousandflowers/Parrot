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
                "Resources/en.lproj",
                "Resources/it.lproj",
                "Resources/zh-Hans.lproj",
                "Resources/hr.lproj",
                "Resources/da.lproj",
                "Resources/nb.lproj",
                "Resources/el.lproj",
                "PopClip",
                "Package.swift",
                "README.md",
                "CHANGELOG.md",
                ".gitignore",
                "Tests",
                ".build",
                "setup-dev.sh",
                "build-app.sh",
                "RefineClone.app"
            ]
        ),
        .testTarget(
            name: "RefineCloneTests",
            dependencies: ["RefineClone"],
            path: "Tests"
        )
    ]
)
