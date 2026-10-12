//
//  VoiceGuide.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import AVFoundation
import HyroxCore

/// 운동 중 구간이 바뀔 때 기록과 목표 대비 차이를 말로 알려 준다.
///
/// 음악을 끊지 않는다 — 말하는 동안만 다른 소리를 줄였다가 되돌린다.
@MainActor
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate {

    static let enabledKey = "voiceGuide.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private typealias L = HyroxSimStrings.Localizable.Voice

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 구간 전환을 알린다. 설정이 꺼져 있거나 구독자가 아니면 아무것도 하지 않는다.
    func announce(_ cue: VoiceCue) {
        guard Self.isEnabled, PremiumAccess.gate().allows(.voiceGuide) else { return }
        speak(Self.text(for: cue))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - 문장

    /// "SkiErg 4분 12초. 목표보다 8초 빠름. 다음, 러닝."
    static func text(for cue: VoiceCue) -> String {
        var parts: [String] = []
        // 록스존은 기록을 읽지 않고 다음 구간만 알린다.
        if cue.finishedType != .roxZone {
            parts.append(L.finished(name(type: cue.finishedType, station: cue.finishedStation), spoken(cue.finishedSeconds)))
            switch cue.pace {
            case .ahead(let seconds): parts.append(L.ahead(spoken(seconds)))
            case .behind(let seconds): parts.append(L.behind(spoken(seconds)))
            case .onGoal: parts.append(L.onGoal)
            case nil: break
            }
        }
        if let nextType = cue.nextType {
            parts.append(L.next(name(type: nextType, station: cue.nextStation)))
        } else {
            parts.append(L.done)
        }
        return parts.joined(separator: " ")
    }

    private static func name(type: SegmentType, station: StationKind?) -> String {
        switch type {
        case .run: return L.run
        case .roxZone: return L.roxZone
        case .station: return station?.displayName ?? L.station
        }
    }

    /// 초 → "4분 12초" / "4 minutes 12 seconds" (현재 언어).
    static func spoken(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }

    // MARK: - 말하기

    private func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.releaseSessionIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.releaseSessionIfIdle() }
    }

    /// 다 말했으면 줄여 놓은 음악을 원래 크기로 되돌린다.
    private func releaseSessionIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
