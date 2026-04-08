//
//  Project.swift
//  HyroxLiveActivityApple
//
//  Created by bbdyno on 4/8/26.
//

import ProjectDescription

let project = Project(
    name: "HyroxLiveActivityApple",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_TEAM": "M79H9K226Y"
        ]
    ),
    targets: [
        .target(
            name: "HyroxLiveActivityApple",
            destinations: [.iPhone, .iPad],
            product: .framework,
            bundleId: "com.bbdyno.app.HyroxSim.liveactivity.apple",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxLiveActivityApple/Sources/**"]
        )
    ]
)
