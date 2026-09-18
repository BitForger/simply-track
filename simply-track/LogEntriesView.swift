//
//  LogEntriesView.swift
//  simply-track
//
//  Created by Noah on 9/17/26.
//

import SwiftUI

struct LogEntriesView: View {
    @Environment(\.openURL) private var openURL

    let entries: [FoodEntry]
    let onAddEntry: () -> Void
    let onDeleteEntries: (IndexSet) -> Void

    private var todayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDateInToday($0.consumedAt) }
    }

    private var yesterdayDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    }

    private var yesterdayCalories: Double {
        CalorieSummaryCalculator.dailyTotal(from: entries, on: yesterdayDate)
    }

    private var dietaryHistoryURLs: [URL] {
        [
            "x-apple-health://SampleType?type=HKQuantityTypeIdentifierDietaryEnergyConsumed",
            "x-apple-health://browse?query=Dietary Energy",
            "x-apple-health://"
        ].compactMap(URL.init(string:))
    }

    var body: some View {
        List {
            Section("Today") {
                if todayEntries.isEmpty {
                    Text("No entries yet today. Tap + to add your first meal.")
                        .foregroundStyle(.secondary)
                }

                ForEach(todayEntries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.foodName)
                            Text(entry.amountDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Int(entry.calories)) cal")
                            Text(entry.consumedAt, format: .dateTime.hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteFromTodayList)
            }

            Section("History") {
#if os(iOS)
                HStack {
                    Text("Yesterday total")
                    Spacer()
                    Text("\(Int(yesterdayCalories)) cal")
                        .foregroundStyle(.secondary)
                }
                if #unavailable(iOS 26.0) {
                    Button {
                        openHealthDietaryHistory()
                    } label: {
                        Label("Open in Health", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.automatic)
                }
#else
                Text("Previous days are available in the Health app on iPhone.")
                    .foregroundStyle(.secondary)
#endif
            }
        }
#if os(iOS)
        .overlay(alignment: .bottomTrailing) {
            if #available(iOS 26.0, *) {
                Button {
                    openHealthDietaryHistory()
                } label: {
                    Label("Previous History", systemImage: "heart.text.square")
                }
                .buttonStyle(.glassProminent)
                .padding(.trailing, 16)
                .padding(.bottom, 20)
            }
        }
#endif
        .navigationTitle("Log")
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
#endif
            ToolbarItem {
                Button(action: onAddEntry) {
                    Label("Add Entry", systemImage: "plus")
                }
            }
        }
    }

    private func openHealthDietaryHistory() {
        openNextDietaryURL(from: dietaryHistoryURLs)
    }

    private func openNextDietaryURL(from candidates: [URL]) {
        guard let next = candidates.first else { return }
        let remaining = Array(candidates.dropFirst())

        openURL(next) { accepted in
            if !accepted {
                openNextDietaryURL(from: remaining)
            }
        }
    }

    private func deleteFromTodayList(offsets: IndexSet) {
        let idsToDelete = offsets.map { todayEntries[$0].id }
        let mappedOffsets = IndexSet(entries.enumerated().compactMap { idsToDelete.contains($0.element.id) ? $0.offset : nil })
        onDeleteEntries(mappedOffsets)
    }
}
