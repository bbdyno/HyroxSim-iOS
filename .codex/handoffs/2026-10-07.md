# HyroxSim Handoff

업데이트: 2026-10-07

## 개요

현재 상태: **iOS 앱 전체를 "코스 맵" 디자인 방향으로 리디자인 완료. `redesign/course-map` 브랜치에 커밋됨, main 병합·푸시 전.**
이전 작업: `.codex/handoffs/2026-04-17.md` 참조.

## 디자인 방향

- 주인공은 `CourseMapView` — 구불구불한 레이스 코스 위에 번호 붙은 스테이션 마커.
- 둥근 카드·배지 대신 각진 면과 1pt 헤어라인. `DesignTokens.Radius`는 모두 0.
- 제목·캡션은 `DesignTokens.Font.wide`(넓은 폭), 숫자는 `DesignTokens.Font.number`.
- 목표 대비: 앞서면 골드, 뒤지면 오렌지(`DesignTokens.Color.overGoal`).
- 상세 규칙은 `CLAUDE.md`의 "레이아웃 (코스 맵 방향)" 참조.

## 화면별 변경

- 홈 (`Features/Home/HomeViewController.swift`, `CoursePageCell.swift`): 디비전 페이저 + 코스 그림, 지난 기록/목표, 시작 버튼. 시작 버튼은 상세 화면을 거치지 않고 바로 운동 시작(`homeDidTapStart`). 코스 그림 탭은 상세 화면. 내비게이션 바 숨김.
- 운동 중 (`ActiveWorkoutViewController.swift`): 상단 컴팩트 코스 + 진행 위치. 위치는 `ActiveWorkoutViewModel.courseStationsReached` / `courseFractionToNext`. 거리 표시 제거. 배경은 항상 블랙.
- 결과 (`WorkoutSummaryViewController.swift`): 코스 위 스테이션별 목표 대비 ±, BIGGEST LOSS 행.
- 템플릿 상세: 코스 그림 추가, 목표·록스존을 헤어라인 행으로.
- 워치 미러: 블랙 배경, 헤어라인, 각진 컨트롤. 코스 그림은 없음(`LiveWorkoutState`에 코스 위치 없음).
- 기록·설정·빌더·페이스 플래너·시트·알림창: 모서리와 서체만 일괄 정리.
- `SlideActionControl`: 각진 모양. 제목이 길 때 손잡이 크기 제약이 깨지던 문제 수정(제목 centerX 우선순위 낮춤).

## 워치 앱

- **의도적으로 변경하지 않음.** 작은 화면의 정보량과 스와이프 사용성을 유지하기로 결정(사용자 결정, 2026-10-07).

## 그 외 수정

- `GarminMessageCodec`: 밀리초 필드를 `NSNumber`로 받아 정수 폭에 상관없이 디코딩.
- `WorkoutSummaryViewModelTests`: `titleText`가 템플릿 이름을 반환하도록 바뀐 뒤 갱신되지 않았던 기대값 수정.

## 빌드·검증

- tuist가 mise 기본 버전에 없으면: `mise exec tuist@4.209.0 -- tuist generate --no-open`
- iOS 빌드는 `-sdk iphonesimulator` 없이 `-destination`만 지정 (지정하면 워치 타겟이 iOS SDK로 빌드되어 실패).
- 2026-10-07 검증 결과:
  - `HyroxSimTests` + `HyroxKitTests` ✅, `HyroxSimUITests` ✅ (4개 중 real watch E2E 1개는 flag 없으면 skip)
  - real watch mirror E2E ✅ — `.codex/handoffs/2026-04-08.md` 절차 + `-testLanguage ko -testRegion KR` (테스트가 "종료" 버튼을 찾음). 워치 시뮬레이터 첫 실행 시 건강 권한 창을 먼저 넘겨야 종료 단계가 통과함.
  - iPhone SE (3세대) 시뮬레이터: 홈 → 운동 시작 → 31개 구간 전부 넘김 → 결과 화면까지 확인. 가장 긴 스테이션 이름(Burpee Broad Jumps)도 들어감.
  - `CourseMapViewTests`: 스테이션 0~20개 렌더링 확인. 16개 이상이면 긴 라벨은 말줄임.
  - 스테이션 편집·런 편집·목표 설정·종료 알림창·설정·가민 페어링 화면 확인.
  - 한국어: 홈, 결과 화면 확인.

## 남은 작업

1. 실기기 확인(시뮬레이터로 대체 불가): 실제 가민 기기에서 오는 기록 수신, 실제 워치의 심박·GPS.
2. main 병합, 버전 올리기, 스토어 스크린샷 교체.
3. (논의됨, 미착수) 유료 앱 → 무료+구독 전환, 실제 대회 랭킹 기능.
