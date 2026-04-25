// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TermWrap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TermWrap", targets: ["TermWrap"]),
        .executable(name: "TermWrapHost", targets: ["TermWrapHost"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.1")
    ],
    targets: [
        .executableTarget(
            name: "TermWrap",
            path: "Sources/TermWrap",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TermWrapHost",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/TermWrapHost"
        )
    ]
)
