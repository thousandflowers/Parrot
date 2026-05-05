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
            exclude: ["Resources/Info.plist", "Resources/RefineClone.entitlements", "Package.swift", "README.md"],
            sources: [
                "RefineCloneApp.swift",
                "App/AppDelegate.swift",
                "App/Constants.swift",
                "Core/AppRule.swift",
                "Core/CancellationToken.swift",
                "Core/CorrectionResult.swift",
                "Core/GGUFVersionCheck.swift",
                "Core/LLMService.swift",
                "Core/LLMServiceExtension.swift",
                "Core/LLMServiceFactory.swift",
                "Core/LocalLLMService.swift",
                "Core/OllamaService.swift",
                "Core/OpenRouterService.swift",
                "Core/PromptEngine.swift",
                "Core/RemoteLLMService.swift",
                "Core/RequestQueue.swift",
                "Core/RuleResolver.swift",
                "Core/StubLLMService.swift",
                "Core/TextCheckCoordinator.swift",
                "Accessibility/AXBridgeProtocol.swift",
                "Accessibility/AccessibilityBridge.swift",
                "Shortcuts/GlobalHotkeyManager.swift",
                "UI/FloatingEditor.swift",
                "UI/MenuBarView.swift",
                "UI/SettingsView.swift",
                "UI/SuggestionPanel.swift",
                "UI/SuggestionView.swift",
                "Infra/KeychainService.swift",
                "Infra/ModelManager.swift",
                "Infra/PreferencesStore.swift",
                "Infra/ResultCache.swift",
                "Infra/ServerHealthMonitor.swift",
                "Infra/ServerManager.swift"
            ]
        ),
        .testTarget(
            name: "RefineCloneTests",
            dependencies: ["RefineClone"],
            path: "Tests"
        )
    ]
)
