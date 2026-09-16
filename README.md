# Simply Track

Simply Track is a SwiftUI calorie-tracking app built with SwiftData. It helps you log food entries, track daily and weekly calorie goals, and review your consistency over time. The app includes optional HealthKit sync for reading active calories burned, reminders, a quick-start onboarding flow, and an optional burn-adjusted max calorie feature that lets you "earn" extra calorie allowance through exercise.

## Features

- **Quick Start onboarding** for privacy, HealthKit access, and sync preferences
- **Manual food logging** with name, amount, calories, and time
- **Daily and weekly dashboards** with progress indicators and target summaries
- **Profile-based calorie targets** using age, sex, height, weight, activity level, and goal
- **Estimated BMR and TDEE** from user metrics and activity level
- **Burn-adjusted max calories** (toggle in Settings) — daily/weekly maximum includes a bonus based on active calories burned from Apple Health
  - Maintain goal: 100% of burned calories added to max
  - Lose weight goal: 80% of burned calories added to max (conservative)
  - Uses fixed calendar week boundaries to prevent daily swings
- **Food catalog shortcuts** for common entries
- **HealthKit integration** for reading, syncing, and deleting calorie entries; pulling active energy burned
- **Optional reminders** to log calories later in the day
- **SwiftData persistence** with versioned schemas, automatic migration, and recovery handling

## Requirements

- Xcode with SwiftUI and SwiftData support
- iPhone and/or Mac run destination, depending on the scheme configuration
- Optional permissions for HealthKit and notifications if you enable those features

## Getting Started

1. Open `simply-track.xcodeproj` in Xcode.
2. Select the `simply-track` scheme.
3. Choose a simulator or connected device.
4. Build and run the app.

When the app launches for the first time, it creates a default profile and seeds a small food catalog automatically.

## Project Structure

```text
simply-track/
├── ContentView.swift      # Main app UI, home dashboard, logging, sync
├── Item.swift             # SwiftData models, HealthKitSyncCoordinator, CalorieSummaryCalculator
├── SettingsView.swift     # Profile metrics, app settings, burn-adjust toggle
├── simply_trackApp.swift  # App entry point, model container with schema migration
└── Assets.xcassets        # App icons and asset catalog
```

**Key Components:**
- **HealthKitSyncCoordinator** — Service for HealthKit authorization, syncing, and active calorie queries
- **CalorieSummaryCalculator** — Static helper for daily/weekly intake aggregation with fixed week boundaries
- **UserProfile** — Persistent user data with BMR/TDEE calculations (schema-versioned in V2)
- **FoodEntry & FoodCatalogItem** — SwiftData models for food tracking

## Data and Sync Notes

- Entries are stored locally using SwiftData with explicit schema versioning and automatic migration.
- HealthKit sync is optional and can be enabled from the app.
- Active calorie burn adjustment can be toggled in Settings ("Adjust max with active calories burned").
- Reminder notifications are optional and can be toggled in Settings.
- The app includes a recovery path for incompatible or corrupted SwiftData stores.
- On app launch, the app ensures required directories exist and performs schema migrations if needed (lightweight V1→V2 migration).

## Architecture

See **AGENTS.md** for detailed documentation of:
- HealthKitSyncCoordinator service and data flows
- CalorieSummaryCalculator for aggregating calorie data
- Burn-adjusted max calorie calculation and formula
- Schema versioning (V1 to V2) and migration strategy
- Error handling and recovery paths

## License

No license has been added yet. Add one here if you plan to share the project publicly.
