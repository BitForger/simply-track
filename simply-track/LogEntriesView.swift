//
//  LogEntriesView.swift
//  simply-track
//
//  Created by Noah on 9/17/26.
//

import SwiftUI

struct LogEntriesView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.editMode) private var editMode
    @State private var entryBeingEdited: FoodEntry?
    @State private var selectedEntryIDs = Set<UUID>()

    let entries: [FoodEntry]
    let onAddEntry: () -> Void
    let onDeleteEntries: (IndexSet) -> Void
    let onEditEntry: (FoodEntry, EditableFoodEntryValues) -> Void

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

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        List(selection: $selectedEntryIDs) {
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteSingleEntry(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            beginEditing(entry)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .tag(entry.id)
                }
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
        .sheet(item: $entryBeingEdited) { entry in
            EditFoodEntrySheet(entry: entry) { updatedValues in
                onEditEntry(entry, updatedValues)
            }
        }
        .toolbar {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }

            if isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        deleteSelectedEntries()
                    } label: {
                        Text(selectedEntryIDs.isEmpty ? "Delete Selected" : "Delete Selected (\(selectedEntryIDs.count))")
                    }
                    .disabled(selectedEntryIDs.isEmpty)
                }
            }
#endif
            ToolbarItem {
                Button(action: onAddEntry) {
                    Label("Add Entry", systemImage: "plus")
                }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                selectedEntryIDs.removeAll()
            }
        }
    }

    private func openHealthDietaryHistory() {
        openNextDietaryURL(from: dietaryHistoryURLs)
    }

    private func beginEditing(_ entry: FoodEntry) {
        entryBeingEdited = entry
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

    private func deleteSingleEntry(_ entry: FoodEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        onDeleteEntries(IndexSet(integer: index))
    }

    private func deleteSelectedEntries() {
        let mappedOffsets = IndexSet(
            entries.enumerated().compactMap { selectedEntryIDs.contains($0.element.id) ? $0.offset : nil }
        )
        guard !mappedOffsets.isEmpty else { return }

        onDeleteEntries(mappedOffsets)
        selectedEntryIDs.removeAll()
    }
}

struct EditableFoodEntryValues {
    let foodName: String
    let amountDescription: String
    let calories: Double
    let consumedAt: Date
}

private struct EditFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: FoodEntry
    let onSave: (EditableFoodEntryValues) -> Void

    @State private var foodName: String
    @State private var amountDescription: String
    @State private var caloriesText: String
    @State private var consumedAt: Date

    init(entry: FoodEntry, onSave: @escaping (EditableFoodEntryValues) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _foodName = State(initialValue: entry.foodName)
        _amountDescription = State(initialValue: entry.amountDescription)
        _caloriesText = State(initialValue: String(Int(entry.calories.rounded())))
        _consumedAt = State(initialValue: entry.consumedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Food name", text: $foodName)
                TextField("Amount", text: $amountDescription)
                TextField("Calories", text: $caloriesText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                DatePicker("Time", selection: $consumedAt)
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !amountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Double(caloriesText) != nil
    }

    private func save() {
        guard let calories = Double(caloriesText) else { return }
        onSave(
            EditableFoodEntryValues(
                foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDescription: amountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: calories,
                consumedAt: consumedAt
            )
        )
        dismiss()
    }
}
