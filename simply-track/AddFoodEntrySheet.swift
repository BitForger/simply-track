import SwiftUI

struct AddFoodEntrySheet: View {
    private static let minCaloriesPerEntry = 1.0
    private static let maxCaloriesPerEntry = 10000.0

    @Environment(\.dismiss) private var dismiss

    let foodCatalog: [FoodCatalogItem]
    let onSave: (AddFoodEntryPayload) -> Void

    @State private var selectedCatalogID: UUID?
    @State private var foodName = ""
    @State private var amountDescription = ""
    @State private var caloriesText = ""
    @State private var consumedAt = Date()
    @State private var saveToCatalog: Bool

    init(foodCatalog: [FoodCatalogItem], initialSaveToCatalog: Bool, onSave: @escaping (AddFoodEntryPayload) -> Void) {
        self.foodCatalog = foodCatalog
        self.onSave = onSave
        _saveToCatalog = State(initialValue: initialSaveToCatalog)
    }

    private var suggestedCatalog: [FoodCatalogItem] {
        foodCatalog.filter { !$0.isUserAdded }.sorted { $0.name < $1.name }
    }

    private var personalCatalog: [FoodCatalogItem] {
        foodCatalog.filter { $0.isUserAdded }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !foodCatalog.isEmpty {
                    Picker("Quick pick", selection: $selectedCatalogID) {
                        Text("None").tag(UUID?.none)
                        if !personalCatalog.isEmpty {
                            Section("Your Foods") {
                                ForEach(personalCatalog) { item in
                                    Text(item.name).tag(UUID?.some(item.id))
                                }
                            }
                        }
                        if !suggestedCatalog.isEmpty {
                            Section("Suggested") {
                                ForEach(suggestedCatalog) { item in
                                    Text(item.name).tag(UUID?.some(item.id))
                                }
                            }
                        }
                        
                    }
                    .onChange(of: selectedCatalogID) { _, newValue in
                        guard let id = newValue, let item = foodCatalog.first(where: { $0.id == id }) else { return }
                        foodName = item.name
                        amountDescription = item.defaultAmountDescription
                        caloriesText = String(Int(item.caloriesPerDefaultAmount))
                    }
                }

                TextField("Food name", text: $foodName)
                TextField("Amount", text: $amountDescription)
                TextField("Calories", text: $caloriesText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                if let caloriesValidationMessage {
                    Text(caloriesValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                DatePicker("Time", selection: $consumedAt)

                Toggle("Save to Quick Pick", isOn: $saveToCatalog)
            }
            .navigationTitle("Manual Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        guard let calories = parsedCalories else { return false }
        return !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !amountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && calories >= Self.minCaloriesPerEntry
            && calories <= Self.maxCaloriesPerEntry
    }

    private var parsedCalories: Double? {
        Double(caloriesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var caloriesValidationMessage: String? {
        let trimmed = caloriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let calories = parsedCalories else { return "Enter a numeric calorie value." }
        guard calories >= Self.minCaloriesPerEntry else { return "Calories must be greater than zero." }
        guard calories <= Self.maxCaloriesPerEntry else { return "Calories must be \(Int(Self.maxCaloriesPerEntry)) or less." }
        return nil
    }

    private func save() {
        guard let calories = parsedCalories,
              calories >= Self.minCaloriesPerEntry,
              calories <= Self.maxCaloriesPerEntry else { return }
        onSave(
            AddFoodEntryPayload(
                foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDescription: amountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: calories,
                consumedAt: consumedAt,
                saveToCatalog: saveToCatalog
            )
        )
        dismiss()
    }
}
