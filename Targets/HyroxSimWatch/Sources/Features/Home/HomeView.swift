import SwiftUI
import HyroxKit

struct HomeView: View {
    let persistence: PersistenceController
    @State private var customTemplates: [WorkoutTemplate] = []

    var body: some View {
        NavigationStack {
            List {
                if !customTemplates.isEmpty {
                    Section("My Workouts") {
                        ForEach(customTemplates) { t in
                            NavigationLink(value: t) {
                                PresetRow(template: t)
                            }
                        }
                    }
                }
                Section("HYROX Presets") {
                    ForEach(HyroxPresets.all) { template in
                        NavigationLink(value: template) {
                            PresetRow(template: template)
                        }
                    }
                }
            }
            .navigationTitle("HyroxSim")
            .navigationDestination(for: WorkoutTemplate.self) { template in
                ConfirmStartView(template: template, persistence: persistence)
            }
            .onAppear {
                customTemplates = (try? persistence.fetchAllTemplates()) ?? []
            }
        }
    }
}

struct PresetRow: View {
    let template: WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.division?.shortName ?? template.name)
                .font(.headline)
            Text("\(template.segments.filter { $0.type == .station }.count) stations")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
