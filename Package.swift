// swift-tools-version: 6.0
// The Swift package for Linux. The Mac app and command build from Skillscout.xcodeproj, generated
// from project.yml, and this package leaves them alone.
//
// Linux/CLI and Linux/App/Core hold symbolic links to the shared files in CLI/ and Skillscout/, so
// each target compiles them into its own module, like the Xcode targets do. A new core file needs
// a link in both folders.

import PackageDescription

var dependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-crypto", "3.0.0"..<"5.0.0"),
]

let core: [Target.Dependency] = [
  .target(name: "CSQLite", condition: .when(platforms: [.linux])),
  .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
]

var targets: [Target] = [
  .systemLibrary(name: "CSQLite", path: "Linux/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
  .executableTarget(name: "skillscout", dependencies: core, path: "Linux/CLI"),
]

var products: [Product] = [
  .executable(name: "skillscout", targets: ["skillscout"]),
]

#if os(Linux)
dependencies.append(.package(url: "https://codeberg.org/aparoksha/adwaita-swift", revision: "af5598fbd6f2425841f426ad388d7a7edd6c90e6"))
targets.append(
  .executableTarget(
    name: "SkillscoutLinux",
    dependencies: core + [.product(name: "Adwaita", package: "adwaita-swift")],
    path: "Linux/App",
    resources: [.copy("Resources")]
  )
)
products.append(.executable(name: "skillscout-gnome", targets: ["SkillscoutLinux"]))
#endif

let package = Package(
  name: "Skillscout",
  platforms: [.macOS(.v15)],
  products: products,
  dependencies: dependencies,
  targets: targets,
  swiftLanguageModes: [.v6]
)
