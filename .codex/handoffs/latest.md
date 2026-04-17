# HyroxSim Handoff

업데이트: 2026-04-17

## 개요

현재 상태: **페이스 플래너 기능 구현 완료. 커밋 대기.**
이전 완료 작업: `.codex/handoffs/2026-04-08.md` 참조.

## 구현 완료: HYROX 페이스 플래너

hyrox-predictor.netlify.app (로컬: `~/Documents/Personal/hyrox-predictor/planner/index.html`) 알고리즘을 iOS에 포팅.

### 알고리즘 (사이트와 동일)
- overallTimes 기준 정렬 → 5분 버킷 → lerp 보간
- 퍼센타일: 버킷 pct_range 중간값
- 런 분배: 균등(÷8) / 실전(RUN_RATIO_TABLE Season 8 medians)
- rebalanceStations: 잔차 ±1초씩 분배
- Tier: ELITE/WORLD CLASS/EXCEPTIONAL/ADVANCED/COMPETITIVE/INTERMEDIATE/DEVELOPING/BEGINNER

### 데이터
- `Targets/HyroxCore/Resources/PaceReference/pace_planner.json` (89KB) — 버킷 데이터, pre-computed from 201 events
- `Targets/HyroxCore/Resources/PaceReference/v1.json` (5KB) — hyresult 벤치마크 (level anchors)
- `Targets/HyroxCore/Resources/PaceReference/race_model.json` (77KB) — polynomial coefficients (미사용, 제거 가능)
- Pre-compute 스크립트: `/tmp/hyresult-scrape/precompute_buckets.py`

### Swift 모델
- `PacePlanner.swift` — 핵심 엔진 (PacePlannerData, TimeBucket, InterpolatedBucket, PacePlanner, PacePlan)
- `PaceReference.swift` — hyresult 벤치마크 모델
- `PaceReferenceLoader.swift` — loadPacePlanner(), loadBundled()
- `RaceModel.swift`, `PaceDistributor.swift` — 미사용 (polynomial/linear 방식), 테스트는 유지

### UI
- `PacePlannerViewController.swift` — 시/분/초 피커, 균등/실전 토글, Run+Station 인터리브, 퍼센타일/tier, Fine-tune 연결
- `WorkoutBuilderViewController.swift` — goalsTapped()에서 PacePlanner 연결
- `TemplateDetailViewController.swift` — editGoalsTapped()에서 PacePlanner 연결
- Division 없는 커스텀 템플릿: WorkoutGoalSetupVC fallback

### 록스존 처리
- ON: plan의 Run+Rox 합산을 roxFraction으로 분리 (run segment + rox segment), 정수 나눗셈 잔차 보정
- OFF: Run segment에 합산 시간 그대로

### 피커 초기값
- 기존 goal 있으면 template.estimatedDurationSeconds 사용
- 없으면 50th percentile (사이트 setupTime과 동일)

### Tuist
- `Projects/HyroxCore/Project.swift` — resources 등록 (`PaceReference/**`)

## 파일 변경 목록

### 신규
- `Targets/HyroxCore/Resources/PaceReference/v1.json`
- `Targets/HyroxCore/Resources/PaceReference/pace_planner.json`
- `Targets/HyroxCore/Resources/PaceReference/race_model.json`
- `Targets/HyroxCore/Sources/Models/PacePlanner.swift`
- `Targets/HyroxCore/Sources/Models/PaceReference.swift`
- `Targets/HyroxCore/Sources/Models/PaceDistributor.swift`
- `Targets/HyroxCore/Sources/Models/RaceModel.swift`
- `Targets/HyroxCore/Sources/Models/PaceReferenceLoader.swift`
- `Targets/HyroxSim/Sources/Features/WorkoutBuilder/PacePlannerViewController.swift`
- `Targets/HyroxKitTests/Sources/PaceReferenceTests.swift`
- `Targets/HyroxKitTests/Sources/RacePredictorTests.swift`
- `Targets/HyroxKitTests/Sources/PacePlannerTests.swift`

### 수정
- `Projects/HyroxCore/Project.swift`
- `Targets/HyroxSim/Sources/Features/WorkoutBuilder/WorkoutBuilderViewController.swift`
- `Targets/HyroxSim/Sources/Features/Home/TemplateDetailViewController.swift`

## 남은 작업
1. 커밋
2. (선택) race_model.json / RaceModel.swift / PaceDistributor.swift 정리 (미사용)
3. (선택) 스테이션별 인라인 편집 (사이트처럼 ±1초 버튼)
4. (선택) 이미지 저장 기능
5. watchOS: 페이스 플래너는 폰에서만 (워치 불필요)
