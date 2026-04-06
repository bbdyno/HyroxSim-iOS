import SwiftUI
import HyroxKit

struct ConfirmStartView: View {
    let template: WorkoutTemplate
    let persistence: PersistenceController
    @State private var showActive = false

    var body: some View {
        VStack(spacing: 12) {
            Text(template.division?.displayName ?? template.name)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("\(template.segments.filter { $0.type == .station }.count) stations · ~\(Int(template.estimatedDurationSeconds / 60)) min")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                showActive = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .navigationDestination(isPresented: $showActive) {
            ActiveWorkoutView(template: template, persistence: persistence)
                .navigationBarBackButtonHidden(true)
        }
    }
}
