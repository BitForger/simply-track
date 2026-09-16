# SimplyTrack Architecture & Services

This document outlines the internal architecture, key services, and how data flows through Simply Track.

## Overview

Simply Track uses a modular architecture built around SwiftUI and SwiftData, with a dedicated sync coordinator managing HealthKit interactions. The app calculates calorie targets dynamically based on user profile metrics (age, sex, height, weight, activity level, goal) and optionally adjusts daily/weekly maximums based on active calories burned from Apple Health.

## Core Services

### 1. **HealthKitSyncCoordinator** (`Item.swift`)

The primary service responsible for all HealthKit integration.

**Responsibilities:**
- Authorization and permissions management
- Reading workout (active energy) and dietary calorie data from HealthKit
- Syncing HealthKit entries into the local database
- Deleting entries from both HealthKit and local storage
- Aggregating burned calories for burn-adjusted max calculations

**Key Methods:**
- `authorizationStatus() -> HKAuthorizationStatus` — Check current authorization state
- `requestAuthorization(completion:)` — Prompt user for HealthKit access (async/await wrapper provided)
- `pullActiveCaloriesBurned(from:to:) -> ActiveCaloriesReadResult` — Fetch cumulative active energy burned over a date range with fallback messaging
- `syncFromHealthKit(completion:)` — Read dietary calories from HealthKit and merge with local entries
- `deleteHealthKitEntry(...)` — Remove entry from both HealthKit and local storage
- `getHealthKitEntries(...)` — Retrieve active HealthKit entries from the app's read-only HK store

**Data Flow:**
```
HealthKit (HKSampleStore)
    ↓
HealthKitSyncCoordinator.syncFromHealthKit()
    ↓
Local FoodEntry items (SwiftData)
    ↓
Dashboard calculations and display
```

### 2. **CalorieSummaryCalculator** (`Item.swift`)

Static helper for aggregating and analyzing calorie data.

**Key Methods:**
- `caloriesSummary(for:in:) -> (consumed: Double, goal: Double, remaining: Double)` — Compute daily totals
- `weeklyCaloriesSummary(for:in:) -> (consumed: Double, goal: Double, remaining: Double)` — Compute weekly totals with fixed Sunday-start boundaries
- `weekRange(for:) -> (start: Date, end: Date)` — Fixed weekly boundaries matching the current Gregorian calendar week (Sunday–Saturday)

**Purpose:**
- Aggregates intake from all `FoodEntry` items for a given time window
- Computes remaining calories (goal − consumed) accounting for burn adjustments
- Ensures consistent week boundaries across all weekly calculations

### 3. **UserProfile** (SwiftData Model, `Item.swift`)

Persistent user data and profile-based calculations.

**Fields:**
- `name`, `age`, `sex`, `height`, `weight`, `activityLevel`, `goal` — User metrics
- `createdAt` — Timestamp of profile creation
- **Removed:** `selectedTargetModeRawValue` (legacy; kept in V1 schema only for migration)

**Computed Properties:**
- `baseDailyTarget: Double` — Daily calorie target based on TDEE formula:
  - **Maintain goal:** TDEE as-is
  - **Lose weight goal:** TDEE − 500
  - Uses formula: `BMR = 10 × weight + 6.25 × height − 5 × age [+ 5 or − 161 by sex]`; `TDEE = BMR × activityLevel`
- `weeklyTarget: Double` — 7 × baseDailyTarget

## Data Models

### FoodEntry
- `id`, `name`, `calories`, `timestamp`, `source` (local or HealthKit)
- SwiftData `@Model` for persistence

### FoodCatalogItem
- `id`, `name`, `calories`, `calorieRange`, `timestamp`
- Pre-seeded shortcuts for quick logging

### UserProfile
- Persistent via SwiftData
- Linked to all intake calculations and burn adjustments

## Burn-Adjusted Max Calorie Feature

### Overview
When enabled in Settings, daily and weekly calorie maximums include a bonus based on active calories burned via Apple Health, allowing users to "earn" extra calorie allowance through exercise.

### Formula
```
adjustedMax = baseDailyTarget + (burnMultiplier × activeCaloriesBurned)
```

Where:
- `baseDailyTarget` — User's baseline calorie target (computed from BMR/TDEE)
- `burnMultiplier` — 1.0 for Maintain goals; 0.8 for Lose Weight goals (conservative assumption that 20% of burned is already accounted for in TDEE)
- `activeCaloriesBurned` — Cumulative active energy from HealthKit for the current day/week

### User Preference
- Toggle in **Settings:** "Adjust max with active calories burned"
- Stored via `@AppStorage("includeActiveCaloriesInMax")`
- Applies to both daily and weekly views
- Calculated in real-time in `ContentView.swift` without schema changes to SwiftData

### Weekly Boundaries
- Fixed to calendar week (Sunday–Saturday) matching `CalorieSummaryCalculator.weekRange(for:)`
- Prevents daily swings as new burn data is added
- Ensures consistency with weekly intake calculations

### Fallback Behavior
If HealthKit data is unavailable or access denied:
- Active calories default to `0`
- User sees base targets applied
- Optional fallback message displays in orange: *"Active calories unavailable right now. Using base targets only until Health data is available."*
- App remains fully functional

### Integration Points
- **ContentView.swift:**
  - Fetches burn data on app launch and after each Health sync
  - Stores `dailyActiveCaloriesBurned` and `weeklyActiveCaloriesBurned` as `@State`
  - Computes `adjustedDailyBonus`, `adjustedWeeklyBonus` using `burnAdjustmentMultiplier`
  - Displays bonus in daily/weekly cards with formula explanation
- **SettingsView.swift:**
  - Hosts the toggle controlling the feature
  - Displays summary text explaining the active calculation (e.g., "Base 2000 + bonus (80% of burned)")

## Data Persistence & Schema Versioning

### SwiftData Schemas (Versioned)

**SimplyTrackSchemaV1** (Initial)
- `FoodEntry`, `FoodCatalogItem`, `UserProfile`
- `UserProfile` includes legacy `selectedTargetModeRawValue` field (deprecated)

**SimplyTrackSchemaV2** (Current)
- `FoodEntry`, `FoodCatalogItem`, `UserProfile`
- `UserProfile` removes `selectedTargetModeRawValue`
- **Active schema** for all new installs and updated devices

### Migration Plan
- **SimplyTrackMigrationPlan:** Lightweight migration from V1 → V2
  - Automatically removes legacy `selectedTargetModeRawValue` on devices upgrading from V1
  - Preserves all other user data
  - No data loss

### Initialization (`simply_trackApp.swift`)
- Preflight directory creation ensures `~/Library/Application Support` exists before model container initialization
- Wired `migrationPlan: SimplyTrackMigrationPlan.self` to `ModelContainer`
- Recovery path: Deletes corrupted store files and retries; falls back to in-memory store if needed
- All paths include preflight directory creation to prevent CoreData initialization errors

## Views & State Flow

### ContentView (Main Dashboard)
```
@State private var includeActiveCaloriesInMax: AppStorage (persisted preference)
@State private var dailyActiveCaloriesBurned: Double
@State private var weeklyActiveCaloriesBurned: Double
@State private var activeCaloriesFallbackMessage: String

refreshActiveCaloriesBurned() — Fetch and update burn data
↓
Compute adjustedDailyTarget, adjustedWeeklyTarget, bonuses
↓
Render daily/weekly cards with totals, remaining, and bonus labels
```

### SettingsView
- Edits `UserProfile` (name, metrics, goal)
- Toggles `includeActiveCaloriesInMax` with explanatory caption
- Explains burn adjustment formula relative to current goal

### HealthKitSyncCoordinator
- Displayed in ContentView as "Pull from HealthKit" button
- Triggers `syncFromHealthKit()` and UI refresh
- Non-blocking async operation

## Calculated Flows

### Daily Calorie Calculation
```
baseDailyTarget (from UserProfile.baseDailyTarget)
+ [if includeActiveCaloriesInMax] adjustedDailyBonus (burnMultiplier × dailyActiveCaloriesBurned)
= dailyTarget (max allowance)

dailyTarget - consumedToday = dailyRemaining
```

### Weekly Calorie Calculation
```
weeklyTarget (7 × baseDailyTarget)
+ [if includeActiveCaloriesInMax] adjustedWeeklyBonus (burnMultiplier × weeklyActiveCaloriesBurned)
= adjustedWeeklyTarget (max allowance for the week)

adjustedWeeklyTarget - consumedThisWeek = weeklyRemaining
```

### Active Calorie Fetch
```
HealthKit.pullActiveCaloriesBurned(from: startDate, to: endDate)
→ HKStatisticsQuery with .cumulativeSum (active energy burned)
→ Fallback to 0 + optional fallback message if unavailable
→ Stored in @State; refreshed on app launch and after sync
```

## Error Handling & Recovery

### HealthKit Access
- Missing authorization → fallback to 0 burned, show message
- Health app data unavailable → fallback to 0 burned
- Partial data failures → best-effort aggregation

### SwiftData Store
- Corrupt store → delete and recreate with migration
- Migration failure → in-memory fallback (data not persisted but app usable)

### File System
- Missing `Library/Application Support` → create on preflight
- Permission issues → log warning, allow SwiftData recovery to proceed

## Testing Considerations

### Simulator
- Enable HealthKit permission in Simulator settings
- Use HealthKit app to manually add workout entries
- Toggle "Adjust max with active calories burned" to observe bonus changes

### Debug Logging
- `DEBUG` conditional print statements log successful preflight directory creation
- CoreData logs cleaner after migration/preflight improvements

---

**Last Updated:** September 2026
**Current Schema Version:** 2.0.0
