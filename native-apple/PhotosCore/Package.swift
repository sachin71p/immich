// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "PhotosCore",
  platforms: [.iOS("26.1"), .macOS("26.0")],
  products: [
    .library(name: "ImmichAPI", targets: ["ImmichAPI"]),
    .library(name: "CoreModel", targets: ["CoreModel"]),
    .library(name: "Rules", targets: ["Rules"]),
    .library(name: "LocalStore", targets: ["LocalStore"]),
    .library(name: "SyncEngine", targets: ["SyncEngine"]),
    .library(name: "Media", targets: ["Media"]),
    .library(name: "Upload", targets: ["Upload"]),
    .library(name: "Editing", targets: ["Editing"]),
    .library(name: "Search", targets: ["Search"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.8.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    .package(url: "https://github.com/kean/Nuke", from: "13.0.0"),
  ],
  targets: [
    .target(
      name: "ImmichAPI",
      dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ],
      plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
    ),
    .target(name: "CoreModel"),
    .target(name: "Rules", dependencies: ["CoreModel"]),
    .target(name: "LocalStore", dependencies: ["CoreModel", "Rules", .product(name: "GRDB", package: "GRDB.swift")]),
    .target(name: "SyncEngine", dependencies: ["CoreModel", "Rules", "ImmichAPI", "LocalStore"]),
    .target(name: "Media", dependencies: ["CoreModel", .product(name: "Nuke", package: "Nuke")]),
    .target(name: "Upload", dependencies: ["CoreModel", "ImmichAPI", "LocalStore"]),
    .target(name: "Editing", dependencies: ["CoreModel"]),
    .target(name: "Search", dependencies: ["CoreModel", "LocalStore"]),
    .testTarget(
      name: "PhotosCoreTests",
      dependencies: [
        "CoreModel", "Rules", "LocalStore", "SyncEngine", "ImmichAPI", "Media",
        .product(name: "Nuke", package: "Nuke"),
      ],
      resources: [.copy("Fixtures")]
    ),
  ]
)
