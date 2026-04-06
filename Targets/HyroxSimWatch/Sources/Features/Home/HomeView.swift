import SwiftUI
import HyroxKit

struct HomeView: View {
    let persistence: PersistenceController

    var body: some View {
        NavigationStack {
            List {
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
