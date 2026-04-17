//
//  WatchActiveWorkoutModel.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxCore
import HyroxPersistenceApple

/// Watch-specific workout model. Similar to iOS ActiveWorkoutViewModel but uses
/// WatchWorkoutSession (HKWorkoutSession host) for heart rate and CoreLocationAdapter for GPS.
/// Code overlap with iOS is intentional — shared refresh logic could be extracted to HyroxKit later.
@Observable
@MainActor
final class WatchActiveWorkoutModel {
    // MARK: - UI State
    private(set) var segmentLabel: String = ""
    private(set) var segmentSubLabel: String?
    private(set) var currentDisplayTitle: String = ""
    private(set) var nextDisplayTitle: String?
    private(set) var segmentElapsedText: String = "00:00"
    private(set) var totalElapsedText: String = "0:00:00"
    private(set) var paceText: String = "—"
    private(set) var distanceText: String = "0 m"
    private(set) var heartRateText: String = "—"
    private(set) var heartRateZone: HeartRateZone?
    private(set) var goalText: String = "—"
    private(set) var goalDeltaText: String = "—"
    private(set) var isOverGoal: Bool = false
    private(set) var totalGoalText: String = "—"
    private(set) var totalDeltaText: String = "—"
    private(set) var isOverTotalGoal: Bool = false
    private(set) var stationNameText: String?
    private(set) var stationTargetText: String?
    private(set) var accentKind: AccentKind = .run
    private(set) var isPaused: Bool = false
    private(set) var isFinished: Bool = false
    private(set) var isLastSegment: Bool = false
    private(set) var gpsStrong: Bool = false  // simple on/off for watch (compact)
    private(set) var gpsActive: Bool = true

    enum AccentKind { case run, roxZone, station }

    private var lastKnownBpm: Int?

    // MARK: - Dependencies
    private let engine: WorkoutEngine
    private let workoutSession: WatchWorkoutSession
    private let locationAdapter: CoreLocationAdapter
    private let persistence: PersistenceController
    private let syncCoordinator: (any SyncCoordinator)?
    private let maxHeartRate: Int

    private var displayTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?
    private var heartRateTask: Task<Void, Never>?
    private var sensorStartupTask: Task<Void, Never>?
    private var mirroringTask: Task<Void, Never>?
    private var segmentStartHKDistance: Double = 0
    private var isMirroringActive = false
    private var didStart = false
    private var lastRemoteCommand: (command: WorkoutCommand, at: Date)?
    private var uiTestAutoEndDeadline: Date?
    private var alertedGoalSegmentId: UUID?

    var finishHandler: ((CompletedWorkout) -> Void)?
    var errorHandler: ((Error) -> Void)?
    var goalAlertHandler: (() -> Void)?

    init(
        template: WorkoutTemplate,
        persistence: PersistenceController,
        syncCoordinator: (any SyncCoordinator)? = nil,
        maxHeartRate: Int = 190
    ) {
        self.engine = WorkoutEngine(template: template)
        self.workoutSession = WatchWorkoutSession()
        self.locationAdapter = CoreLocationAdapter()
        self.persistence = persistence
        self.syncCoordinator = syncCoordinator
        self.maxHeartRate = maxHeartRate
    }

    /// TimelineView에서 매 틱마다 호출 — UI 갱신용
    @discardableResult
    func triggerRefresh() -> Bool {
        refresh()
        return true
    }

    // MARK: - Lifecycle

    func start() async {
        guard !didStart else { return }
        didStart = true
        do {
            try engine.start(at: Date())
            if uiTestAutoEndDeadline == nil,
               ProcessInfo.processInfo.arguments.contains("UITestAutoEndWatchWorkout") {
                uiTestAutoEndDeadline = Date().addingTimeInterval(6)
            }
            setupRemoteInputs()
            await sendWorkoutStarted()
            startDisplayTimer()
            refresh()
            startSensors()
        } catch {
            didStart = false
            errorHandler?(error)
        }
    }

    /// 폰에서 보낸 원격 명령 처리
    private func handleRemoteCommand(_ cmd: WorkoutCommand) {
        switch cmd {
        case .advance: advance()
        case .pause: if !isPaused { togglePause() }
        case .resume: if isPaused { togglePause() }
        case .end: endWorkout()
        }
    }

    private func handleRemoteCommandIfNeeded(_ cmd: WorkoutCommand) {
        let now = Date()
        if let lastRemoteCommand,
           lastRemoteCommand.command == cmd,
           now.timeIntervalSince(lastRemoteCommand.at) < 1 {
            return
        }
        lastRemoteCommand = (cmd, now)
        handleRemoteCommand(cmd)
    }

    func advance() {
        do {
            try engine.advance(at: Date())
            segmentStartHKDistance = workoutSession.cumulativeDistanceMeters
            refresh()
            if engine.isFinished {
                Task { await finishAndSave() }
            }
        } catch { errorHandler?(error) }
    }

    func togglePause() {
        do {
            if isPaused {
                workoutSession.resume()
                try engine.resume(at: Date())
            } else {
                workoutSession.pause()
                try engine.pause(at: Date())
            }
            isPaused.toggle()
            refresh()
        } catch { errorHandler?(error) }
    }

    func endWorkout() {
        do {
            try engine.finish(at: Date())
            Task { await finishAndSave() }
        } catch { errorHandler?(error) }
    }

    // MARK: - Refresh

    private func refresh() {
        let now = Date()
        if let deadline = uiTestAutoEndDeadline, now >= deadline, !isFinished {
            uiTestAutoEndDeadline = nil
            endWorkout()
            return
        }
        let totalElapsed = engine.totalElapsed(at: now)
        segmentElapsedText = DurationFormatter.ms(engine.segmentElapsed(at: now))
        totalElapsedText = DurationFormatter.hms(totalElapsed)

        guard let current = engine.currentSegment, let index = engine.currentSegmentIndex else {
            isFinished = engine.isFinished
            currentDisplayTitle = ""
            nextDisplayTitle = nil
            goalText = "—"
            goalDeltaText = "—"
            isOverGoal = false
            totalGoalText = "—"
            totalDeltaText = "—"
            isOverTotalGoal = false
            return
        }

        let live = engine.liveMeasurementsSnapshot
        let segElapsed = engine.segmentElapsed(at: now)
        currentDisplayTitle = displayTitle(for: current, at: index)
        nextDisplayTitle = nextDisplayTitle(after: index, currentType: current.type)

        // Run/Rox: Run 세그먼트에 Run+Rox 합산 goal 이 저장되어 있고 Rox goal=0.
        // Rox 진행 중엔 직전 Run 실측 + Rox 경과 vs 합산 goal 로 delta 계산.
        let goalInfo = resolveGoalAndDelta(currentIndex: index, segElapsed: segElapsed)
        goalText = goalInfo.goalText
        goalDeltaText = goalInfo.deltaText
        isOverGoal = goalInfo.isOver
        if isOverGoal, goalText != "—", alertedGoalSegmentId != current.id {
            alertedGoalSegmentId = current.id
            goalAlertHandler?()
        }

        // 누적 delta: 완료 세그먼트 + 현재 세그먼트 목표 합산 vs totalElapsed.
        // Rox는 goal=0(Run에 합산되어 있음)이라 단순 합산으로도 자연스럽게 동작.
        let wholeGoal: TimeInterval = engine.template.segments
            .compactMap { $0.goalDurationSeconds }
            .reduce(0, +)
        if wholeGoal > 0 {
            let goalSoFar: TimeInterval = engine.template.segments[0...index]
                .compactMap { $0.goalDurationSeconds }
                .reduce(0, +)
            let delta = totalElapsed - goalSoFar
            totalGoalText = DurationFormatter.hms(wholeGoal)
            totalDeltaText = DurationFormatter.signedMs(delta)
            isOverTotalGoal = delta >= 0
        } else {
            totalGoalText = "—"
            totalDeltaText = "—"
            isOverTotalGoal = false
        }

        // GPS 거리 부족 시 HKWorkoutBuilder 거리로 폴백
        let gpsPace = live.averagePaceSecondsPerKm(activeDuration: segElapsed)
        let hkSegmentDist = workoutSession.cumulativeDistanceMeters - segmentStartHKDistance
        let effectivePace: Double? = {
            if let gps = gpsPace { return gps }
            let km = hkSegmentDist / 1000.0
            guard km > 0.001 else { return nil }
            return segElapsed / km
        }()
        let effectiveDistance = live.distanceMeters > 1 ? live.distanceMeters : hkSegmentDist

        switch current.type {
        case .run:
            let runIdx = engine.template.segments[..<(index + 1)].filter { $0.type == .run }.count
            let runTotal = engine.template.segments.filter { $0.type == .run }.count
            segmentLabel = "RUN \(runIdx) / \(runTotal)"
            segmentSubLabel = nil
            accentKind = .run
            distanceText = DistanceFormatter.short(effectiveDistance)
            paceText = DurationFormatter.pace(effectivePace)
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
            distanceText = DistanceFormatter.short(effectiveDistance)
            paceText = DurationFormatter.pace(effectivePace)
            stationNameText = nil
            stationTargetText = nil

        case .station:
            let stIdx = engine.template.segments[..<(index + 1)].filter { $0.type == .station }.count
            let stTotal = engine.template.segments.filter { $0.type == .station }.count
            let name = current.stationKind?.displayName ?? "Station"
            segmentLabel = "STATION \(stIdx) / \(stTotal)"
            segmentSubLabel = name
            accentKind = .station
            stationNameText = current.stationKind?.displayName
            stationTargetText = current.stationTarget?.formatted
            paceText = "—"
            distanceText = "—"
        }

        // HR persists across segments
        if let lastHR = live.heartRateSamples.last { lastKnownBpm = lastHR.bpm }
        if let bpm = lastKnownBpm {
            heartRateText = "\(bpm)"
            heartRateZone = HeartRateZone.zone(forHeartRate: bpm, maxHeartRate: maxHeartRate)
        } else {
            heartRateText = "—"
            heartRateZone = nil
        }

        // GPS status (simple for watch)
        gpsActive = current.type != .station
        if gpsActive, let lastLoc = live.locationSamples.last {
            gpsStrong = lastLoc.horizontalAccuracy < 15
        }

        isFinished = engine.isFinished
        isLastSegment = engine.isLastSegment

        // 폰에 실시간 상태 전송
        broadcastLiveState()
    }

    private func broadcastLiveState() {
        let accentRaw: String = switch accentKind {
        case .run: "run"
        case .roxZone: "roxZone"
        case .station: "station"
        }
        let state = LiveWorkoutState(
            segmentLabel: segmentLabel, segmentSubLabel: segmentSubLabel,
            currentDisplayTitle: currentDisplayTitle, nextDisplayTitle: nextDisplayTitle,
            segmentElapsedText: segmentElapsedText, totalElapsedText: totalElapsedText,
            paceText: paceText, distanceText: distanceText,
            heartRateText: heartRateText, heartRateZoneRaw: heartRateZone?.rawValue,
            goalText: goalText, goalDeltaText: goalDeltaText, isOverGoal: isOverGoal,
            stationNameText: stationNameText, stationTargetText: stationTargetText,
            accentKindRaw: accentRaw,
            isPaused: isPaused, isFinished: isFinished, isLastSegment: isLastSegment,
            gpsStrong: gpsStrong, gpsActive: gpsActive,
            templateName: engine.template.name,
            totalSegmentCount: engine.template.segments.count,
            currentSegmentIndex: engine.currentSegmentIndex ?? 0,
            origin: .watch
        )
        sendPacket(.liveState(state))
    }

    /// UI 갱신은 TimelineView가 담당. 이 타이머는 백그라운드 브로드캐스트 전용.
    /// TimelineView가 보이지 않을 때도 폰에 실시간 전송을 유지하기 위해 필요.
    private func startDisplayTimer() {
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self?.broadcastLiveState() }
            }
        }
    }

    private func finishAndSave() async {
        syncCoordinator?.sendWorkoutFinished(origin: .watch)
        if isMirroringActive {
            Task { [workoutSession] in
                do {
                    let data = try LiveSyncPacketCoder.encode(.workoutFinished(origin: .watch))
                    try await workoutSession.sendToRemoteWorkoutSession(data: data)
                } catch {
                    print("[WatchWorkout] Failed to send mirrored workoutFinished: \(error)")
                }
            }
        }
        cleanup()
        workoutSession.stop()
        do {
            let completed = try engine.makeCompletedWorkout()
            try persistence.saveCompletedWorkout(completed)
            try? syncCoordinator?.sendCompletedWorkout(completed)
            isFinished = true
            finishHandler?(completed)
        } catch {
            errorHandler?(error)
        }
    }

    private func cleanup() {
        displayTask?.cancel()
        displayTask = nil
        sensorStartupTask?.cancel()
        sensorStartupTask = nil
        locationTask?.cancel()
        heartRateTask?.cancel()
        mirroringTask?.cancel()
        mirroringTask = nil
        uiTestAutoEndDeadline = nil
        locationAdapter.stop()
        workoutSession.onRemoteDataReceived = nil
        workoutSession.onRemoteDisconnect = nil
        syncCoordinator?.onReceiveCommand = nil
        isMirroringActive = false
    }
}

// MARK: - Remote Sync

private extension WatchActiveWorkoutModel {

    func startSensors() {
        sensorStartupTask?.cancel()
        sensorStartupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await workoutSession.start()
                heartRateTask = engine.attachHeartRateStream(workoutSession)
                segmentStartHKDistance = workoutSession.cumulativeDistanceMeters
                startMirroring()

                try await locationAdapter.start()
                locationTask = engine.attachLocationStream(locationAdapter)
            } catch {
                guard !Task.isCancelled else { return }
                errorHandler?(error)
            }
        }
    }

    func startMirroring() {
        mirroringTask?.cancel()
        mirroringTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await workoutSession.startMirroringToCompanionDevice()
                guard !Task.isCancelled else { return }
                isMirroringActive = true
                await sendPacketNow(.workoutStarted(template: engine.template, origin: .watch))
                broadcastLiveState()
            } catch {
                guard !Task.isCancelled else { return }
                isMirroringActive = false
                print("[WatchWorkout] Failed to start mirroring: \(error)")
            }
        }
    }

    func setupRemoteInputs() {
        workoutSession.onRemoteDataReceived = { [weak self] payloads in
            self?.handleMirroredPayloads(payloads)
        }
        workoutSession.onRemoteDisconnect = { [weak self] error in
            self?.isMirroringActive = false
            if let error {
                print("[WatchWorkout] Mirroring disconnected: \(error)")
            }
        }
        syncCoordinator?.onReceiveCommand = { [weak self] command in
            self?.handleRemoteCommandIfNeeded(command)
        }
    }

    func handleMirroredPayloads(_ payloads: [Data]) {
        for payload in payloads {
            guard let packet = try? LiveSyncPacketCoder.decode(payload) else {
                print("[WatchWorkout] Failed to decode mirrored payload")
                continue
            }
            if case .command(let command) = packet {
                handleRemoteCommandIfNeeded(command)
            }
        }
    }

    func sendWorkoutStarted() async {
        let packet = LiveSyncPacket.workoutStarted(template: engine.template, origin: .watch)
        await sendPacketNow(packet)
    }

    func sendPacket(_ packet: LiveSyncPacket) {
        Task { await self.sendPacketNow(packet) }
    }

    func sendPacketNow(_ packet: LiveSyncPacket) async {
        if isMirroringActive {
            do {
                let data = try LiveSyncPacketCoder.encode(packet)
                try await workoutSession.sendToRemoteWorkoutSession(data: data)
                return
            } catch {
                print("[WatchWorkout] Failed to send mirrored payload: \(error)")
            }
        }

        guard let syncCoordinator else { return }
        switch packet {
        case .workoutStarted(let template, let origin):
            syncCoordinator.sendWorkoutStarted(template: template, origin: origin)
        case .liveState(let state):
            syncCoordinator.sendLiveState(state)
        case .workoutFinished(let origin):
            syncCoordinator.sendWorkoutFinished(origin: origin)
        case .command:
            break
        case .heartRateRelay(let relay):
            syncCoordinator.sendHeartRateRelay(relay)
        }
    }

    /// Run/Rox 합산 goal 기준 SEG delta. iOS `ActiveWorkoutViewModel.resolveGoalAndDelta` 와 동일 로직.
    /// - Run: 자체 goal(Run+Rox 합산) vs segElapsed
    /// - Rox: 직전 Run 실측 + Rox 경과 vs Run 세그먼트의 합산 goal
    /// - Station: 자체 goal vs segElapsed
    func resolveGoalAndDelta(
        currentIndex: Int, segElapsed: TimeInterval
    ) -> (goalText: String, deltaText: String, isOver: Bool) {
        let current = engine.template.segments[currentIndex]

        switch current.type {
        case .run:
            guard let goal = current.goalDurationSeconds, goal > 0 else {
                return ("—", "—", false)
            }
            let delta = segElapsed - goal
            return (DurationFormatter.ms(goal), DurationFormatter.signedMs(delta), delta >= 0)

        case .roxZone:
            if let prevRecord = findPrecedingRunRecord(before: currentIndex) {
                let combinedGoal = engine.template.segments[prevRecord.index].goalDurationSeconds ?? 0
                guard combinedGoal > 0 else { return ("—", "—", false) }
                let combinedActual = prevRecord.activeDuration + segElapsed
                let delta = combinedActual - combinedGoal
                return (DurationFormatter.ms(combinedGoal), DurationFormatter.signedMs(delta), delta >= 0)
            }
            return ("—", "—", false)

        case .station:
            guard let goal = current.goalDurationSeconds, goal > 0 else {
                return ("—", "—", false)
            }
            let delta = segElapsed - goal
            return (DurationFormatter.ms(goal), DurationFormatter.signedMs(delta), delta >= 0)
        }
    }

    func findPrecedingRunRecord(before index: Int) -> SegmentRecord? {
        for record in engine.records.reversed() {
            if record.type == .run && record.index < index { return record }
        }
        return nil
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
            // Rox Zone ON: roxZone 전환 구간에서만 다음 운동 표시
            guard currentType == .roxZone else { return nil }
        } else {
            // Rox Zone OFF: run 구간에서만 다음 운동 표시
            guard currentType == .run else { return nil }
        }
        let nextIndex = currentIndex + 1
        guard engine.template.segments.indices.contains(nextIndex) else { return nil }
        let nextSegment = engine.template.segments[nextIndex]
        return displayTitle(for: nextSegment, at: nextIndex)
    }
}
