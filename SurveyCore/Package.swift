// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurveyCore",
    platforms: [
        // Mac の swift test は、未指定だと 10.13 扱いになり AsyncStream と URLSession.data(for:) で落ちる。
        .macOS(.v12),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SurveyCore", targets: ["SurveyCore"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(
            name: "SurveyCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3", .when(platforms: [.iOS, .macOS, .watchOS, .tvOS]))
            ]
        ),
        .testTarget(
            name: "SurveyCoreTests",
            dependencies: ["SurveyCore"],
            exclude: ["drawings_test"],
            resources: [.copy("docs")]
        )
    ]
)
