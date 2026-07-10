// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GhostlyStudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GhostlyCore", targets: ["GhostlyCore"]),
        .library(name: "GhostlyDomain", targets: ["GhostlyDomain"]),
        .library(name: "GhostlyFCPXML", targets: ["GhostlyFCPXML"]),
        .library(name: "GhostlySubtitles", targets: ["GhostlySubtitles"]),
        .library(name: "GhostlyDetection", targets: ["GhostlyDetection"]),
        .library(name: "GhostlyAssets", targets: ["GhostlyAssets"]),
        .library(name: "GhostlyExport", targets: ["GhostlyExport"]),
        .library(name: "GhostlyStorage", targets: ["GhostlyStorage"]),
        .library(name: "GhostlyPlugin", targets: ["GhostlyPlugin"]),
        .library(name: "GhostlyTranscription", targets: ["GhostlyTranscription"]),
        .library(name: "GhostlyDirector", targets: ["GhostlyDirector"]),
        .library(name: "GhostlyAI", targets: ["GhostlyAI"]),
        .library(name: "GhostlyLearning", targets: ["GhostlyLearning"]),
        .library(name: "GhostlyMCP", targets: ["GhostlyMCP"]),
        .library(name: "GhostlyApp", targets: ["GhostlyApp"]),
        .executable(name: "ghostly", targets: ["GhostlyCLI"]),
        .executable(name: "ghostly-mcp-server", targets: ["GhostlyMCPServer"]),
    ],
    targets: [
        // MARK: Foundation layers
        .target(name: "GhostlyCore"),
        .target(name: "GhostlyDomain", dependencies: ["GhostlyCore"]),
        .target(name: "GhostlyFCPXML", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlySubtitles", dependencies: ["GhostlyCore", "GhostlyDomain", "GhostlyFCPXML"]),
        .target(name: "GhostlyDetection", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyAssets", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyExport", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyStorage", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyPlugin", dependencies: ["GhostlyCore"]),
        .target(name: "GhostlyTranscription", dependencies: ["GhostlyCore", "GhostlySubtitles"]),
        .target(name: "GhostlyDirector", dependencies: [
            "GhostlyCore", "GhostlyDomain", "GhostlyDetection", "GhostlyFCPXML", "GhostlySubtitles",
        ]),
        .target(name: "GhostlyAI", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyLearning", dependencies: ["GhostlyCore", "GhostlyDomain"]),
        .target(name: "GhostlyMCP", dependencies: [
            "GhostlyCore", "GhostlyDomain", "GhostlyFCPXML", "GhostlySubtitles",
            "GhostlyDirector", "GhostlyDetection", "GhostlyLearning", "GhostlyAssets",
            "GhostlyExport", "GhostlyPlugin",
        ]),
        // MARK: Presentation (compiles to an empty module off-macOS)
        .target(name: "GhostlyApp", dependencies: [
            "GhostlyCore", "GhostlyDomain", "GhostlyDirector", "GhostlySubtitles",
            "GhostlyMCP", "GhostlyLearning", "GhostlyAI",
        ]),
        // MARK: Executables
        .executableTarget(name: "GhostlyCLI", dependencies: [
            "GhostlyCore", "GhostlyDomain", "GhostlyFCPXML", "GhostlySubtitles",
            "GhostlyDirector", "GhostlyDetection", "GhostlyLearning", "GhostlyExport",
            "GhostlyTranscription",
        ]),
        .executableTarget(name: "GhostlyMCPServer", dependencies: ["GhostlyMCP"]),
        // MARK: Tests
        .testTarget(name: "GhostlyCoreTests", dependencies: ["GhostlyCore"]),
        .testTarget(name: "GhostlyDomainTests", dependencies: ["GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyFCPXMLTests", dependencies: ["GhostlyFCPXML", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlySubtitlesTests", dependencies: ["GhostlySubtitles", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyDetectionTests", dependencies: ["GhostlyDetection", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyAssetsTests", dependencies: ["GhostlyAssets", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyExportTests", dependencies: ["GhostlyExport", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyStorageTests", dependencies: ["GhostlyStorage", "GhostlyDomain", "GhostlyCore"]),
        .testTarget(name: "GhostlyPluginTests", dependencies: ["GhostlyPlugin", "GhostlyCore"]),
        .testTarget(name: "GhostlyTranscriptionTests", dependencies: [
            "GhostlyTranscription", "GhostlySubtitles", "GhostlyCore",
        ]),
        .testTarget(name: "GhostlyDirectorTests", dependencies: [
            "GhostlyDirector", "GhostlyDetection", "GhostlySubtitles", "GhostlyDomain", "GhostlyCore",
        ]),
        .testTarget(name: "GhostlyAITests", dependencies: ["GhostlyAI", "GhostlyCore"]),
        .testTarget(name: "GhostlyLearningTests", dependencies: ["GhostlyLearning", "GhostlyCore"]),
        .testTarget(name: "GhostlyMCPTests", dependencies: ["GhostlyMCP", "GhostlyCore", "GhostlyDetection"]),
    ]
)
