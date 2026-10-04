import SwiftUI
import SwiftData

struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    let entries: [FoodEntry]
    let includeActiveCaloriesInMax: Bool
    let dailyActiveCaloriesBurned: Double
    let weeklyActiveCaloriesBurned: Double
    let activeCaloriesFallbackMessage: String
    let syncMessage: String
    let hasCompletedQuickStart: Bool
    let onOpenQuickStart: () -> Void

    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }

        let fallbackProfile = UserProfile()
        modelContext.insert(fallbackProfile)
        return fallbackProfile
    }

    private var todayCalories: Double {
        CalorieSummaryCalculator.dailyTotal(from: entries, on: .now)
    }

    private var weeklyCalories: Double {
        CalorieSummaryCalculator.weeklyTotal(from: entries, around: .now)
    }

    private var burnAdjustmentMultiplier: Double {
        profile.nutritionGoal == .loseWeight ? 0.8 : 1.0
    }

    private var baseDailyTarget: Double {
        profile.dailyCalorieTarget
    }

    private var baseWeeklyTarget: Double {
        profile.weeklyCalorieTarget
    }

    private var adjustedDailyBonus: Double {
        includeActiveCaloriesInMax ? (dailyActiveCaloriesBurned * burnAdjustmentMultiplier) : 0
    }

    private var adjustedWeeklyBonus: Double {
        includeActiveCaloriesInMax ? (weeklyActiveCaloriesBurned * burnAdjustmentMultiplier) : 0
    }

    private var dailyTarget: Double {
        baseDailyTarget + adjustedDailyBonus
    }

    private var weeklyTarget: Double {
        baseWeeklyTarget + adjustedWeeklyBonus
    }

    private var weekLoggedDays: Int {
        StreakCalculator.weekLoggedDays(entries: entries, around: .now)
    }

    private var currentStreakDays: Int {
        StreakCalculator.currentDailyLoggingStreak(entries: entries)
    }

    var body: some View {
        List {
            if !hasCompletedQuickStart {
                Section("Quick Start") {
                    Text("Finish the 3-step privacy setup when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Quick Start") {
                        onOpenQuickStart()
                    }
                }
            }

            Section("Today") {
                dailyCard
            }

            Section("Week") {
                weeklyCard
            }

            Section("Consistency") {
                consistencyCard
            }

            Section("Targets") {
                metabolismCard
            }

            if !syncMessage.isEmpty {
                Section("Sync") {
                    Text(syncMessage)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Simply Track")
    }

    private var dailyCard: some View {
        let progress = max(0, min(1, todayCalories / max(dailyTarget, 1)))
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(todayCalories)) / \(Int(dailyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.green)
            if includeActiveCaloriesInMax {
                Text("Base \(Int(baseDailyTarget)) + bonus \(Int(adjustedDailyBonus.rounded())) (\(Int((burnAdjustmentMultiplier * 100).rounded()))% of \(Int(dailyActiveCaloriesBurned.rounded())) burned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Daily progress")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklyCard: some View {
        let status = CalorieSummaryCalculator.weeklyStatus(total: weeklyCalories, target: weeklyTarget)
        let progress = max(0, min(1, weeklyCalories / max(weeklyTarget, 1)))
        let weekRange = CalorieSummaryCalculator.weekRange(for: .now)
        let remaining = CalorieSummaryCalculator.remainingWeeklyCalories(total: weeklyCalories, target: weeklyTarget)

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(weeklyCalories)) / \(Int(weeklyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.blue)
            if includeActiveCaloriesInMax {
                Text("Base \(Int(baseWeeklyTarget)) + bonus \(Int(adjustedWeeklyBonus.rounded())) (\(Int((burnAdjustmentMultiplier * 100).rounded()))% of \(Int(weeklyActiveCaloriesBurned.rounded())) burned this week)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Week \(weekRange.start, format: .dateTime.month().day()) - \(weekRange.end.addingTimeInterval(-1), format: .dateTime.month().day())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(weeklyStatusText(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(weeklyStatusColor(status))
            Text("Remaining this week: \(Int(remaining)) cal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current streak: \(currentStreakDays) day\(currentStreakDays == 1 ? "" : "s")")
            Text("Logged this week: \(weekLoggedDays) of 7 days")
            Text("Weekly adherence matters as much as daily precision.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metabolismCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated BMR: \(Int(profile.estimatedBMR())) cal/day")
            Text("Estimated TDEE: \(Int(profile.estimatedTDEE())) cal/day")
            Group {
                if includeActiveCaloriesInMax {
                    Text("Adjusted max uses base + \(Int((burnAdjustmentMultiplier * 100).rounded()))% of active calories burned so far.")
                } else {
                    Text("Adjusted max is off. Daily/weekly max uses your base targets only.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if includeActiveCaloriesInMax && !activeCaloriesFallbackMessage.isEmpty {
                Text(activeCaloriesFallbackMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func weeklyStatusText(_ status: WeeklyAggregateStatus) -> String {
        switch status {
        case .onTrack:
            return "On track this week"
        case .aboveTarget:
            return "Above weekly target"
        case .belowTarget:
            return "Below weekly target"
        }
    }

    private func weeklyStatusColor(_ status: WeeklyAggregateStatus) -> Color {
        switch status {
        case .onTrack:
            return .green
        case .aboveTarget:
            return .orange
        case .belowTarget:
            return .red
        }
    }
}
