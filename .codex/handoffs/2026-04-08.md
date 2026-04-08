# HyroxSim Handoff

업데이트: 2026-04-08

## 현재 상태

- `HyroxKit` 단일 프레임워크를 `HyroxCore / HyroxPersistenceApple / HyroxLiveActivityApple`로 분리 완료
- 워치↔폰 양방향 workout mirroring 구현 완료
- paired simulator 기준 real watch mirror E2E 검증 완료
- 운동 결과/히스토리에서 station 이름이 `"Station"`으로만 보이던 문제 수정 완료
- 작업 트리는 clean 상태

## 최근 커밋

- `HEAD~0` 아직 미커밋: module split 작업 진행 중
- `e6101d4` `Preserve station names in workout history`
- `3e3da3f` `Add bidirectional watch workout mirroring`

## 모듈 구조

- `Targets/HyroxCore`
  - Models / Engine / Formatters / Presets / Sensors protocol / Sync protocol+payload
- `Targets/HyroxPersistenceApple`
  - SwiftData entities / mappers / `PersistenceController`
- `Targets/HyroxLiveActivityApple`
  - `WorkoutActivityAttributes`

주의:

- 앱/워치 공용 도메인 코드는 이제 `HyroxCore` 기준으로 볼 것
- Apple 전용 코드는 persistence/live activity 모듈로 분리됨

## 핵심 변경

### 1. Watch mirror / bidirectional sync

- iPhone:
  - `Targets/HyroxSim/Sources/App/AppServices.swift`
  - `Targets/HyroxSim/Sources/App/AppDelegate.swift`
  - `Targets/HyroxSim/Sources/App/SceneDelegate.swift`
  - `Targets/HyroxSim/Sources/Coordinators/AppCoordinator.swift`
  - `Targets/HyroxSim/Sources/Sync/WorkoutMirrorController.swift`
  - `Targets/HyroxSim/Sources/Sync/WatchConnectivitySyncCoordinator.swift`
- Watch:
  - `Targets/HyroxSimWatch/Sources/App/HyroxSimWatchApp.swift`
  - `Targets/HyroxSimWatch/Sources/Features/ActiveWorkout/WatchActiveWorkoutModel.swift`
  - `Targets/HyroxSimWatch/Sources/Sensors/WatchWorkoutSession.swift`
  - `Targets/HyroxSimWatch/Sources/Sync/WatchConnectivitySyncCoordinator.swift`
- Shared:
  - `Targets/HyroxKit/Sources/Sync/LiveSyncPacket.swift`
  - `Targets/HyroxKit/Sources/Sync/LiveWorkoutState.swift`
  - `Targets/HyroxKit/Sources/Sync/SyncCoordinatorProtocol.swift`

핵심 동작:

- 워치 시작 → 아이폰 실시간 미러 표시
- 아이폰 원격 명령 `advance/pause/resume/end` → 워치 전달
- 워치 종료 시 mirrored session + WatchConnectivity fallback 양쪽으로 종료 전파
- 아이폰 미러 dismiss 시 확인 alert가 떠 있어도 미러 화면 자체를 명시적으로 닫도록 처리

### 2. Station 이름 보존 / fallback

- 저장 필드 추가:
  - `Targets/HyroxKit/Sources/Persistence/Entities/StoredSegment.swift`
  - `Targets/HyroxKit/Sources/Persistence/Mappers/CompletedWorkoutMapper.swift`
- 표시 fallback 추가:
  - `Targets/HyroxKit/Sources/Models/CompletedWorkout.swift`
  - `Targets/HyroxSim/Sources/Features/Summary/WorkoutSummaryViewModel.swift`
  - `Targets/HyroxSim/Sources/Features/Summary/WorkoutSummaryViewController.swift`
  - `Targets/HyroxSimWatch/Sources/Features/Summary/SummaryView.swift`

핵심 동작:

- 새로 저장되는 workout은 `stationDisplayName`과 `plannedDistanceMeters`를 영속화
- 예전에 저장된 공식 HYROX division workout은 station 순서 기반 fallback으로 이름 복원
- 예전에 저장된 custom workout은 원본 이름이 저장되지 않았다면 완전 복구 불가

## 검증

### real watch mirror E2E

검증 대상:

- `Targets/HyroxSimUITests/Sources/LiveWorkoutMirrorUITests.swift`

주의:

- 이 테스트는 `xcodebuild test`만으로는 부족하고, 실행 중인 20초 창 안에 watch app을 별도로 launch 해야 함
- simulator ID는 머신마다 다르므로 새 맥북에서는 다시 찾을 것

재현 절차:

1. paired simulator ID 찾기
   - `xcrun simctl list devices | rg "paired Apple Watch|Apple Watch Series 11"`
2. flag 생성
   - `touch /tmp/hyrox-real-watch-e2e.flag`
3. iPhone UI test 시작
   - `xcodebuild test -quiet -workspace HyroxSim.xcworkspace -scheme HyroxSim -destination 'id=<IPHONE_ID>' -only-testing:HyroxSimUITests/LiveWorkoutMirrorUITests/testRealWatchWorkoutMirrorsToPhoneAndDismisses`
4. 약 8초 뒤 watch app launch
   - `xcrun simctl launch --terminate-running-process <WATCH_ID> com.bbdyno.app.HyroxSim.watchkitapp UITestAutoStartWatchWorkout UITestAutoEndWatchWorkout`

마지막 검증 상태:

- 위 절차로 real watch mirror UI test 반복 통과 확인

### station 이름 관련 테스트

- `xcodebuild test -quiet -workspace HyroxSim.xcworkspace -scheme HyroxSim -destination 'id=<IPHONE_ID>' -only-testing:HyroxKitTests/MappersTests -only-testing:HyroxKitTests/PersistenceControllerTests -only-testing:HyroxSimTests/WorkoutSummaryViewModelTests`

## 새 세션에서 바로 이어갈 때

1. 이 파일 먼저 읽기
2. `git status`
3. `git log --oneline -5`
4. simulator 관련 작업이면 ID를 다시 찾고 진행
5. 새 작업이 끝나면 이 파일과 날짜 스냅샷을 같이 갱신

## 메모

- 커밋 규칙은 `CLAUDE.md` 기준
- author / committer는 항상 `bbdyno <della.kimko@gmail.com>`
- 새 파일 헤더의 `Created by`도 항상 `bbdyno`로 유지하고 `Codex` 표기는 남기지 않음
- 이 handoff는 다른 맥북에서도 그대로 쓰기 위해 repo-relative path만 사용
