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
                ),
                // v4 대회 기록 스냅샷(9개 디비전 + manifest, 약 110KB).
                // 원격 갱신이 실패하거나 첫 실행·오프라인일 때 쓰는 바닥값이다.
                // `docs/pace/v4/<dataset_version>/*.json` 과 `docs/pace/manifest.json` 의 복사본이며,
                // 버전 디렉터리를 두지 않으므로 데이터를 갱신해도 이 목록은 그대로 둔다.
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/manifest.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/menOpenSingle.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/menOpenDouble.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/menProSingle.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/menProDouble.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/womenOpenSingle.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/womenOpenDouble.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/womenProSingle.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/womenProDouble.json",
                    inclusionCondition: .when([.ios])
                ),
                .glob(
                    pattern: "../../Targets/HyroxCore/Resources/PaceReference/v4/mixedDouble.json",
                    inclusionCondition: .when([.ios])
                )
            ]
        )
    ]
)
