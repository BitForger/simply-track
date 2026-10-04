import SwiftUI

struct QuickStartOnboardingView: View {
    @Binding var useHealthSync: Bool
    @Binding var enableReminders: Bool

    let onRequestHealthKit: () async -> Bool
    let onComplete: () -> Void

    @State private var step = 0
    @State private var isRequestingHealthKit = false
    @State private var healthKitRequestMessage: String?

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

            if let healthKitRequestMessage {
                Text(healthKitRequestMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0 || isRequestingHealthKit)

                Spacer()

                Button(step == 2 ? "Finish" : "Next") {
                    if step == 2 {
                        onComplete()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequestingHealthKit)
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
            Button(isRequestingHealthKit ? "Requesting…" : "Allow Health Access") {
                Task {
                    isRequestingHealthKit = true
                    defer { isRequestingHealthKit = false }

                    let granted = await onRequestHealthKit()
                    useHealthSync = granted
                    healthKitRequestMessage = granted
                        ? "Health access granted. You can continue to the next step."
                        : "Health access wasn't granted. You can continue without Health sync."
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingHealthKit)
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
