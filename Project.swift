import ProjectDescription

let project = Project(
    name: "HyroxSim",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9"
        ]
    ),
    targets: [
        // MARK: - HyroxSim (iOS App, UIKit)
        .target(
            name: "HyroxSim",
            destinations: .iOS,
            product: .app,
            bundleId: "com.bbdyno.app.HyroxSim",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                    "UISceneConfigurations": [
                        "UIWindowSceneSessionRoleApplication": [
                            [
                                "UISceneConfigurationName": "Default Configuration",
                                "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate"
                            ]
                        ]
                    ]
                ],
                "UILaunchScreen": [
                    "UIColorName": "systemBackground"
                ],
                "NSLocationWhenInUseUsageDescription": "운동 중 페이스와 거리 측정을 위해 위치 정보가 필요합니다.",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "운동 중 페이스와 거리 측정을 위해 위치 정보가 필요합니다.",
                "NSMotionUsageDescription": "운동 분석을 위해 모션 데이터를 사용합니다.",
                "NSHealthShareUsageDescription": "심박수 등 운동 데이터를 읽어옵니다.",
                "NSHealthUpdateUsageDescription": "운동 결과를 건강 앱에 저장합니다.",
                "UIBackgroundModes": ["location", "audio"]
            ]),
            sources: ["Targets/HyroxSim/Sources/**"],
            resources: [
                "Targets/HyroxSim/Resources/Assets.xcassets"
            ],
            entitlements: "Targets/HyroxSim/HyroxSim.entitlements",
            dependencies: [
                .target(name: "HyroxKit")
            ]
        ),

        // MARK: - HyroxSimWatch (watchOS App, SwiftUI)
        .target(
            name: "HyroxSimWatch",
            destinations: [.appleWatch],
            product: .app,
            bundleId: "com.bbdyno.app.HyroxSim.watchkitapp",
            deploymentTargets: .watchOS("10.0"),
            infoPlist: .extendingDefault(with: [
                "WKApplication": true,
                "NSLocationWhenInUseUsageDescription": "운동 중 페이스와 거리 측정을 위해 위치 정보가 필요합니다.",
                "NSHealthShareUsageDescription": "심박수 등 운동 데이터를 읽어옵니다.",
                "NSHealthUpdateUsageDescription": "운동 결과를 건강 앱에 저장합니다.",
                "WKBackgroundModes": ["workout-processing"],
                "WKCompanionAppBundleIdentifier": "com.bbdyno.app.HyroxSim"
            ]),
            sources: ["Targets/HyroxSimWatch/Sources/**"],
            resources: [
                "Targets/HyroxSimWatch/Resources/Assets.xcassets"
            ],
            entitlements: "Targets/HyroxSimWatch/HyroxSimWatch.entitlements",
            dependencies: [
                .target(name: "HyroxKit")
            ]
        ),

        // MARK: - HyroxKit (Shared Framework, iOS + watchOS)
        .target(
            name: "HyroxKit",
            destinations: [.iPhone, .iPad, .appleWatch],
            product: .framework,
            bundleId: "com.bbdyno.app.HyroxSim.kit",
            deploymentTargets: .multiplatform(iOS: "17.0", watchOS: "10.0"),
            infoPlist: .default,
            sources: ["Targets/HyroxKit/Sources/**"]
        ),

        // MARK: - HyroxSimTests (iOS Unit Tests)
        .target(
            name: "HyroxSimTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.bbdyno.app.HyroxSim.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["Targets/HyroxSimTests/Sources/**"],
            dependencies: [
                .target(name: "HyroxSim")
            ]
        ),

        // MARK: - HyroxKitTests (Shared Framework Tests)
        .target(
            name: "HyroxKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.bbdyno.app.HyroxSim.kit.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["Targets/HyroxKitTests/Sources/**"],
            dependencies: [
                .target(name: "HyroxKit")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "HyroxSim",
            shared: true,
            buildAction: .buildAction(targets: ["HyroxSim"]),
            testAction: .targets(["HyroxSimTests", "HyroxKitTests"], configuration: .debug),
            runAction: .runAction(configuration: .debug, executable: "HyroxSim")
        ),
        .scheme(
            name: "HyroxSimWatch",
            shared: true,
            buildAction: .buildAction(targets: ["HyroxSimWatch"]),
            runAction: .runAction(configuration: .debug, executable: "HyroxSimWatch")
        )
    ]
)
