//
//  HyroxModelContainerFactory.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import os
import SwiftData

/// `ModelContainer` 생성을 한곳에 모은 팩토리.
///
/// 컨테이너 생성은 앱 실행 경로에서 가장 먼저 실패할 수 있는 지점이다(마이그레이션
/// 실패, 디스크 가득 참, 손상된 스토어). 실패하면 **로그를 남기고 그대로 위로
/// 던진다** — 스토어를 지우거나 인메모리로 몰래 대체하지 않는다. 사용자 기록을
/// 말없이 날리는 것보다 오류 화면을 띄우는 쪽이 낫기 때문이다.
public enum HyroxModelContainerFactory {

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "Persistence"
    )

    /// 앱이 쓰는 현재 스키마 버전. 버전을 올릴 때 여기도 같이 바꾼다.
    public static var currentVersionedSchema: any VersionedSchema.Type { HyroxSchemaV2.self }

    /// 현재 스키마.
    public static var currentSchema: Schema { Schema(versionedSchema: currentVersionedSchema) }

    /// 현재 스키마 + 마이그레이션 계획으로 컨테이너를 만든다.
    /// - Parameters:
    ///   - inMemory: `true` 면 디스크를 쓰지 않는다(테스트/스크린샷 모드).
    ///   - storeURL: 저장 위치를 직접 지정할 때만 사용. `nil` 이면 SwiftData 기본
    ///     위치(기존 사용자 스토어와 동일한 경로)를 쓴다. `inMemory` 가 우선한다.
    /// - Throws: 컨테이너 생성 실패 시 SwiftData 가 던진 오류를 그대로 전달한다.
    public static func makeContainer(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = currentSchema
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: HyroxMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            let version = currentVersionedSchema.versionIdentifier
            let detail = "schema v\(version.major).\(version.minor).\(version.patch)"
                + ", inMemory=\(inMemory), error=\(error)"
            logger.error("ModelContainer 생성 실패 — \(detail, privacy: .public)")
            throw error
        }
    }

    /// 특정 스키마 버전으로 **마이그레이션 없이** 컨테이너를 만든다.
    ///
    /// 마이그레이션 검증/진단 전용이다. 앱 실행 경로에서는 쓰지 말 것 —
    /// 과거 버전으로 스토어를 열면 최신 코드가 기대하는 엔티티가 없다.
    /// 테스트에서 "예전 버전으로 만든 스토어"를 재현하는 데 쓴다.
    public static func makeContainer(
        versionedSchema: any VersionedSchema.Type,
        storeURL: URL
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: versionedSchema)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
