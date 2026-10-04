import SwiftUI

struct QuickStartOnboardingView: View {
    @Binding var useHealthSync: Bool
    @Binding var enableReminders: Bool

    let onRequestHealthKit: () async -> Void
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Start")
                .font(.largeTitle.bold())

            Text("Step \(step + 1) of 3")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case 0:
                    stepOnePrivacy
                case 1:
                    stepTwoHealthKit
                default:
                    stepThreePreferences
                }
            }

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0)

                Spacer()

                Button(step == 2 ? "Finish" : "Next") {
                    if step == 2 {
                        onComplete()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var stepOnePrivacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy first")
                .font(.title3.weight(.semibold))
            Text("Your entries are stored locally first. You control Health sync in Settings at any time.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepTwoHealthKit: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health integration")
                .font(.title3.weight(.semibold))
            Text("The app reads latest calorie data from Apple Health before syncing, then writes updates.")
                .foregroundStyle(.secondary)
            Button("Allow Health Access") {
                Task {
                    await onRequestHealthKit()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepThreePreferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync preferences")
                .font(.title3.weight(.semibold))
            Toggle("Enable Health sync", isOn: $useHealthSync)
            Toggle("Enable reminders", isOn: $enableReminders)
            Text("You can change these any time later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
