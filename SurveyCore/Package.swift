// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurveyCore",
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
            dependencies: ["SurveyCore"]
        )
    ]
)
