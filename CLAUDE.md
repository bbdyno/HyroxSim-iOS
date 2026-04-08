# HyroxSim — Claude Code 규칙

## 프로젝트 개요

HYROX 경기 시뮬레이션 앱. iOS (UIKit) + watchOS (SwiftUI) + 공유 모듈(`HyroxCore`, `HyroxPersistenceApple`, `HyroxLiveActivityApple`).
Tuist 4.x로 프로젝트 관리.

## 세션 Handoff

- 최신 handoff: `.codex/handoffs/latest.md`
- 날짜별 스냅샷: `.codex/handoffs/YYYY-MM-DD.md`
- 새 세션은 초기 분석 전에 최신 handoff를 먼저 읽고 이어서 작업
- handoff에는 절대경로 대신 repo-relative path를 기록하고, simulator ID 같은 머신 의존 값은 재탐색 명령만 남김

## 빌드

```bash
tuist install
tuist generate
xcodebuild build -workspace HyroxSim.xcworkspace -scheme HyroxSim \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -workspace HyroxSim.xcworkspace -scheme HyroxSimWatch \
  -sdk watchsimulator -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

- 파일 추가/삭제 후 반드시 `tuist generate` 실행
- 테스트: `xcodebuild test -workspace HyroxSim.xcworkspace -scheme HyroxSim ...`

## 아키텍처

| 타겟 | 플랫폼 | 제품 | 설명 |
|---|---|---|---|
| HyroxSim | iOS | App (UIKit) | 메인 iOS 앱, MVVM + Coordinator |
| HyroxSimWatch | watchOS | App (SwiftUI) | Apple Watch 앱 |
| HyroxCore | iOS + watchOS | Framework | 도메인 모델, 엔진, 포맷터, 센서/동기화 프로토콜 |
| HyroxPersistenceApple | iOS + watchOS | Framework | SwiftData persistence |
| HyroxLiveActivityApple | iOS | Framework | Live Activity / Dynamic Island 공유 타입 |
| HyroxSimWidgets | iOS | App Extension | Live Activity + Dynamic Island |
| HyroxSimTests | iOS | Unit Tests | iOS 앱 테스트 |
| HyroxKitTests | iOS | Unit Tests | 공유 모듈 테스트 |

## Bundle ID

- iOS: `com.bbdyno.app.HyroxSim`
- watchOS: `com.bbdyno.app.HyroxSim.watchkitapp`
- HyroxCore: `com.bbdyno.app.HyroxSim.core`
- HyroxPersistenceApple: `com.bbdyno.app.HyroxSim.persistence.apple`
- HyroxLiveActivityApple: `com.bbdyno.app.HyroxSim.liveactivity.apple`
- Widgets: `com.bbdyno.app.HyroxSim.widgets`
- App Groups: `group.com.bbdyno.app.HyroxSim`

## 파일 헤더 형식

모든 Swift 파일의 헤더:

```swift
//
//  FileName.swift
//  TargetName
//
//  Created by bbdyno on M/DD/YY.
//
```

- TargetName: HyroxCore / HyroxPersistenceApple / HyroxLiveActivityApple / HyroxSim / HyroxSimWatch / HyroxKitTests / HyroxSimTests / HyroxSimWidgets
- 날짜: `M/D/YY` (예: `4/7/26`)
- 새로 만들거나 수정하는 파일 헤더의 `Created by`는 항상 `bbdyno`
- `Codex` 이름을 파일 헤더에 쓰지 않음
- 기존 파일 헤더 수정하지 않음

## 커밋 규칙

- **커밋 메시지: 한국어**로 작성
- author / committer는 항상 `bbdyno <della.kimko@gmail.com>`
- `Co-Authored-By: Claude` 붙이지 않음
- 작업 단위별로 커밋 분리
- 큰 작업은 단계별로 나눠서 커밋

## 디자인 시스템

### 컬러 스킴
- **블랙+옐로우(골드)** — HYROX 공식 결과 화면 스타일
- 배경: 순수 블랙 (`#000000`)
- 액센트: 골드 (`#FFD700`)
- 텍스트: 흰색 (primary), 회색 (secondary/tertiary)
- iOS: `DesignTokens.swift`에서 중앙 관리
- 다크모드 강제 (`window.overrideUserInterfaceStyle = .dark`)

### 세그먼트 타입 색상
- Run: 블루 (`.systemBlue`)
- RoxZone: 오렌지 (`.systemOrange`)
- Station: 옐로우/골드 (액센트 컬러)

### 컴포넌트
- 시스템 UIAlertController 사용 금지 → `DarkAlertController` 사용
- 시스템 기본 셀 대신 커스텀 셀 사용
- UIKit 화면: `applyDarkNavBarAppearance()` 또는 AppCoordinator 전역 설정
- 모달 UINavigationController: `nav.applyDarkTheme()` 호출

## 모듈 원칙

- **HyroxCore**: CoreLocation, HealthKit, WatchConnectivity import 금지 — 프로토콜만 노출
- **HyroxPersistenceApple**: SwiftData만 담당
- **HyroxLiveActivityApple**: ActivityKit 공유 타입만 담당
- 도메인 모델은 값 타입 (struct), Codable + Hashable + Sendable
- WorkoutEngine은 `@MainActor` class, 시간은 외부 주입 (`Date` 파라미터)
- 센서/동기화 추상화: 프로토콜만 HyroxCore에, 구현은 앱 타겟에

## HYROX 운동 구조

- 31 세그먼트 per 프리셋 (8 × [Run + RoxZone(입장) + Station + RoxZone(퇴장)] - 마지막 퇴장 없음)
- 9개 디비전: Men's Open/Pro (Single/Double), Women's Open/Pro (Single/Double), Mixed Double
- 스테이션 순서: SkiErg → Sled Push → Sled Pull → Burpee Broad Jumps → Rowing → Farmers Carry → Sandbag Lunges → Wall Balls
- 디비전별 무게/횟수: `HyroxDivisionSpec.swift`에 모아둠 (공식 룰북 확인 필요)

## watchOS 특이사항

- UI 실시간 갱신: `TimelineView(.periodic(from: .now, by: 0.5))` 사용 (Timer 미동작)
- `WatchWorkoutSession`: HKWorkoutSession 호스트, `.functionalStrengthTraining` 타입
- 운동 완료 후 네비게이션: `NavigationPath`를 비워서 홈으로 직접 복귀
- 커스텀 템플릿 생성 불가 — 폰에서만 만들고 WatchConnectivity로 동기화

## 워치↔폰 동기화

- **비실시간**: `transferUserInfo` (템플릿), `transferFile` (워크아웃 결과)
- **실시간**: `sendMessage` — 워치 운동 중 매 0.5초 `LiveWorkoutState` 전송
- 폰 → 워치: `WorkoutCommand` (advance/pause/resume/end) 원격 명령
- 워치 운동 시작 → 폰에 자동으로 `LiveWorkoutMirrorViewController` 표시
- idempotent upsert: 같은 ID가 두 번 도착해도 1개만 저장

## 주의사항

- Distance(GPS 측정 거리) 표시하지 않음 — HYROX는 거리 고정이라 불필요
- 운동 화면에 Undo 버튼 없음 — 불필요
- End 버튼은 얼럿 없이 즉시 종료
- 심박수는 세그먼트 전환 시에도 유지 (`lastKnownBpm`)
- HR 어댑터: `predicateForSamples(withStart: Date())` 로 현재 이후 샘플만 수집
- 빌트인 프리셋은 영속화하지 않음 (코드에서 직접 제공)
