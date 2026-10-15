// swift-tools-version: 5.9
import PackageDescription

// Package.swift is like a pyproject.toml: it names the project and says where the code is.
let package = Package(
    name: "QuickFLAC",
    platforms: [.macOS(.v14)],
    targets: [
        // An "executable target" builds into a runnable program.
        .executableTarget(
            name: "QuickFLAC",
            path: "Sources/QuickFLAC",
            // Ships themes.json next to the program; the code reads it via Bundle.module.
            resources: [.copy("Resources/themes.json")]
        )
    ]
)
