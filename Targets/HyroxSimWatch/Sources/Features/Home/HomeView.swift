//
//  HomeView.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import SwiftUI
import HyroxCore
import HyroxPersistenceApple

/// watchOS 홈 화면 — 블랙+옐로우 테마.
/// NavigationPath를 관리하여 운동 완료 시 홈으로 직접 복귀.
struct HomeView: View {
    let persistence: PersistenceController
    let syncCoordinator: (any SyncCoordinator)?
    @State private var customTemplates: [WorkoutTemplate] = []
    @State private var navigationPath = NavigationPath()
    @State private var overrideRefresh = 0
    private let goalOverrideStore = TemplateGoalOverrideStore()

    private let accent = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 8) {
                    if !customTemplates.isEmpty {
                        sectionHeader("MY WORKOUTS")
                        ForEach(customTemplates) { t in
                            NavigationLink(value: t) {
                                presetCard(t)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    sectionHeader("HYROX PRESETS")
                    ForEach(HyroxPresets.all) { template in
                        let resolved = goalOverrideStore.resolvedTemplate(from: template)
                        NavigationLink(value: resolved) {
                            presetCard(resolved)
                        }
                        .buttonStyle(.plain)
                        .id("\(template.id)-\(overrideRefresh)")
                    }

                    // 히스토리 진입
                    sectionHeader("")
                    NavigationLink {
                        WatchHistoryView(persistence: persistence)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(accent)
                            Text("History")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.3))
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
            }
            .background(Color.black)
            .navigationTitle("HYROX")
            .navigationDestination(for: WorkoutTemplate.self) { template in
                ConfirmStartView(template: template, persistence: persistence, syncCoordinator: syncCoordinator, navigationPath: $navigationPath)
            }
            .onAppear {
                customTemplates = (try? persistence.fetchAllTemplates()) ?? []
            }
            .onReceive(NotificationCenter.default.publisher(for: .hyroxTemplateGoalOverrideUpdated)) { _ in
                overrideRefresh &+= 1
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(accent)
            Spacer()
        }
        .padding(.top, 6)
    }

    private func presetCard(_ template: WorkoutTemplate) -> some View {
        VStack(spacing: 0) {
            HStack {
                if template.isBuiltIn {
                    Text(badgeText(template))
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(accent)
                        .cornerRadius(3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.division?.shortName ?? template.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("\(template.segments.filter { $0.type == .station }.count) stations")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.vertical, 10)

            Divider()
                .overlay(Color.white.opacity(0.08))
        }
    }

    private func badgeText(_ template: WorkoutTemplate) -> String {
        guard let d = template.division else { return "—" }
        switch d {
        case .menProSingle, .menProDouble, .womenProSingle, .womenProDouble: return "PRO"
        case .mixedDouble: return "MIX"
        default: return "OPEN"
        }
    }
}
