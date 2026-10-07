# HyroxSim Handoff

업데이트: 2026-10-07

## 개요

현재 상태: **1.5.0 (빌드 2026.10.07.1) — 코스 맵 리디자인 + 1.3.0 스토어 업데이트 충돌 수정. main 병합 완료.**
이전 기록: `2026-09-21.md`(1.4.0, 로드맵 0~3단계), `2026-10-07.md`(리디자인 상세, 옛 main 기준으로 작성됨).

## ⚠️ 1.4.0 업데이트 충돌 (P0)

- 증상: 1.3.0 스토어가 있는 기기에서 1.4.0 을 실행하면 `SwiftDataError.loadIssueModelContainer` 로 즉시 종료.
  새로 설치한 경우는 문제없음.
- 원인: `HyroxMigrationPlan` 에 실제 출시된 1.3.0 스키마(엔티티 3개, `usesRoxZone` 없음)가 없었음.
  `HyroxSchemaV1` 은 1.3.0 이후 개발 빌드의 모양이라 1.3.0 스토어와 맞지 않음.
- 수정: `HyroxSchemaV0`(1.3.0 스냅샷, 수정 금지) 추가 + v0→v1 경량 단계.
  `PersistenceControllerTests.testStoreWrittenByShipped130OpensUnderCurrentSchema`.
- 검증: 새 시뮬레이터에서 "1.3.0 스키마 빌드 실행 → 덮어 설치" 로 재현·해소 확인. 순수 1.4.0 은 매번 충돌.
- 미확인: 실제 1.3.0 App Store 빌드가 깔린 실기기, 기록이 많은 스토어.
- 수정만 담은 브랜치: `hotfix/shipped-store-migration` (main 1.4.0 + 수정 커밋 하나).

## 리디자인 (코스 맵 방향)

- 규칙은 `CLAUDE.md` "레이아웃 (코스 맵 방향)". 핵심 뷰는 `Targets/HyroxSim/Sources/Common/Views/CourseMapView.swift`.
- 홈: 디비전 페이저 + 코스 → 지난 기록/목표 → 시작 → 내 대회 카드 → 행(커스텀·기록·진척·레이스 데이) → 훈련 세션 → 저장 템플릿.
  시작 버튼은 상세를 거치지 않고 바로 시작(`homeDidTapStart`). 내 대회 카드는 작은 화면에서 시작 버튼이 가려지지 않게 그 아래에 둠.
- 운동 중: 컴팩트 코스 + 위치, 레이스 모드/랩 카운터 통합. 높이 700pt 미만 + 랩 카운터일 때 타이머를 줄이는 컴팩트 배치.
- 결과: 코스 위 스테이션별 ±, 그 아래 격차 분석 카드.
- 1.4.0 에서 추가된 화면(진척·대회 등록·팀 분담·PFT·레이스 데이)은 모서리만 각지게 맞춤.
- 워치 앱은 의도적으로 변경하지 않음(작은 화면 정보량·스와이프 사용성, 사용자 결정).

## 빌드·검증

- 이 맥에서는 `.mise.toml` 이 trust 되지 않아 `mise exec` 가 실패한다. `mise trust` 하거나
  `~/.local/share/mise/installs/tuist/<버전>/tuist` 를 직접 실행.
- iOS 빌드는 `-sdk iphonesimulator` 없이 `-destination` 만 지정.
- 전체 테스트(HyroxKitTests·HyroxSimTests·HyroxSimUITests) 통과. real watch E2E 는 flag 없으면 skip —
  절차는 `2026-04-08.md`, `-testLanguage ko -testRegion KR` 필요.
- 화면 확인: iPhone 17, iPhone SE(3세대) 시뮬레이터. 한국어는 홈·결과.

## 남은 작업

1. App Store Connect: 1.4.0 상태 확인, 1.5.0 버전 생성·릴리스 노트(`docs/release-notes/1.5.0.md`) 입력·심사 제출.
2. 스토어 스크린샷 교체(화면이 전부 바뀜). `tools/generate_app_store_screenshots.swift`.
3. 실기기 확인: 1.3.0 → 1.5.0 업데이트, 가민 기록 수신, 워치 심박·GPS.
4. 팀 분담·PFT·대회 등록 화면 육안 확인(모서리만 일괄 변경함).
5. `2026-09-21.md` 의 남은 작업·결정 대기 항목.
