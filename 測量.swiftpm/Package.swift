// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

// iPad の Swift Playgrounds で開くアプリ。外部パッケージは使わない。
// App と SurveyCore は scripts/refresh-playground.sh がリポジトリからコピーする。
let package = Package(
    name: "測量",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "測量",
            targets: ["AppModule"],
            bundleIdentifier: "jp.captain.survey.playground",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .location),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .locationWhenInUse(
                    purposeString: "現在地と精度の円を地図に出すために使います。座標は端末内に WGS84/ITRF で保持します。"
                ),
                .camera(
                    purposeString: "水準器の十字線、顔から端末までの距離、丁張の相対高と、歩行の位置をつなぐ視覚慣性に使います。映像は保存せず、誰かを識別するためにも使いません。"
                )
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: ["SurveyCore"],
            path: "App",
            swiftSettings: [
                .define("SURVEY_PLAYGROUND")
            ],
            exclude: [
                "Info.plist",
                "PrivacyInfo.xcprivacy",
                "Previews.swift",
                "Assets.xcassets"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "SurveyCore",
            path: "SurveyCore"
        )
    ]
)
