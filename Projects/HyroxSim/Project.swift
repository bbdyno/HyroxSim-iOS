//
//  Project.swift
//  HyroxSim
//
//  Created by bbdyno on 4/8/26.
//

import ProjectDescription

let appVersion = "1.0.0"
let appBuildNumber = "2026.04.10.1"

let signingSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.9",
    "DEVELOPMENT_TEAM": "M79H9K226Y"
]

let versionSettings: SettingsDictionary = [
    "MARKETING_VERSION": .string(appVersion),
    "CURRENT_PROJECT_VERSION": .string(appBuildNumber)
]

let iosCodeSigningBase: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Development"
]

let iosAppBaseSettings: SettingsDictionary = iosCodeSigningBase
    .merging(versionSettings) { _, new in new }
    .merging([
        "OTHER_LDFLAGS": "$(inherited) -ObjC"
    ]) { _, new in new }

let watchAppBaseSettings: SettingsDictionary = versionSettings

let widgetBaseSettings: SettingsDictionary = iosCodeSigningBase
    .merging(versionSettings) { _, new in new }

let project = Project(
    name: "HyroxSim",
    settings: .settings(base: signingSettings),
    targets: [
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
                "UIBackgroundModes": ["location", "audio"],
                "NSSupportsLiveActivities": true
            ]),
            sources: ["../../Targets/HyroxSim/Sources/**"],
            resources: [
                "../../Targets/HyroxSim/Resources/Assets.xcassets",
                "../../Targets/HyroxSim/Resources/GoogleService-Info.plist"
            ],
            entitlements: "../../Targets/HyroxSim/HyroxSim.entitlements",
            dependencies: [
                .external(name: "FirebaseCore"),
                .project(target: "HyroxCore", path: "../HyroxCore"),
                .project(target: "HyroxPersistenceApple", path: "../HyroxPersistenceApple"),
                .project(target: "HyroxLiveActivityApple", path: "../HyroxLiveActivityApple"),
                .target(name: "HyroxSimWidgets"),
                .target(name: "HyroxSimWatch")
            ],
            settings: .settings(
                base: iosAppBaseSettings,
                configurations: [
                    .debug(name: .debug, settings: [
                        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim App Provisioning"
                    ]),
                    .release(name: .release, settings: [
                        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim App Provisioning"
                    ])
                ]
            )
        ),
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
            sources: ["../../Targets/HyroxSimWatch/Sources/**"],
            resources: [
                "../../Targets/HyroxSimWatch/Resources/Assets.xcassets"
            ],
            entitlements: "../../Targets/HyroxSimWatch/HyroxSimWatch.entitlements",
            dependencies: [
                .project(target: "HyroxCore", path: "../HyroxCore"),
                .project(target: "HyroxPersistenceApple", path: "../HyroxPersistenceApple")
            ],
            settings: .settings(base: watchAppBaseSettings)
        ),
        .target(
            name: "HyroxSimWidgets",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "com.bbdyno.app.HyroxSim.widgets",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension"
                ]
            ]),
            sources: ["../../Targets/HyroxSimWidgets/Sources/**"],
            dependencies: [
                .project(target: "HyroxLiveActivityApple", path: "../HyroxLiveActivityApple")
            ],
            settings: .settings(
                base: widgetBaseSettings,
                configurations: [
                    .debug(name: .debug, settings: [
                        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim Widget Extension Provisioning"
                    ]),
                    .release(name: .release, settings: [
                        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim Widget Extension Provisioning"
                    ])
                ]
            )
        ),
        .target(
            name: "HyroxSimTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.bbdyno.app.HyroxSim.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxSimTests/Sources/**"],
            dependencies: [
                .target(name: "HyroxSim"),
                .project(target: "HyroxCore", path: "../HyroxCore"),
                .project(target: "HyroxPersistenceApple", path: "../HyroxPersistenceApple"),
                .project(target: "HyroxLiveActivityApple", path: "../HyroxLiveActivityApple")
            ]
        ),
        .target(
            name: "HyroxKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.bbdyno.app.HyroxSim.kit.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxKitTests/Sources/**"],
            dependencies: [
                .project(target: "HyroxCore", path: "../HyroxCore"),
                .project(target: "HyroxPersistenceApple", path: "../HyroxPersistenceApple"),
                .project(target: "HyroxLiveActivityApple", path: "../HyroxLiveActivityApple")
            ]
        ),
        .target(
            name: "HyroxSimUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.bbdyno.app.HyroxSim.uitests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxSimUITests/Sources/**"],
            dependencies: [
                .target(name: "HyroxSim")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "HyroxSim",
            shared: true,
            buildAction: .buildAction(targets: ["HyroxSim"]),
            testAction: .targets(["HyroxSimTests", "HyroxKitTests", "HyroxSimUITests"], configuration: .debug),
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
