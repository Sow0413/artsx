// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SurveyCore",
    products: [
        .library(name: "SurveyCore", targets: ["SurveyCore"])
    ],
    targets: [
        .target(name: "SurveyCore"),
        .testTarget(
            name: "SurveyCoreTests",
            dependencies: ["SurveyCore"]
        )
    ]
)
