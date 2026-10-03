// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserChooser",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BrowserChooser", targets: ["BrowserChooser"])],
    targets: [
        .executableTarget(name: "BrowserChooser"),
        .testTarget(name: "BrowserChooserTests", dependencies: ["BrowserChooser"])
    ]
)
