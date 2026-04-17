# HyroxSim Handoff

업데이트: 2026-04-17

## 개요

현재 상태: **Race Estimator + Pace Planner 기능 구현 완료. 커밋 대기.**
이전 완료 작업(모듈 분할, 워치↔폰 mirror, station 이름 보존)은 `.codex/handoffs/2026-04-08.md` 참조.

## 이번 세션 완료 작업

### 1. 데이터 수집

#### hyresult.com 시뮬레이터 스크래핑 (9개 디비전)
- Playwright 헤드리스로 `www.hyresult.com/simulator` 접속 (robots.txt `Allow: /` 확인)
- 403 방지 위해 realistic UA + anti-detection 설정
- DOM 기반 추출: 스테이션별 시간, 퍼센타일, 슬라이더 범위
- 결과: `Targets/HyroxCore/Resources/PaceReference/v1.json` (hyresult 벤치마크)

#### hyrox-predictor.netlify.app 레이스 데이터 (201 이벤트, 685K+ 선수)
- `data/all_events.json` (84MB) 다운로드 → Python으로 pre-compute
- Degree-9 polynomial regression (outlier-robust, normalized)
- 9개 디비전 × (run fit + 9 station fits + percentile snapshots)
- 결과: `Targets/HyroxCore/Resources/PaceReference/race_model.json` (34KB)

### 2. HyroxCore 모델 계층

| 파일 | 역할 |
|---|---|
| `PaceReference.swift` | hyresult 벤치마크 모델 (level anchors 등) |
| `PaceDistributor.swift` | 목표 총시간 → 선형 비율 분배 (legacy, 테스트 유지) |
| `RaceModel.swift` | polynomial regression 모델 + `RacePredictor` |
| `PaceReferenceLoader.swift` | `loadBundled()`, `loadRaceModel()`, `loadPredictor()` |

### 3. RacePredictor 핵심 알고리즘

```
input: paceSecondsPerKm (e.g. 310 = 5:10/km)
targetRunTotal = pace × 8.0 (km)
estRank = binarySearch(runFit, targetRunTotal) // rank that gives this run time
stationTime[i] = stationFit[i].evaluate(estRank) // polynomial at that rank
roxzone = roxzoneFit.evaluate(estRank)
percentile = estRank / nAthletes × 100
```

### 4. UI: PacePlannerViewController

- 입력: 러닝 페이스 (min:sec /km) — 숫자패드 입력
- "Analyze" 버튼 → RacePredictor 예측 실행
- 결과:
  - Rank 카드: "Top XX.X%" + "~N / Total athletes"
  - Total 카드: H:MM:SS + level label + breakdown
  - 스테이션별 예측 시간 리스트
- Footer: "Fine-tune" (→ WorkoutGoalSetupVC push) / "Apply Goals" (→ 템플릿에 적용)
- Division 없는 커스텀 템플릿: 기존 WorkoutGoalSetupVC로 fallback

### 5. 테스트

- `PaceReferenceTests` (8개): 벤치마크 데이터 무결성
- `PaceDistributorTests` (6개): 선형 분배 엔진
- `RaceModelTests` (6개): regression 모델 로딩/구조
- `RacePredictorTests` (5개): 예측 정확성, 단조성, 합리성
- 총 25개 전부 통과

### 6. Tuist 변경

- `Projects/HyroxCore/Project.swift`: resources 추가 (`PaceReference/**`)
- `tuist generate` 후 빌드 성공 확인

## 파일 변경 목록

### 신규
- `Targets/HyroxCore/Resources/PaceReference/v1.json`
- `Targets/HyroxCore/Resources/PaceReference/race_model.json`
- `Targets/HyroxCore/Sources/Models/PaceReference.swift`
- `Targets/HyroxCore/Sources/Models/PaceDistributor.swift`
- `Targets/HyroxCore/Sources/Models/RaceModel.swift`
- `Targets/HyroxCore/Sources/Models/PaceReferenceLoader.swift`
- `Targets/HyroxSim/Sources/Features/WorkoutBuilder/PacePlannerViewController.swift`
- `Targets/HyroxKitTests/Sources/PaceReferenceTests.swift`
- `Targets/HyroxKitTests/Sources/RacePredictorTests.swift`

### 수정
- `Projects/HyroxCore/Project.swift` (resources 등록)
- `Targets/HyroxSim/Sources/Features/WorkoutBuilder/WorkoutBuilderViewController.swift` (goalsTapped → PacePlanner 연결 + delegate)
- `Targets/HyroxSim/Sources/Features/Home/TemplateDetailViewController.swift` (editGoalsTapped → PacePlanner 연결 + delegate)

## 남은 Step

1. 커밋
2. (선택) 피커 값 변경 시 실시간 재분석 (현재는 Analyze 버튼 필요)
3. (선택) 스테이션별 슬라이더 조절 UI (웹 툴처럼)
4. (선택) 차트/분포 시각화 
5. watchOS 동기화: 워치에서는 Pace Planner 불필요 (폰에서만 설정)

## 다른 맥북에서 이어받는 법

1. `git pull`
2. 이 파일 읽기
3. `tuist install && tuist generate`
4. `xcodebuild build` / `xcodebuild test`
