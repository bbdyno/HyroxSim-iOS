//
//  RaceTargetForm.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import HyroxCore

/// 대회 편집 화면의 입력값과 검증 규칙.
///
/// UIKit 화면과 분리해 둔 이유는 검증이 화면 없이도 테스트 가능해야 하고,
/// "빈 이름 거부 / 과거 날짜 허용" 같은 규칙이 한곳에만 있어야 하기 때문이다.
struct RaceTargetForm {

    enum ValidationError: LocalizedError, Equatable {
        case emptyEventName

        var errorDescription: String? {
            switch self {
            case .emptyEventName:
                return HyroxSimStrings.Localizable.RaceTarget.Error.emptyName
            }
        }
    }

    /// 편집 중인 기존 대회. 새로 만드는 중이면 nil.
    let existing: HyroxCore.RaceTarget?

    var eventName: String = ""
    var city: String = ""
    var date: Date
    var division: HyroxDivision?
    /// 목표 시간(초). 사용자가 목표를 끄면 nil.
    var goalDurationSeconds: TimeInterval?
    var note: String = ""

    var isEditingExisting: Bool { existing != nil }

    init(existing: HyroxCore.RaceTarget?, defaultDivision: HyroxDivision?, now: Date = Date()) {
        self.existing = existing
        if let existing {
            self.eventName = existing.eventName
            self.city = existing.city ?? ""
            self.date = existing.date
            self.division = existing.division
            self.goalDurationSeconds = existing.goalDurationSeconds
            self.note = existing.note ?? ""
        } else {
            // 기본값은 "한 달 뒤" — 오늘로 두면 대부분 바로 과거 경고를 보게 된다.
            self.date = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
            self.division = defaultDivision
        }
    }

    /// 대회 날짜가 이미 지났는지. 지난 대회도 저장은 되지만 홈 카운트다운에서는 빠진다.
    func isPastDate(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    /// 검증 후 도메인 모델을 만든다. 기존 대회를 편집 중이면 id·createdAt 을 유지한다.
    func makeTarget(now: Date = Date()) throws -> HyroxCore.RaceTarget {
        let trimmedName = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw ValidationError.emptyEventName }

        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        return HyroxCore.RaceTarget(
            id: existing?.id ?? UUID(),
            eventName: trimmedName,
            city: trimmedCity.isEmpty ? nil : trimmedCity,
            date: date,
            division: division,
            goalDurationSeconds: goalDurationSeconds,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}
