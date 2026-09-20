//
//  ActiveWorkoutViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import ActivityKit
import Foundation
import Observation
import os
import HyroxCore
import HyroxLiveActivityApple
import HyroxPersistenceApple

@Observable
@MainActor
public final class ActiveWorkoutViewModel {

    // MARK: - Public state (UI binding)
    public private(set) var segmentLabel: String = ""
    public private(set) var segmentSubLabel: String?
    public private(set) var currentDisplayTitle: String = ""
    public private(set) var nextDisplayTitle: String?
    public private(set) var segmentElapsedText: String = "00:00"
    public private(set) var totalElapsedText: String = "0:00:00"
    public private(set) var paceText: String = "—"
    public private(set) var distanceText: String = "0 m"
    public private(set) var heartRateText: String = "—"
    public private(set) var heartRateZone: HeartRateZone?
    public private(set) var goalText: String = "—"
    public private(set) var goalDeltaText: String = "—"
    public private(set) var isOverGoal: Bool = false
    public private(set) var totalGoalText: String = "—"
    public private(set) var totalDeltaText: String = "—"
    public private(set) var isOverTotalGoal: Bool = false
    public private(set) var stationNameText: String?
    public private(set) var stationTargetText: String?
    public private(set) var accentKind: AccentKind = .run
    public private(set) var isPaused: Bool = false
    public private(set) var isFinished: Bool = false
    public private(set) var isLastSegment: Bool = false
    public private(set) var gpsStatus: GPSStatus = .searching

    // MARK: - 레이스 데이 (대회 당일 표시)

    /// 레이스 모드. 켜면 누적 델타를 크게 강조하고 런 구간에서 랩 카운터를 노출한다.
    /// 대회 당일 내내 유지돼야 해서 기기에 저장한다.
    public private(set) var isRaceMode: Bool = RaceDayPreferences.shared.isRaceModeEnabled
    /// 현재 런 구간에서 선수가 직접 센 바퀴 수. 기록에는 남기지 않는다.
    public private(set) var lapCount: Int = 0
    /// 랩 카운터를 보여줄 구간인지. 랩은 런에서만 의미가 있다.
    public private(set) var isLapCounterAvailable: Bool = false
    /// 다음 구간 이름 ("Wall Balls"). 마지막 구간이면 nil.
    public private(set) var nextTargetLabel: String?
    /// 다음 구간의 목표 시간 ("04:10"). 목표가 없으면 nil.
    public private(set) var nextTargetGoalText: String?

    public enum AccentKind { case run, roxZone, station }

    /// GPS signal quality based on horizontalAccuracy of most recent sample
    public enum GPSStatus: Hashable {
        case off          // station segment, GPS not tracked
        case searching    // no samples yet
        case weak         // accuracy > 20m
        case fair         // accuracy 10-20m
        case strong       // accuracy < 10m
    }

    // MARK: - Dependencies
    private let engine: WorkoutEngine
    private let locationStream: any LocationStreaming
    private let heartRateStream: any HeartRateStreaming
    private let persistence: PersistenceController
    private let syncCoordinator: (any SyncCoordinator)?
    private let checkpointStore: WorkoutCheckpointStore
    private let maxHeartRate: Int
    /// 완료된 운동을 건강 앱에 남기는 어댑터. nil 이면 저장하지 않는다(테스트/비활성 기기).
    private let healthWorkoutSaver: (any HealthWorkoutSaving)?

    /// 체크포인트/복구가 같은 운동을 가리키도록 고정되는 ID (idempotent upsert 용).
    private let workoutId = UUID()

    // MARK: - Internal
    private var displayTimer: Timer?
    private var checkpointTimer: Timer?
    private var locationTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var lastKnownBpm: Int?
    private var liveActivity: Activity<WorkoutActivityAttributes>?
    private var alertedGoalSegmentId: UUID?
    /// GPS 스트림이 실제로 살아 있는지. 권한 거부/시작 실패 시 false → GPS OFF 표시.
    private var isLocationActive = false
    /// 런 구간 랩 카운터. 구간이 바뀌면 스스로 0 으로 돌아간다.
    private var lapCounter = RaceLapCounter()
    /// 이번 운동에서 GPS 추적이 한 번이라도 살아 있었는지. `cleanup()` 이후에도 실내/실외 판정에 쓰인다.
    private var didTrackLocation = false
    /// 건강 앱 쓰기 권한 확보 여부. 거부면 저장을 조용히 건너뛴다.
    private var healthAuthorizationTask: Task<Bool, Never>?

    private static let logger = Logger(
        subsystem: "com.bbdyno.app.HyroxSim",
        category: "HealthWorkout"
    )

    /// Live Activity 가 "멈춘 화면"으로 잠금화면에 남지 않도록 하는 stale 여유 시간.
    private static let activityStaleInterval: TimeInterval = 4 * 60
    /// 주기 체크포인트 간격.
    private static let checkpointInterval: TimeInterval = 30

    // MARK: - Callbacks
    public var errorHandler: ((Error) -> Void)?
    public var finishHandler: ((CompletedWorkout) -> Void)?
    public var cancelHandler: (() -> Void)?
    public var goalAlertHandler: (() -> Void)?

    public init(
        template: WorkoutTemplate,
        locationStream: any LocationStreaming,
        heartRateStream: any HeartRateStreaming,
        persistence: PersistenceController,
        maxHeartRate: Int = 190,
        syncCoordinator: (any SyncCoordinator)? = nil,
        checkpointStore: WorkoutCheckpointStore = .shared,
        healthWorkoutSaver: (any HealthWorkoutSaving)? = HealthKitWorkoutSaver()
    ) {
        self.engine = WorkoutEngine(template: template)
        self.locationStream = locationStream
        self.heartRateStream = heartRateStream
        self.persistence = persistence
        self.maxHeartRate = maxHeartRate
        self.syncCoordinator = syncCoordinator
        self.checkpointStore = checkpointStore
        self.healthWorkoutSaver = healthWorkoutSaver
    }

    // MARK: - Lifecycle

    public func start() async {
        // 1) 센서(=권한 창)를 엔진 시작 전에 끝낸다.
        //    권한 창에 사용자가 답하는 시간이 Run 1 / 총 시간에 포함되면 안 되기 때문.
        let sensorError = await prepareSensors()

        // 2) 엔진 시작. 실패는 치명적이라 여기서만 중단한다.
        do {
            try engine.start(at: Date())
        } catch {
            errorHandler?(error)
            return
        }

        setupSyncCallbacks()
        syncCoordinator?.sendWorkoutStarted(template: engine.template, origin: .phone)

        // 3) 센서 성공 여부와 무관하게 타이머·Live Activity·워치 전송을 시작한다.
        if isLocationActive {
            locationTask = engine.attachLocationStream(locationStream)
        }
        heartRateTask = engine.attachHeartRateStream(heartRateStream)
        startDisplayTimer()
        startCheckpointTimer()
        startLiveActivity()
        refresh()
        writeCheckpoint()

        // 4) 센서 실패는 운동을 막지 않고 안내만 한다.
        if let sensorError {
            errorHandler?(sensorError)
        }
    }

    /// 위치/심박 스트림을 각각 독립적으로 시작한다.
    /// 한쪽이 실패해도 다른 쪽은 계속 시도하며, 운동 자체는 항상 진행된다.
    /// - Returns: 사용자에게 안내할 대표 오류 (없으면 nil). 위치 오류를 우선한다.
    private func prepareSensors() async -> Error? {
        var locationError: Error?
        var heartRateError: Error?

        // 건강 앱 쓰기 권한은 **기다리지 않고** 요청만 걸어 둔다. 사용자가 시트에 답할 때까지
        // 운동 시작이 멈추면, 위치 권한에서 고쳤던 문제를 그대로 반복하게 된다.
        // 결과는 종료 시점에 확인한다(그때는 기다려도 운동에 영향이 없다).
        startHealthAuthorizationIfNeeded()

        do {
            try await locationStream.start()
            isLocationActive = true
            didTrackLocation = true
        } catch {
            isLocationActive = false
            locationError = error
        }

        do {
            try await heartRateStream.start()
        } catch {
            heartRateError = error
        }

        return locationError ?? heartRateError
    }

    /// 운동 쓰기 권한 요청을 시작만 해 둔다. 결과는 `resolveHealthAuthorization()` 에서 읽는다.
    private func startHealthAuthorizationIfNeeded() {
        guard let healthWorkoutSaver, healthAuthorizationTask == nil else { return }
        healthAuthorizationTask = Task { await healthWorkoutSaver.requestAuthorization() }
    }

    /// 종료 시점에 권한 결과를 확인한다. 실패는 로그만 남기고 삼킨다 — 운동 진행을 막지 않는다.
    private func resolveHealthAuthorization() async -> Bool {
        guard let healthAuthorizationTask else { return false }
        let granted = await healthAuthorizationTask.value
        if !granted {
            Self.logger.notice("건강 앱 쓰기 권한이 없어 이번 운동은 건강 앱에 저장하지 않습니다.")
        }
        return granted
    }

    public func advance() {
        do {
            try engine.advance(at: Date())
            refresh()
            if engine.isFinished {
                Task { await finishAndSave() }
            } else {
                // 세그먼트 전환마다 체크포인트 — 여기까지의 기록은 크래시에도 살아남는다.
                writeCheckpoint()
            }
        } catch { errorHandler?(error) }
    }

    public func undo() {
        do {
            try engine.undo(at: Date())
            refresh()
        } catch { errorHandler?(error) }
    }

    public func togglePause() {
        do {
            if isPaused {
                try engine.resume(at: Date())
            } else {
                try engine.pause(at: Date())
            }
            isPaused = !isPaused
            refresh()
            writeCheckpoint()
        } catch { errorHandler?(error) }
    }

    public func endWorkout() {
        do {
            try engine.finish(at: Date())
            Task { await finishAndSave() }
        } catch { errorHandler?(error) }
    }

    public func cancelWorkout() {
        cleanup()
        checkpointStore.clear()
        cancelHandler?()
    }

    // MARK: - 레이스 데이

    /// 이번 운동이 쓰는 템플릿. 페이스 카드가 구간 목표를 읽어 가는 원본.
    public var template: WorkoutTemplate { engine.template }

    /// 레이스 모드 토글. 화면 표시만 바꾸고 엔진/기록에는 손대지 않는다.
    public func setRaceMode(_ enabled: Bool) {
        guard isRaceMode != enabled else { return }
        isRaceMode = enabled
        RaceDayPreferences.shared.isRaceModeEnabled = enabled
    }

    public func toggleRaceMode() {
        setRaceMode(!isRaceMode)
    }

    /// 한 바퀴 추가. 대회장 트랙은 선수가 직접 세야 한다.
    public func incrementLap() {
        lapCounter.increment()
        lapCount = lapCounter.count
    }

    /// 잘못 누른 한 바퀴 취소. 0 밑으로는 내려가지 않는다.
    public func decrementLap() {
        lapCounter.decrement()
        lapCount = lapCounter.count
    }

    /// 레이스 데이 화면(페이스 카드·체크리스트)에 넘길 맥락.
    /// 등록된 대회가 있으면 그 목표를, 없으면 템플릿 목표를 쓴다.
    public func makeRaceDayContext() -> RaceDayContext {
        let raceTarget = try? persistence.fetchUpcomingRaceTarget()
        return RaceDayContext(template: template, raceTarget: raceTarget ?? nil)
    }

    // MARK: - Sync (워치 양방향 연동)

    private func setupSyncCallbacks() {
        syncCoordinator?.onReceiveCommand = { [weak self] cmd in
            self?.handleRemoteCommand(cmd)
        }
        syncCoordinator?.onHeartRateRelayReceived = { [weak self] relay in
            self?.handleHeartRateRelay(relay)
        }
    }

    private func handleRemoteCommand(_ cmd: WorkoutCommand) {
        switch cmd {
        case .advance: advance()
        case .pause: if !isPaused { togglePause() }
        case .resume: if isPaused { togglePause() }
        case .end: endWorkout()
        }
    }

    private func handleHeartRateRelay(_ relay: HeartRateRelay) {
        let sample = HeartRateSample(timestamp: relay.timestamp, bpm: relay.bpm)
        engine.ingest(heartRateSample: sample)
    }

    private func broadcastLiveState() {
        guard let syncCoordinator else { return }
        let accentRaw: String = switch accentKind {
        case .run: "run"
        case .roxZone: "roxZone"
        case .station: "station"
        }
        let gpsStrong = gpsStatus == .strong
        let gpsActive = gpsStatus != .off
        let now = Date()
        let idx = engine.currentSegmentIndex ?? 0
        let segGoalRaw = engine.currentSegment != nil
            ? resolveSegmentGoalRaw(currentIndex: idx)
            : (goalSeconds: nil as TimeInterval?, actualBase: 0)
        let totalGoalRaw = engine.currentSegment != nil
            ? resolveTotalGoalRaw(currentIndex: idx)
            : (totalGoal: nil as TimeInterval?, goalSoFar: 0)
        let state = LiveWorkoutState(
            segmentLabel: segmentLabel, segmentSubLabel: segmentSubLabel,
            currentDisplayTitle: currentDisplayTitle, nextDisplayTitle: nextDisplayTitle,
            segmentElapsedText: segmentElapsedText, totalElapsedText: totalElapsedText,
            paceText: paceText, distanceText: distanceText,
            heartRateText: heartRateText, heartRateZoneRaw: heartRateZone?.rawValue,
            goalText: goalText, goalDeltaText: goalDeltaText, isOverGoal: isOverGoal,
            stationNameText: stationNameText, stationTargetText: stationTargetText,
            accentKindRaw: accentRaw, isPaused: isPaused, isFinished: isFinished, isLastSegment: isLastSegment,
            gpsStrong: gpsStrong, gpsActive: gpsActive,
            templateName: engine.template.name,
            totalSegmentCount: engine.template.segments.count,
            currentSegmentIndex: idx,
            origin: .phone,
            broadcastedAt: now,
            segmentElapsedSeconds: engine.segmentElapsed(at: now),
            totalElapsedSeconds: engine.totalElapsed(at: now),
            segmentGoalSeconds: segGoalRaw.goalSeconds,
            segmentGoalActualBaseSeconds: segGoalRaw.goalSeconds != nil ? segGoalRaw.actualBase : nil,
            totalGoalSeconds: totalGoalRaw.totalGoal,
            totalGoalSoFarSeconds: totalGoalRaw.totalGoal != nil ? totalGoalRaw.goalSoFar : nil
        )
        syncCoordinator.sendLiveState(state)
    }

    // MARK: - Refresh

    func refresh() {
        let now = Date()
        let segElapsed = engine.segmentElapsed(at: now)
        let totalElapsed = engine.totalElapsed(at: now)
        segmentElapsedText = DurationFormatter.ms(segElapsed)
        totalElapsedText = DurationFormatter.hms(totalElapsed)

        guard let current = engine.currentSegment, let index = engine.currentSegmentIndex else {
            isFinished = engine.isFinished
            currentDisplayTitle = ""
            nextDisplayTitle = nil
            isOverGoal = false
            isOverTotalGoal = false
            syncLapCounter(to: nil, segmentType: nil)
            nextTargetLabel = nil
            nextTargetGoalText = nil
            return
        }

        let total = engine.template.segments.count
        let live = engine.liveMeasurementsSnapshot
        currentDisplayTitle = displayTitle(for: current, at: index)
        nextDisplayTitle = nextDisplayTitle(after: index, currentType: current.type)

        // 구간이 바뀌면 랩은 0 부터 다시 센다.
        syncLapCounter(to: current.id, segmentType: current.type)

        // Live Activity 가 보여줄 "다음 구간 목표".
        let nextTarget = resolveNextTarget(currentIndex: index)
        nextTargetLabel = nextTarget?.label
        nextTargetGoalText = nextTarget?.goalText

        // Delta calculation: Run/Rox uses combined Run+Rox goal vs cumulative elapsed.
        let goalInfo = resolveGoalAndDelta(currentIndex: index, segElapsed: segElapsed)
        goalText = goalInfo.goalText
        goalDeltaText = goalInfo.deltaText
        isOverGoal = goalInfo.isOver
        if isOverGoal, alertedGoalSegmentId != current.id {
            alertedGoalSegmentId = current.id
            goalAlertHandler?()
        }

        // Cumulative delta vs whole-workout goal.
        let totalInfo = resolveTotalGoalAndDelta(totalElapsed: totalElapsed, currentIndex: index)
        totalGoalText = totalInfo.goalText
        totalDeltaText = totalInfo.deltaText
        isOverTotalGoal = totalInfo.isOver

        switch current.type {
        case .run:
            let runIndex = countOfType(.run, upTo: index + 1)
            let runTotal = countOfType(.run, upTo: total)
            segmentLabel = "RUN \(runIndex) / \(runTotal)"
            segmentSubLabel = nil
            accentKind = .run
            distanceText = DistanceFormatter.short(live.distanceMeters)
            paceText = DurationFormatter.pace(live.averagePaceSecondsPerKm(activeDuration: segElapsed))
            stationNameText = nil
            stationTargetText = nil

        case .roxZone:
            segmentLabel = "ROX ZONE"
            if let next = engine.nextSegment, next.type == .station, let kind = next.stationKind {
                segmentSubLabel = "→ \(kind.displayName)"
            } else {
                segmentSubLabel = nil
            }
            accentKind = .roxZone
            distanceText = DistanceFormatter.short(live.distanceMeters)
            paceText = DurationFormatter.pace(live.averagePaceSecondsPerKm(activeDuration: segElapsed))
            stationNameText = nil
            stationTargetText = nil

        case .station:
            let stationIndex = countOfType(.station, upTo: index + 1)
            let stationTotal = countOfType(.station, upTo: total)
            segmentLabel = "STATION \(stationIndex) / \(stationTotal)"
            segmentSubLabel = current.stationKind?.displayName ?? "Station"
            accentKind = .station
            stationNameText = current.stationKind?.displayName
            stationTargetText = current.stationTarget?.formatted
            paceText = "—"
            distanceText = "—"
        }

        // Heart rate — persist across segments (don't reset on advance)
        // liveMeasurements buffer clears on advance, so we keep the last known value
        if let lastHR = live.heartRateSamples.last {
            lastKnownBpm = lastHR.bpm
        }
        if let bpm = lastKnownBpm {
            heartRateText = "\(bpm)"
            heartRateZone = HeartRateZone.zone(forHeartRate: bpm, maxHeartRate: maxHeartRate)
        } else {
            heartRateText = "—"
            heartRateZone = nil
        }

        // GPS status from latest location sample accuracy
        if !isLocationActive || current.type == .station {
            // 권한 거부/시작 실패 시에도 운동은 계속되고, GPS 만 비활성으로 표시한다.
            gpsStatus = .off
        } else if let lastLoc = live.locationSamples.last {
            let acc = lastLoc.horizontalAccuracy
            if acc < 10 { gpsStatus = .strong }
            else if acc < 20 { gpsStatus = .fair }
            else { gpsStatus = .weak }
        } else {
            gpsStatus = .searching
        }

        isFinished = engine.isFinished
        isLastSegment = engine.isLastSegment

        updateLiveActivity()
        broadcastLiveState()
    }

    /// 랩 카운터를 현재 구간에 맞춘다. 구간이 바뀌면 0 으로 초기화된다.
    /// 랩은 런에서만 의미가 있어 전환/스테이션 구간에서는 카운터를 숨긴다.
    private func syncLapCounter(to segmentId: UUID?, segmentType: SegmentType?) {
        lapCounter.syncSegment(segmentId)
        lapCount = lapCounter.count
        isLapCounterAvailable = segmentType == .run
    }

    /// 전환 구간을 건너뛴 "다음 구간"의 이름과 목표 시간.
    /// 런 블록이면 뒤따르는 전환 구간 목표까지 합쳐 실제로 써야 할 시간을 보여준다.
    func resolveNextTarget(currentIndex: Int) -> (label: String, goalText: String?)? {
        let segments = engine.template.segments
        var index = currentIndex + 1

        while segments.indices.contains(index) {
            let segment = segments[index]
            guard segment.type != .roxZone else {
                index += 1
                continue
            }

            let goal: TimeInterval? = {
                switch segment.type {
                case .station:
                    return segment.goalDurationSeconds
                case .run:
                    let start = max(blockStartIndex(runIndex: index), currentIndex + 1)
                    let end = max(blockEndIndex(runIndex: index), start)
                    let goals = segments[start...end].compactMap(\.goalDurationSeconds)
                    return goals.isEmpty ? nil : goals.reduce(0, +)
                case .roxZone:
                    return nil
                }
            }()

            return (
                displayTitle(for: segment, at: index),
                goal.map(DurationFormatter.ms)
            )
        }

        return nil
    }

    /// 현재 세그먼트/블록의 raw goal + 현재 세그먼트 이전까지의 누적 실행 시간.
    /// 수신측이 로컬 클록으로 보간할 때 사용. nil 목표면 (nil, 0) 반환.
    func resolveSegmentGoalRaw(currentIndex: Int) -> (goalSeconds: TimeInterval?, actualBase: TimeInterval) {
        let current = engine.template.segments[currentIndex]
        switch current.type {
        case .station:
            guard let goal = current.goalDurationSeconds, goal > 0 else { return (nil, 0) }
            return (goal, 0)
        case .run, .roxZone:
            guard let runIndex = owningRunIndex(for: currentIndex) else { return (nil, 0) }
            let start = blockStartIndex(runIndex: runIndex)
            let end = blockEndIndex(runIndex: runIndex)
            let combinedGoal: TimeInterval = engine.template.segments[start...end]
                .compactMap { $0.goalDurationSeconds }
                .reduce(0, +)
            guard combinedGoal > 0 else { return (nil, 0) }
            var actualBase: TimeInterval = 0
            for i in start..<currentIndex {
                if let rec = engine.records.first(where: { $0.index == i }) {
                    actualBase += rec.activeDuration
                }
            }
            return (combinedGoal, actualBase)
        }
    }

    /// 전체 운동 raw goal + 현재 세그먼트까지 누적 goal.
    func resolveTotalGoalRaw(currentIndex: Int) -> (totalGoal: TimeInterval?, goalSoFar: TimeInterval) {
        let wholeGoal: TimeInterval = engine.template.segments
            .compactMap { $0.goalDurationSeconds }
            .reduce(0, +)
        guard wholeGoal > 0 else { return (nil, 0) }
        let upTo: Int = {
            if let owning = owningRunIndex(for: currentIndex) { return max(currentIndex, owning) }
            return currentIndex
        }()
        let goalSoFar: TimeInterval = engine.template.segments[0...upTo]
            .compactMap { $0.goalDurationSeconds }
            .reduce(0, +)
        return (wholeGoal, goalSoFar)
    }

    /// 블록 단위 delta: 블록0 = Run+RoxEntry, 블록1~7 = RoxExit+Run+RoxEntry.
    /// 블록의 합산 goal 은 Run 세그먼트에 저장되어 있고 Rox=0.
    /// - Run/Rox: 블록 내 완료 세그먼트 합 + 현재 경과 vs 블록 Run 의 합산 goal
    /// - Station: 자체 goal vs segElapsed
    private func resolveGoalAndDelta(
        currentIndex: Int, segElapsed: TimeInterval
    ) -> (goalText: String, deltaText: String, isOver: Bool) {
        let current = engine.template.segments[currentIndex]

        switch current.type {
        case .station:
            guard let goal = current.goalDurationSeconds, goal > 0 else {
                return ("—", "—", false)
            }
            let delta = segElapsed - goal
            return (DurationFormatter.ms(goal), DurationFormatter.signedMs(delta), delta >= 0)

        case .run, .roxZone:
            guard let runIndex = owningRunIndex(for: currentIndex) else {
                return ("—", "—", false)
            }
            let start = blockStartIndex(runIndex: runIndex)
            let end = blockEndIndex(runIndex: runIndex)
            // 블록 내 모든 세그먼트 goal 합산 (페이스 플래너 후: Run 에 합산·Rox=0, 기본 프리셋: Run+Rox 각각 goal).
            let combinedGoal: TimeInterval = engine.template.segments[start...end]
                .compactMap { $0.goalDurationSeconds }
                .reduce(0, +)
            guard combinedGoal > 0 else { return ("—", "—", false) }

            var blockActual: TimeInterval = 0
            for i in start..<currentIndex {
                if let rec = engine.records.first(where: { $0.index == i }) {
                    blockActual += rec.activeDuration
                }
            }
            blockActual += segElapsed
            let delta = blockActual - combinedGoal
            return (DurationFormatter.ms(combinedGoal), DurationFormatter.signedMs(delta), delta >= 0)
        }
    }

    /// Cumulative delta vs whole-workout goal.
    /// goalText: total workout goal (h:mm:ss).
    /// deltaText: totalElapsed − cumulativeGoalThroughCurrentSegment (inclusive).
    /// RoxExit 중에는 소유 Run(뒤따라오는) 의 goal 도 포함해야 블록 예산이 반영됨.
    private func resolveTotalGoalAndDelta(
        totalElapsed: TimeInterval, currentIndex: Int
    ) -> (goalText: String, deltaText: String, isOver: Bool) {
        let wholeGoal: TimeInterval = engine.template.segments
            .compactMap { $0.goalDurationSeconds }
            .reduce(0, +)
        guard wholeGoal > 0 else { return ("—", "—", false) }

        let upTo: Int = {
            if let owning = owningRunIndex(for: currentIndex) { return max(currentIndex, owning) }
            return currentIndex
        }()
        let goalSoFar: TimeInterval = engine.template.segments[0...upTo]
            .compactMap { $0.goalDurationSeconds }
            .reduce(0, +)
        let delta = totalElapsed - goalSoFar
        return (DurationFormatter.hms(wholeGoal), DurationFormatter.signedMs(delta), delta >= 0)
    }

    /// 현재 Run/Rox 세그먼트가 속한 블록의 Run 인덱스.
    /// - Run: 자기 자신
    /// - RoxEntry (다음이 Station): 바로 앞 Run
    /// - RoxExit (앞이 Station): 바로 뒤 Run
    private func owningRunIndex(for index: Int) -> Int? {
        let segs = engine.template.segments
        switch segs[index].type {
        case .run:
            return index
        case .roxZone:
            if index >= 1, segs[index - 1].type == .station {
                for i in (index + 1)..<segs.count {
                    if segs[i].type == .run { return i }
                    if segs[i].type == .station { return nil }
                }
                return nil
            } else {
                for i in stride(from: index - 1, through: 0, by: -1) {
                    if segs[i].type == .run { return i }
                    if segs[i].type == .station { return nil }
                }
                return nil
            }
        case .station:
            return nil
        }
    }

    /// 블록의 첫 세그먼트 인덱스 (RoxExit 가 있으면 그 인덱스, 없으면 Run 인덱스).
    private func blockStartIndex(runIndex: Int) -> Int {
        let segs = engine.template.segments
        if runIndex >= 1, segs[runIndex - 1].type == .roxZone {
            return runIndex - 1
        }
        return runIndex
    }

    /// 블록의 마지막 세그먼트 인덱스 (RoxEntry 가 있으면 그 인덱스, 없으면 Run 인덱스).
    private func blockEndIndex(runIndex: Int) -> Int {
        let segs = engine.template.segments
        let next = runIndex + 1
        if next < segs.count, segs[next].type == .roxZone {
            return next
        }
        return runIndex
    }

    private func countOfType(_ type: SegmentType, upTo end: Int) -> Int {
        engine.template.segments[..<end].filter { $0.type == type }.count
    }

    private func displayTitle(for segment: WorkoutSegment, at index: Int) -> String {
        switch segment.type {
        case .run:
            return "RUNNING \(countOfType(.run, upTo: index + 1))"
        case .roxZone:
            return "ROX ZONE"
        case .station:
            return segment.stationKind?.displayName ?? "Station"
        }
    }

    private func nextDisplayTitle(after currentIndex: Int, currentType: SegmentType) -> String? {
        if engine.template.usesRoxZone {
            guard currentType == .roxZone else { return nil }
        } else {
            guard currentType == .run else { return nil }
        }
        let nextIndex = currentIndex + 1
        guard engine.template.segments.indices.contains(nextIndex) else { return nil }
        let nextSegment = engine.template.segments[nextIndex]
        return displayTitle(for: nextSegment, at: nextIndex)
    }

    // MARK: - Timer

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Checkpoint (앱 강제 종료/크래시 대비)

    private func startCheckpointTimer() {
        checkpointTimer = Timer.scheduledTimer(
            withTimeInterval: Self.checkpointInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.writeCheckpoint() }
        }
    }

    private func stopCheckpointTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
    }

    /// 지금까지의 진행 상황을 "지금 끝났다고 가정한" 잠정 결과로 저장한다.
    func writeCheckpoint(at now: Date = Date()) {
        guard let provisional = makeProvisionalWorkout(at: now) else { return }
        checkpointStore.save(workout: provisional, at: now)
    }

    /// 진행 중인 세그먼트까지 포함한 잠정 `CompletedWorkout`.
    /// 엔진이 idle/finished 이거나 기록이 하나도 없으면 nil.
    func makeProvisionalWorkout(at now: Date) -> CompletedWorkout? {
        guard !engine.isFinished else { return nil }

        var records = engine.records
        if let index = engine.currentSegmentIndex,
           engine.template.segments.indices.contains(index) {
            let segment = engine.template.segments[index]
            let segElapsed = engine.segmentElapsed(at: now)
            records.append(
                SegmentRecord(
                    segmentId: segment.id,
                    index: index,
                    type: segment.type,
                    startedAt: now.addingTimeInterval(-segElapsed),
                    endedAt: now,
                    measurements: engine.liveMeasurementsSnapshot,
                    stationDisplayName: segment.stationKind?.displayName,
                    plannedDistanceMeters: segment.distanceMeters,
                    goalDurationSeconds: segment.goalDurationSeconds
                )
            )
        }
        guard !records.isEmpty else { return nil }

        // paused 상태에서는 workoutStartedAt 이 상태에 없으므로 총 경과로 역산한다.
        let startedAt = now.addingTimeInterval(-engine.totalElapsed(at: now))
        return CompletedWorkout(
            id: workoutId,
            templateName: engine.template.name,
            division: engine.template.division,
            startedAt: startedAt,
            finishedAt: now,
            segments: records
        )
    }

    // MARK: - Finish

    private func finishAndSave() async {
        cleanup()
        do {
            let completed = try engine.makeCompletedWorkout()
            try persistence.saveCompletedWorkout(completed)
            // 정상 저장이 끝난 뒤에만 체크포인트를 지운다.
            checkpointStore.clear()
            try? syncCoordinator?.sendCompletedWorkout(completed)
            syncCoordinator?.sendWorkoutFinished(origin: .phone)
            isFinished = true
            finishHandler?(completed)
            // 건강 앱 저장은 요약 화면 표시 뒤에 — 실패하든 느리든 사용자 흐름을 막지 않는다.
            await saveToHealthIfPossible(completed)
        } catch {
            errorHandler?(error)
        }
    }

    /// 완료된 운동을 건강 앱에 남긴다.
    /// 이 뷰모델은 **폰에서 시작한 운동**만 다루므로 `origin: .phone` 으로 저장한다.
    /// 워치에서 기록돼 동기화로 들어온 운동은 이 경로를 타지 않는다(워치가 이미 저장했으므로 중복 방지).
    private func saveToHealthIfPossible(_ workout: CompletedWorkout) async {
        guard let healthWorkoutSaver, await resolveHealthAuthorization() else { return }

        let environment = WorkoutEnvironmentClassifier.classify(
            workout: workout,
            isLocationTrackingActive: didTrackLocation
        )
        guard let export = HealthWorkoutExport(
            workout: workout,
            origin: .phone,
            environment: environment
        ) else {
            Self.logger.notice("길이가 0 인 운동이라 건강 앱 저장을 건너뜁니다.")
            return
        }

        do {
            try await healthWorkoutSaver.save(export)
        } catch {
            Self.logger.error("건강 앱 저장 실패: \(String(describing: error), privacy: .public)")
        }
    }

    private func cleanup() {
        stopDisplayTimer()
        stopCheckpointTimer()
        endLiveActivity()
        locationTask?.cancel()
        heartRateTask?.cancel()
        locationTask = nil
        heartRateTask = nil
        isLocationActive = false
        locationStream.stop()
        heartRateStream.stop()
        syncCoordinator?.onReceiveCommand = nil
        syncCoordinator?.onHeartRateRelayReceived = nil
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(
            templateName: engine.template.name,
            totalSegments: engine.template.segments.count
        )
        let content = makeActivityContent()
        liveActivity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let content = makeActivityContent()
        Task { await liveActivity.update(content) }
    }

    /// staleDate 를 매번 "현재 + 수 분"으로 갱신한다.
    /// 앱이 죽어 업데이트가 끊기면 시스템이 stale 로 표시해 주므로,
    /// 멈춘 시계가 잠금화면에 계속 살아 있는 것처럼 보이지 않는다.
    private func makeActivityContent() -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        ActivityContent(
            state: makeActivityState(),
            staleDate: Date().addingTimeInterval(Self.activityStaleInterval)
        )
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let state = makeActivityState()
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await liveActivity.end(content, dismissalPolicy: .immediate) }
        self.liveActivity = nil
    }

    /// 앱 시작 시 이전 세션에서 남은 Live Activity 정리
    public static func endStaleActivities() {
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func makeActivityState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            segmentLabel: segmentLabel,
            segmentSubLabel: segmentSubLabel,
            segmentElapsed: segmentElapsedText,
            totalElapsed: totalElapsedText,
            heartRate: heartRateText,
            accentKind: { switch accentKind { case .run: "run"; case .roxZone: "roxZone"; case .station: "station" } }(),
            isPaused: isPaused,
            isLastSegment: isLastSegment,
            nextSegmentLabel: nextTargetLabel,
            nextSegmentGoal: nextTargetGoalText
        )
    }
}
