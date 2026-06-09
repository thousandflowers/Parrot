// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Parrot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Parrot", targets: ["Parrot"]),
        .executable(name: "ParrotCompletionHelper", targets: ["ParrotCompletionHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        // MLX backend for the correction/chat path — 2-3× faster than llama.cpp on Apple Silicon.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // Hub download + tokenizer for MLX models (MLXHuggingFace macros expand to these).
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "ParrotObjC",
            path: "ObjCBridge",
            publicHeadersPath: "."
        ),
        // libllama (system library) — header from the matching Homebrew llama.cpp install.
        .systemLibrary(name: "CLlama", path: "CLlama"),
        // In-process completion helper (separate process for crash isolation).
        .executableTarget(
            name: "ParrotCompletionHelper",
            dependencies: ["CLlama"],
            path: "CompletionHelper",
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/lib",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "/opt/homebrew/lib"
                ])
            ]
        ),
        .executableTarget(
            name: "Parrot",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                "ParrotObjC",
            ],
            path: ".",
            exclude: [
                "ObjCBridge",
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
                "Parrot.app",
                "Wren.app",
                "docs",
                "scripts",
                "build-wren.sh",
                "Resources/MenuIcon.png",
                "Resources/MenuIcon@2x.png",
                "Resources/AppIcon.icns",
                "Casks",
                "CONTRIBUTING.md",
                "PRODUCT.md",
                "Parrot.dmg",
                "appcast.xml",
                "Resources/Localizable.xcstrings",
                "Resources/Parrot-MAS.entitlements",
                "CLlama",
                "CompletionHelper"
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "ParrotTests",
            dependencies: ["Parrot"],
            path: "Tests"
        )
    ]
)
