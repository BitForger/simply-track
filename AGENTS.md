# SimplyTrack Architecture Guide

This document describes the current architecture and major data flows for Simply Track.

## Overview

Simply Track is a SwiftUI + SwiftData app with three primary user surfaces:

- `HomeDashboardView` for daily/weekly status.
- `LogEntriesView` for entry CRUD.
- `SettingsView` for profile, targets, sync, reminders, and catalog tools.

`ContentView` orchestrates these surfaces, coordinating persistence and HealthKit-related refresh actions.

## Workspace Structure

```text
simply-track/
├── ContentView.swift
├── HomeDashboardView.swift
├── LogEntriesView.swift
├── SettingsView.swift
├── AddFoodEntrySheet.swift
├── QuickStartOnboardingView.swift
├── TDEEEquationSettingsView.swift
├── Services/
│   ├── CalorieSummaryCalculator.swift
│   ├── HealthKitService.swift
│   ├── HealthKitSyncCoordinator.swift
│   ├── ReminderManager.swift
│   └── StreakCalculator.swift
├── Models/
│   ├── BiologicalSex.swift
│   ├── EntryPayloads.swift
│   ├── FoodCatalogSeed.swift
│   ├── NutritionGoal.swift
│   ├── TDEEEquation.swift
│   ├── WeeklyAggregateStatus.swift
│   ├── WeightLossPace.swift
│   └── Schemas/
│       ├── SimplyTrackSchemaV1.swift
│       ├── SimplyTrackSchemaV2.swift
│       ├── SimplyTrackSchemaV3.swift
│       ├── SimplyTrackSchemaV4.swift
│       ├── SimplyTrackSchemaV5.swift
│       ├── SimplyTrackSchemaV6.swift
│       ├── SimplyTrackSchemaV7.swift
│       └── SimplyTrackMigrationPlan.swift
└── simply_trackApp.swift
```

## Core Domain Models

### FoodEntry

- Stored in SwiftData.
- Represents one consumed item.
- Includes calorie value, consumed time, source (`manual` or `healthKit`), and optional HealthKit sample ID.

### FoodCatalogItem

- Quick-pick template for faster logging.
- Supports seeded entries and user-added entries (`isUserAdded`).

### UserProfile

- Stores demographics, activity multiplier, goal mode, and personalization flags.
- Stores manual targets (`dailyCalorieTarget`, `weeklyCalorieTarget`) and recommendation inputs.
- Stores privacy/sync flags (`useHealthSync`, `enableReminders`, `includeActiveCaloriesInMax`, `autoSaveToCatalog`).
- Supports TDEE equation choice + optional lean body mass.

## Calculation Services

### CalorieSummaryCalculator (`Services/CalorieSummaryCalculator.swift`)

- `dailyTotal(from:on:)`
- `weekRange(for:calendar:)`
- `weeklyTotal(from:around:calendar:)`
- `weeklyStatus(total:target:tolerance:)`
- `weeklyProgress(total:target:)`
- `remainingWeeklyCalories(total:target:)`

Important behavior:

- Weekly boundaries use a fixed Sunday-start Gregorian calendar.
- Weekly dashboard progress uses `weeklyProgress(...)` directly to keep calculations centralized.

### StreakCalculator (`Services/StreakCalculator.swift`)

- Computes current streak and week logging consistency statistics for dashboard UI.

## HealthKit + Reminder Services

### HealthKitService (`Services/HealthKitService.swift`)

- Handles HealthKit authorization checks/requests.
- Reads dietary energy samples into `CalorieEntryPayload`.
- Reads active energy for burn adjustments.
- Saves/deletes diet entries in HealthKit.
- Performs read-first sync merge logic using `updatedAt` precedence.

### HealthKitSyncCoordinator (`Services/HealthKitSyncCoordinator.swift`)

- View-facing observable state for sync messages, authorization status, and flow control.
- Delegates platform operations to `HealthKitService`.

### ReminderManager (`Services/ReminderManager.swift`)

- Schedules/disables local reminders.
- Returns explicit status values consumed by `SettingsView` and `ContentView`.

## UI Layer Responsibilities

### ContentView

- Hosts top-level navigation/tabs and shared app-state orchestration.
- Owns `HealthKitSyncCoordinator` lifecycle.
- Triggers initial refresh and write-through flows for profile + entries.

### HomeDashboardView

- Shows daily/weekly cards, status labels, and consistency metrics.
- Applies burn-adjusted bonus when enabled.
- Uses `CalorieSummaryCalculator.weeklyStatus(...)` and `weeklyProgress(...)`.

### LogEntriesView

- Displays Today + History sections.
- Supports edit and delete operations.
- Provides Health app jump action for history on supported iOS versions.

### SettingsView

- Manages profile inputs, goal mode, target editing, and equation selection.
- Handles reminder preference updates with permission-aware feedback.
- Handles HealthKit import candidate scan and selective catalog import.
- Persists changes with debounced saves for high-frequency edits.

## Persistence and Startup

### App entry (`simply_trackApp.swift`)

- Builds SwiftData container from `SimplyTrackSchemaV7.models`.
- Supports iCloud-backed mode (`useCloudKitPersistence`) with local fallback.
- Handles persistence failure recovery:
  - ensures app support directory
  - creates backup snapshots
  - removes stale SQLite sidecars
  - retries local container creation
- Exposes `PersistenceStatus` via environment.

## Schema and Migration

Current active schema:

- `SimplyTrackSchemaV7` (`Schema.Version(7, 0, 0)`)

Historical versions retained for migration:

- `SimplyTrackSchemaV1` through `SimplyTrackSchemaV6`

Migration helpers:

- `SimplyTrackMigrationPlan.swift` contains compatibility aliases.
- `SimplyTrackSchemaV7.swift` contains V6 deduplication helper logic used by tests and migration-oriented checks.

## Test Coverage Snapshot

Primary tests are in `simply-trackTests/simply_trackTests.swift` and cover:

- V6 duplicate-resolution heuristics for entries, catalog items, and profiles.
- Week-range boundary semantics.
- Daily/weekly aggregation behavior.
- Weekly status/progress consistency.
- TDEE equation calculations and weight-loss floor behavior.

Most recent run in this workspace context: 8 passed, 0 failed.

## Operational Notes

- Keep all week-based calculations aligned to `CalorieSummaryCalculator.weekRange(...)`.
- Keep burn-adjusted max logic symmetric between daily and weekly UI.
- Avoid duplicating nutrition math in views; prefer model/service methods.
- If schema model fields change, update tests and docs in the same PR.

---

Last updated: October 2026
Active schema version: 7.0.0
