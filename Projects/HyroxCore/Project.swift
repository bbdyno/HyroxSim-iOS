//
//  Project.swift
//  HyroxCore
//
//  Created by bbdyno on 4/8/26.
//

import ProjectDescription

let project = Project(
    name: "HyroxCore",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_TEAM": "M79H9K226Y"
        ]
    ),
    targets: [
        .target(
            name: "HyroxCore",
            destinations: [.iPhone, .iPad, .appleWatch],
            product: .framework,
            bundleId: "com.bbdyno.app.HyroxSim.core",
            deploymentTargets: .multiplatform(iOS: "17.0", watchOS: "10.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxCore/Sources/**"],
            resources: [
                "../../Targets/HyroxCore/Resources/PaceReference/**"
            ]
        )
    ]
)
