# HyroxSim Handoff

업데이트: 2026-04-17

## 개요

현재 상태: **목표 설정 폰↔워치 동기화 + 페이스 플래너 티어 용어/색상 변경 + 다국어화(en/ko) + rank UI 숨김 완료. 커밋 대기.**
이전 완료 작업: `.codex/handoffs/2026-04-17.md` (페이스 플래너), `.codex/handoffs/2026-04-08.md` 참조.

## 구현 완료: 빌트인 프리셋 목표 동기화

아이폰에서 페이스 플래너로 설정한 목표(`goalDurationSeconds`)가 애플워치 pre-workout 화면(ConfirmStartView)에 실시간 반영됨.

### 이전 갭
- 커스텀 템플릿: iPhone `persistence.upsertTemplate` → `sendTemplate` → 워치 ✅
- 빌트인 프리셋 goal: `TemplateGoalOverrideStore`(iOS UserDefaults)에만 저장, 워치 미전송 ❌

### 변경

**HyroxCore (공유)**
- 신규: `Targets/HyroxCore/Sources/Models/TemplateGoalOverrideStore.swift`
  - 기존 iOS 전용 store를 Core로 승격, `public`/`@MainActor`.
  - division 키 포맷 `com.hyroxsim.templateGoalOverride.<raw>` 그대로 유지 (기존 iOS 저장 호환).
  - `save()` 후 `Notification.Name.hyroxTemplateGoalOverrideUpdated` 포스트.
- 삭제: `Targets/HyroxSim/Sources/Common/Storage/TemplateGoalOverrideStore.swift`

**iOS (송신)**
- `AppCoordinator.persistTemplateChanges`: 빌트인 분기에서도 `syncCoordinator.sendTemplate(template)` 호출.

**워치 (수신/표시)**
- `WatchConnectivitySyncCoordinator`:
  - `goalOverrideStore` 프로퍼티 추가.
  - `handleDict` `.template` 케이스: `t.isBuiltIn`이면 `persistence` 대신 `goalOverrideStore.save(t)`. 아니면 기존 upsert.
- `ConfirmStartView`: `resolvedTemplate` @State로 override 반영, notification 관찰 시 재해결. "GOAL h:mm:ss" 표시. Start 시 `resolvedTemplate`로 네비.
- `HomeView`: 프리셋 카드에 `goalOverrideStore.resolvedTemplate(from:)` 적용, notification 시 `overrideRefresh` 카운터로 재렌더.

### 전제/주의
- 빌트인 프리셋은 워치 persistence에 저장하지 않음 (HyroxPresets 코드 제공) — override 디비전 키로만 기록.
- `TemplateGoalOverrideStore`는 UserDefaults 기반이라 App Group 공유 필요 없음 (폰/워치 각자 별도 저장).
- `WorkoutTemplate.createdAt`/`id`는 프로세스마다 `Date()/UUID()`로 새로 생성되므로 "override 여부" 판단에 쓰면 안 됨. UI에선 항상 "GOAL" 라벨.

## 빌드 검증

- `xcodebuild build -scheme HyroxCore -sdk iphonesimulator` ✅
- `xcodebuild build -scheme HyroxCore -sdk watchsimulator` ✅
- `xcodebuild build -scheme HyroxSimWatch -sdk watchsimulator -destination 'id=<46mm simulator id>'` ✅
- `xcodebuild build -scheme HyroxKitTests -sdk iphonesimulator` ✅
- iOS 전체 앱 빌드(`-scheme HyroxSim`)는 사전 이슈로 실패 — `HyroxSimWatch/Resources/Assets.xcassets` AppIcon content 누락 + iOS 스킴이 HyroxSimWatch를 iphonesimulator로 compile 시도하며 `WatchKit` 미해결. 내 변경과 무관(`git stash` 검증).

## 페이스 플래너 티어 용어/색상 변경

레퍼런스 사이트(hyrox-predictor.netlify.app)와 오해 방지를 위해 티어 라벨/컬러 팔레트 차별화.

- **용어** (`PacePlanner.swift:289-298`): ELITE→APEX / WORLD CLASS→PRO / EXCEPTIONAL→EXPERT / ADVANCED→STRONG / COMPETITIVE→SOLID / INTERMEDIATE→STEADY / DEVELOPING→RISING / BEGINNER→STARTER
- **컬러** (`PacePlannerViewController.swift`): 메달 팔레트(금/은/동/초록/파랑/보라/회색) → warm→cool 계열(골드/앰버/코랄/살몬핑크/민트/시안/라일락/중성그레이). 최상위만 HYROX 골드 유지.

## 다국어화 + rank UI 숨김

- 신규 `Localizable.strings` (en/ko) 추가: `pace_planner.mode.equal/adaptive`, `pace_planner.mode.hint.equal/adaptive`, `pace_planner.percentile.format`.
- `Projects/HyroxSim/Project.swift`: 기존 InfoPlist 복사 post-script에 Localizable.strings 2종 추가.
- `PacePlannerViewController.swift`: 하드코딩 한글 제거, `Self.L` enum으로 `NSLocalizedString` 래핑.
- "000명 중 약 000등" rank 라벨 제거 (레퍼런스 사이트 오해 방지, 사용자 요청). `rankLabel` 프로퍼티 및 관련 계산 삭제.

## 파일 변경 목록

### 신규
- `Targets/HyroxCore/Sources/Models/TemplateGoalOverrideStore.swift`
- `Targets/HyroxSim/Resources/en.lproj/Localizable.strings`
- `Targets/HyroxSim/Resources/ko.lproj/Localizable.strings`

### 수정
- `Targets/HyroxSim/Sources/Coordinators/AppCoordinator.swift`
- `Targets/HyroxSimWatch/Sources/Sync/WatchConnectivitySyncCoordinator.swift`
- `Targets/HyroxSimWatch/Sources/Features/Home/ConfirmStartView.swift`
- `Targets/HyroxSimWatch/Sources/Features/Home/HomeView.swift`
- `Targets/HyroxCore/Sources/Models/PacePlanner.swift` — 티어 용어 변경
- `Targets/HyroxSim/Sources/Features/WorkoutBuilder/PacePlannerViewController.swift` — 티어 컬러, NSLocalizedString, rank 라벨 제거
- `Projects/HyroxSim/Project.swift` — Localizable.strings 복사 post-script

### 삭제
- `Targets/HyroxSim/Sources/Common/Storage/TemplateGoalOverrideStore.swift`

## 남은 작업
1. 커밋 (한국어 메시지, 변경 파일 전부).
2. 페이스 플래너 미커밋 분 있으면 함께 또는 선행 커밋 필요 — git status 확인.
3. (선택) iOS 전체 앱 빌드 실패 원인 (AppIcon + WatchKit) 해결.
4. (선택) 페이스 플래너 추가 작업: race_model.json 정리, 스테이션 ±1초, 이미지 저장.
