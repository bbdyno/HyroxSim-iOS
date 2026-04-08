//
//  Project.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 4/8/26.
//

import ProjectDescription

let project = Project(
    name: "HyroxPersistenceApple",
    settings: .settings(
        base: [
            "SWIFT_VERSION": "5.9",
            "DEVELOPMENT_TEAM": "M79H9K226Y"
        ]
    ),
    targets: [
        .target(
            name: "HyroxPersistenceApple",
            destinations: [.iPhone, .iPad, .appleWatch],
            product: .framework,
            bundleId: "com.bbdyno.app.HyroxSim.persistence.apple",
            deploymentTargets: .multiplatform(iOS: "17.0", watchOS: "10.0"),
            infoPlist: .default,
            sources: ["../../Targets/HyroxPersistenceApple/Sources/**"],
            dependencies: [
                .project(target: "HyroxCore", path: "../HyroxCore")
            ]
        )
    ]
)
