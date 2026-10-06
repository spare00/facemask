// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FaceMask",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "FaceMask",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist"
                ])
            ]
        )
    ]
)
