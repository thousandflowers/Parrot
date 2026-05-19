// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Parrot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Parrot", targets: ["Parrot"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Parrot",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: ".",
            exclude: [
                "Resources/Info.plist",
                "Resources/Parrot.entitlements",
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
                "RefineClone.app",
                "Parrot.app"
            ]
        ),
        .testTarget(
            name: "ParrotTests",
            dependencies: ["Parrot"],
            path: "Tests"
        )
    ]
)
