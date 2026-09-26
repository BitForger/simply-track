//
//  TDEEEquationSettingsView.swift
//  simply-track
//
//  Created by Noah on 9/25/26.
//

import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

struct TDEEEquationSettingsView: View {
    @Bindable var profile: UserProfile

    @State private var leanBodyMassText: String = ""
    @State private var isFetchingFromHealth = false
    @State private var healthFetchMessage: String?
    @FocusState private var isLeanBodyMassFieldFocused: Bool

    private let leanBodyMassReader = LeanBodyMassReader()

    private var leanBodyMassTextBinding: Binding<String> {
        Binding(
            get: { leanBodyMassText },
            set: { newValue in
                leanBodyMassText = newValue.filter { $0.isNumber || $0 == "." }
                profile.leanBodyMassKg = Double(leanBodyMassText)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("TDEE Equation", selection: $profile.tdeeEquation) {
                    ForEach(TDEEEquation.allCases) { equation in
                        Text(equation.title).tag(equation)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Choose Equation")
            }

            Section {
                ForEach(TDEEEquation.allCases) { equation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(equation.title)
                            .font(.subheadline.weight(.semibold))
                        Text(equation.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("About These Equations")
            }

            if profile.tdeeEquation == .katchMcArdle {
                Section {
                    HStack(spacing: 8) {
                        TextField("e.g. 60", text: leanBodyMassTextBinding)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                            .focused($isLeanBodyMassFieldFocused)
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await fetchFromHealth() }
                    } label: {
                        if isFetchingFromHealth {
                            ProgressView()
                        } else {
                            Label("Fetch from Health", systemImage: "heart.text.square")
                        }
                    }
                    .disabled(isFetchingFromHealth)

                    if let healthFetchMessage {
                        Text(healthFetchMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Lean Body Mass")
                } footer: {
                    Text("Required for the Katch-McArdle equation. If Health has a stored Lean Body Mass value, tap \"Fetch from Health\" to use it automatically. Until a value is set, Mifflin-St Jeor is used instead.")
                }
            }
        }
        .navigationTitle("TDEE Equation")
        .onAppear {
            leanBodyMassText = profile.leanBodyMassKg.map(formattedWeight) ?? ""
        }
        .onChange(of: profile.leanBodyMassKg) { _, newValue in
            guard !isLeanBodyMassFieldFocused else { return }
            leanBodyMassText = newValue.map(formattedWeight) ?? ""
        }
    }

    private func fetchFromHealth() async {
        isFetchingFromHealth = true
        healthFetchMessage = nil
        defer { isFetchingFromHealth = false }

        do {
            let kilograms = try await leanBodyMassReader.fetchLatestLeanBodyMassKg()
            profile.leanBodyMassKg = kilograms
            leanBodyMassText = formattedWeight(kilograms)
        } catch {
            healthFetchMessage = "Couldn't read lean body mass from Health: \(error.localizedDescription)"
        }
    }

    private func formattedWeight(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// Small, self-contained reader for the Health "Lean Body Mass" quantity type.
/// Requests read-only authorization on demand rather than requiring the main
/// HealthKit sync flow to have already run.
private struct LeanBodyMassReader {
    enum ReaderError: LocalizedError {
        case unsupported
        case noSampleFound

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "HealthKit is not available on this platform."
            case .noSampleFound:
                return "No Lean Body Mass sample found in Health."
            }
        }
    }

    func fetchLatestLeanBodyMassKg() async throws -> Double {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let leanBodyMassType = HKObjectType.quantityType(forIdentifier: .leanBodyMass) else {
            throw ReaderError.unsupported
        }

        let store = HKHealthStore()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: [leanBodyMassType]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if granted {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ReaderError.noSampleFound)
                }
            }
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: leanBodyMassType, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(throwing: ReaderError.noSampleFound)
                    return
                }
                let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kilograms)
            }
            store.execute(query)
        }
#else
        throw ReaderError.unsupported
#endif
    }
}

#Preview {
    NavigationStack {
        TDEEEquationSettingsView(profile: UserProfile())
    }
}
