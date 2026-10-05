# Simply Track

Simply Track is a SwiftUI calorie tracking app built on SwiftData. It focuses on fast food logging, clear daily and weekly progress, and optional HealthKit integration.

## Highlights

- Daily and weekly calorie progress with fixed Sunday-start week boundaries.
- Home dashboard weekly status uses `CalorieSummaryCalculator.weeklyProgress(...)` for consistent progress math.
- Profile-driven targets with selectable TDEE equations (Mifflin-St Jeor, Harris-Benedict, Katch-McArdle).
- Optional burn-adjusted max calories (base target + percentage of active calories burned).
- Optional reminders and Quick Start onboarding.
- Optional iCloud-backed SwiftData persistence with local fallback and recovery handling.

## Requirements

- Xcode 16+
- iOS 18+ (or compatible Apple platform destination configured by the scheme)
- HealthKit and notification permissions are optional and only needed for those features

## Run Locally

1. Open `simply-track.xcodeproj` in Xcode.
2. Select the `simply-track` scheme.
3. Pick a simulator or connected device.
4. Build and run.

On first launch, the app creates a default `UserProfile` and seeds base food catalog entries.

## Current Project Layout

```text
simply-track/
├── ContentView.swift                    # Root container, tab wiring, orchestration
├── HomeDashboardView.swift              # Daily/weekly cards, streaks, metabolism summary
├── LogEntriesView.swift                 # Entry list, edit/delete flows, history shortcuts
├── SettingsView.swift                   # Profile, targets, sync toggles, Health import
├── AddFoodEntrySheet.swift              # Manual add-entry form
├── QuickStartOnboardingView.swift       # First-run onboarding flow
├── TDEEEquationSettingsView.swift       # TDEE equation + lean body mass config
├── Services/
│   ├── CalorieSummaryCalculator.swift
│   ├── HealthKitService.swift
│   ├── HealthKitSyncCoordinator.swift
│   ├── ReminderManager.swift
│   └── StreakCalculator.swift
├── Models/
│   ├── EntryPayloads.swift
│   ├── FoodCatalogSeed.swift
│   ├── TDEEEquation.swift
│   ├── WeeklyAggregateStatus.swift
│   └── Schemas/
│       ├── SimplyTrackSchemaV1.swift
│       ├── SimplyTrackSchemaV2.swift
│       ├── SimplyTrackSchemaV3.swift
│       ├── SimplyTrackSchemaV4.swift
│       ├── SimplyTrackSchemaV5.swift
│       ├── SimplyTrackSchemaV6.swift
│       ├── SimplyTrackSchemaV7.swift
│       └── SimplyTrackMigrationPlan.swift
└── simply_trackApp.swift                # App entry, model container setup, persistence fallback
```

## Data Model Snapshot

- `FoodEntry`: consumed item, calories, timestamps, source, optional HealthKit sample ID.
- `FoodCatalogItem`: reusable food templates for quick logging.
- `UserProfile`: body metrics, target settings, goal mode, sync/reminder preferences.

Active schema is `SimplyTrackSchemaV7`.

## Testing

- Unit tests live in `simply-trackTests/simply_trackTests.swift`.
- Current shared scheme includes the `simply-trackTests` test bundle.
- Most recent run in this workspace context: 8 passed, 0 failed.

## Additional Docs

- Architecture and service details: `AGENTS.md`
- Privacy policy: `PRIVACY.md`
- License: `LICENSE`

## Support

If Simply Track is useful to you, you can support development on [Ko-fi](https://ko-fi.com/bitforger).
