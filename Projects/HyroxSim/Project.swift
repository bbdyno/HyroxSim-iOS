//
//  Project.swift
//  HyroxSim
//
//  Created by bbdyno on 4/8/26.
//

import ProjectDescription

let appVersion = "1.1.0"
let appBuildNumber = "2026.04.18.2"

let signingSettings: SettingsDictionary = [
    "SWIFT_VERSION": "5.9",
    "DEVELOPMENT_TEAM": "M79H9K226Y"
]

let versionSettings: SettingsDictionary = [
    "MARKETING_VERSION": .string(appVersion),
    "CURRENT_PROJECT_VERSION": .string(appBuildNumber)
]

let automaticSigningBase: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Automatic"
]

let manualDevelopmentSigningBase: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Development"
]

let manualDistributionSigningBase: SettingsDictionary = [
    "CODE_SIGN_STYLE": "Manual",
    "CODE_SIGN_IDENTITY": "Apple Distribution"
]

let iosAppBaseSettings: SettingsDictionary = automaticSigningBase
    .merging(versionSettings) { _, new in new }
    .merging([
        "OTHER_LDFLAGS": "$(inherited) -ObjC"
    ]) { _, new in new }

let watchAppBaseSettings: SettingsDictionary = manualDevelopmentSigningBase
    .merging(versionSettings) { _, new in new }
    .merging([
        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim WatchOS Provisioning"
    ]) { _, new in new }

let widgetBaseSettings: SettingsDictionary = manualDevelopmentSigningBase
    .merging(versionSettings) { _, new in new }
    .merging([
        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim Widget Extension Provisioning"
    ]) { _, new in new }

let iosAppDistributionSettings: SettingsDictionary = manualDistributionSigningBase
    .merging([
        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim App Distribution Provisioning"
    ]) { _, new in new }

let watchAppDistributionSettings: SettingsDictionary = manualDistributionSigningBase
    .merging([
        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim WatchOS Distribution Provisioning"
    ]) { _, new in new }

let widgetDistributionSettings: SettingsDictionary = manualDistributionSigningBase
    .merging([
        "PROVISIONING_PROFILE_SPECIFIER": "HyroxSim Widget Distribution Provisioning"
    ]) { _, new in new }

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
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
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
                "NSLocationWhenInUseUsageDescription": "HYROX SIM uses your location during workouts to measure your running pace and distance.",
                "NSLocationAlwaysAndWhenInUseUsageDescription": "HYROX SIM uses your location during workouts to keep measuring your running pace and distance while the workout remains active.",
                "NSMotionUsageDescription": "HYROX SIM uses motion data to support movement analysis during workout sessions.",
                "NSHealthShareUsageDescription": "HYROX SIM reads your heart rate from HealthKit during workouts.",
                "NSHealthUpdateUsageDescription": "HYROX SIM saves completed workout results to the Health app.",
                "UIBackgroundModes": ["location", "audio"],
                "NSSupportsLiveActivities": true
            ]),
            sources: ["../../Targets/HyroxSim/Sources/**"],
            resources: [
                "../../Targets/HyroxSim/Resources/Assets.xcassets",
                "../../Targets/HyroxSim/Resources/GoogleService-Info.plist"
            ],
            entitlements: "../../Targets/HyroxSim/HyroxSim.entitlements",
            scripts: [
                .post(
                    script: """
                    set -eu
                    APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
                    mkdir -p "${APP_BUNDLE}/en.lproj" "${APP_BUNDLE}/ko.lproj"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSim/Resources/en.lproj/InfoPlist.strings" "${APP_BUNDLE}/en.lproj/InfoPlist.strings"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSim/Resources/ko.lproj/InfoPlist.strings" "${APP_BUNDLE}/ko.lproj/InfoPlist.strings"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSim/Resources/en.lproj/Localizable.strings" "${APP_BUNDLE}/en.lproj/Localizable.strings"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSim/Resources/ko.lproj/Localizable.strings" "${APP_BUNDLE}/ko.lproj/Localizable.strings"
                    """,
                    name: "Copy Localized Strings",
                    inputPaths: [
                        "../../Targets/HyroxSim/Resources/en.lproj/InfoPlist.strings",
                        "../../Targets/HyroxSim/Resources/ko.lproj/InfoPlist.strings",
                        "../../Targets/HyroxSim/Resources/en.lproj/Localizable.strings",
                        "../../Targets/HyroxSim/Resources/ko.lproj/Localizable.strings"
                    ],
                    outputPaths: [
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/en.lproj/InfoPlist.strings",
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/ko.lproj/InfoPlist.strings",
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/en.lproj/Localizable.strings",
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/ko.lproj/Localizable.strings"
                    ],
                    basedOnDependencyAnalysis: false
                )
            ],
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
                    .debug(name: .debug),
                    .release(name: .release, settings: iosAppDistributionSettings)
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
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "WKApplication": true,
                "NSLocationWhenInUseUsageDescription": "HYROX SIM uses your location during workouts on Apple Watch to measure your running pace and distance.",
                "NSHealthShareUsageDescription": "HYROX SIM reads your heart rate from HealthKit during workouts on Apple Watch.",
                "NSHealthUpdateUsageDescription": "HYROX SIM saves completed Apple Watch workout results to the Health app.",
                "WKBackgroundModes": ["workout-processing"],
                "WKCompanionAppBundleIdentifier": "com.bbdyno.app.HyroxSim"
            ]),
            sources: ["../../Targets/HyroxSimWatch/Sources/**"],
            resources: [
                "../../Targets/HyroxSimWatch/Resources/Assets.xcassets"
            ],
            entitlements: "../../Targets/HyroxSimWatch/HyroxSimWatch.entitlements",
            scripts: [
                .post(
                    script: """
                    set -eu
                    APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
                    mkdir -p "${APP_BUNDLE}/en.lproj" "${APP_BUNDLE}/ko.lproj"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSimWatch/Resources/en.lproj/InfoPlist.strings" "${APP_BUNDLE}/en.lproj/InfoPlist.strings"
                    cp "${PROJECT_DIR}/../../Targets/HyroxSimWatch/Resources/ko.lproj/InfoPlist.strings" "${APP_BUNDLE}/ko.lproj/InfoPlist.strings"
                    """,
                    name: "Copy Localized InfoPlist Strings",
                    inputPaths: [
                        "../../Targets/HyroxSimWatch/Resources/en.lproj/InfoPlist.strings",
                        "../../Targets/HyroxSimWatch/Resources/ko.lproj/InfoPlist.strings"
                    ],
                    outputPaths: [
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/en.lproj/InfoPlist.strings",
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/ko.lproj/InfoPlist.strings"
                    ],
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .project(target: "HyroxCore", path: "../HyroxCore"),
                .project(target: "HyroxPersistenceApple", path: "../HyroxPersistenceApple")
            ],
            settings: .settings(
                base: watchAppBaseSettings,
                configurations: [
                    .debug(name: .debug),
                    .release(name: .release, settings: watchAppDistributionSettings)
                ]
            )
        ),
        .target(
            name: "HyroxSimWidgets",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "com.bbdyno.app.HyroxSim.widgets",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "CFBundleDisplayName": "HYROX SIM",
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
                    .debug(name: .debug),
                    .release(name: .release, settings: widgetDistributionSettings)
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
