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
                // 페이스 플래너 버킷 데이터(약 90KB). iOS 앱에서만 쓰므로 워치 번들에서는 제외한다.
                // 글롭 대신 파일을 명시해 두면 리소스 폴더에 파일이 하나 더 생겨도 번들에 조용히 섞이지 않는다.
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/pace_planner.json",
                    inclusionCondition: .when([.ios])
                )
            ]
        )
    ]
)
