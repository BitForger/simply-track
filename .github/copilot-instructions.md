# GitHub Copilot Instructions — Simply Track

These instructions apply to all code generated or edited in this repository. Read them fully before proposing changes. When instructions conflict with habit or a generic pattern, follow this file.

**Read `AGENTS.md` first.** It is the source of truth for architecture, data flow, and the current schema. Keep `AGENTS.md` and `README.md` accurate when you change structure, persistence, or behavior.

---

## 1. Project Context

- **App:** Simply Track — privacy-first, local-first iOS calorie tracker.
- **Stack:** SwiftUI, SwiftData, Swift concurrency (`async`/`await`), Combine (legacy `@Published` in a few coordinators). No third-party dependencies. No SPM/CocoaPods packages — do not add any without an explicit request.
- **Targets:** Xcode 16+, iOS 18+ deployment target. Write code that uses current APIs; do not guard for OS versions older than the deployment target unless one already exists nearby.
- **Privacy:** On-device first. No analytics, no telemetry, no third-party SDKs, no network calls except what HealthKit/CloudKit already do. HealthKit and notification permissions are optional — features must degrade gracefully when denied.

## 2. Non-Negotiable Engineering Priorities

In order of importance: **reliability → cleanliness → maintainability.** Never trade reliability for cleverness or brevity.

### Reliability

- User data is sacred. Never lose or corrupt entries. All persistence changes must be safe against interruption.
- Never crash on recoverable failure. `preconditionFailure` / `fatalError` / force-unwrap (`!`) / `try!` / `as!` are forbidden in app code unless the failure is genuinely unrecoverable (the existing container-creation fallback in `simply_trackApp.swift` is the model example). Tests may use force unwraps for fixture setup.
- Handle errors explicitly. Surface user-facing failures through observable state (e.g. `syncMessage`, `PersistenceStatus.error`), not silent swallowing and not `print()`-only logging in new code.
- All calorie/week math must be deterministic and testable. Views never contain nutrition math — they call services.

### Cleanliness

- Write idiomatic, modern Swift. Prefer clarity over compactness. No single-letter names, no abbreviations, no `self.` unless required.
- Follow existing naming and formatting. Look at neighboring files before introducing a new style. Match `// MARK: -` usage for logical sections in longer files.
- Keep the file header comment block (`//  FileName.swift //  simply-track //  Created by ...`) pattern used throughout the project.
- No dead code, no commented-out code, no `// TODO` left behind — either do it or track it outside the code.
- No duplicated logic. If a calculation or merge rule exists in a service, call it; never reimplement it inline in a view.

### Maintainability

- Small, focused types and functions. A view that grows beyond ~200 lines should be decomposed into subviews; a function doing more than one thing should be split.
- One type per file, named after the type. New services go in `Services/`, models in `Models/`, top-level views at the target root (matching current layout).
- Prefer dependency injection through initializers over singletons or environment grabs deep in the tree. `Environment` is for app-wide state (`PersistenceStatus`, `ModelContext`) and user preferences, not for hiding service dependencies.
- Every schema, behavior, or structure change updates tests and docs in the same commit/PR.

## 3. Architecture Rules

### Layers and responsibilities

- **Views** (`*View.swift`): rendering and user interaction only. Read state via `@Query`, `@Environment`, `@State`, `@Bindable`, or an injected `@Observable`/coordinator. Trigger side effects through services/coordinators, never inline `HealthKitService` calls from a view.
- **Coordinators / view-facing state** (e.g. `HealthKitSyncCoordinator`): `@MainActor final class`, expose observable state, translate service errors into user-facing messages, own flow control. New ones should use `@Observable` unless they must interop with existing `ObservableObject` code.
- **Services** (`Services/`): pure-ish business logic and platform integration. Calculation services (`CalorieSummaryCalculator`, `StreakCalculator`) are stateless enums/structs with static or instance methods and must be deterministic and unit-testable. Platform services (`HealthKitService`, `ReminderManager`) encapsulate framework calls and return explicit results, not `Bool` alone when failure context matters.
- **Models** (`Models/`): SwiftData `@Model` types live inside versioned schema namespaces. Plain value types (`EntryPayloads`, enums, structs) are used to cross layer boundaries — never pass `@Model` objects into HealthKit or async contexts; convert to payload structs first.

### Concurrency

- Use Swift structured concurrency (`async`/`await`, `Task`) for new code. Do not introduce new Combine usage; Combine exists only where already present.
- Respect actor isolation. UI state lives on `@MainActor`. SwiftData `ModelContext` operations stay on the actor that owns the context; don't capture contexts across `await` boundaries carelessly.
- Long-running or HealthKit work must not block the main thread.

### SwiftUI specifics

- Prefer the observation framework (`@Observable`, `@Bindable`, `@Environment`) for new types over `ObservableObject`/`@Published`/`@StateObject`.
- State ownership: `@State` for private view-local value state; `@Binding` only when the parent genuinely owns the value; avoid `ObservableObject` for simple forms.
- Debounce high-frequency saves (pattern already used in `SettingsView`) — don't save on every keystroke synchronously.
- Keep platform availability checks minimal and centralized (see the "Health app jump" gating in `LogEntriesView`).

## 4. SwiftData & Persistence Rules (highest-risk area)

- **Active schema is `SimplyTrackSchemaV7`.** Never edit a historical schema (`V1`–`V6`) — they are frozen migration snapshots.
- Any model change requires: a **new** `SimplyTrackSchemaVN+1` enum, a migration stage added to `SimplyTrackMigrationPlan`, and container setup in `simply_trackApp.swift` pointed at the new version. Lightweight vs. custom migration must be a deliberate choice, documented in code.
- Never mutate stored properties of a shipped schema version in place.
- All writes go through the shared `ModelContext`; save explicitly after mutations that must persist, and keep save failures observable.
- Follow the startup resilience pattern: backup before destructive recovery, prune backups, degrade CloudKit → local gracefully. Do not add new persistence paths that bypass this.
- Merge/sync logic uses `updatedAt` precedence (read-first, then write). Preserve this invariant; conflicts resolve deterministically.

## 5. Domain Invariants (do not break)

- Week boundaries are a **fixed Sunday-start Gregorian calendar** via `Calendar+GregorianSundayStart` / `CalorieSummaryCalculator.weekRange(...)`. All weekly math funnels through that one implementation.
- Daily/weekly totals, weekly status, progress, and remaining-calorie math come only from `CalorieSummaryCalculator`. Burn-adjusted max logic must stay symmetric between daily and weekly surfaces.
- TDEE/BMR math lives on `UserProfile` (Mifflin-St Jeor default, Harris-Benedict, Katch-McArdle with optional lean body mass). Weight-loss targets respect the safety floor (1200 kcal/day). Do not duplicate these formulas anywhere.
- Entry `source` is `"manual"` or `"healthKit"`; HealthKit-linked entries carry `healthKitSampleIdentifier` for idempotent sync/delete.

## 6. Testing Requirements

- Tests live in `simply-trackTests/simply_trackTests.swift` using **XCTest** (`XCTestCase`, `XCTAssert...`, `@testable import simply_track`). Do not introduce Swift Testing or other frameworks.
- Write tests for: every new calculation, every migration stage, dedup/merge heuristics, and boundary conditions (week edges, empty states, zero targets).
- Use the existing deterministic-date helper pattern (fixed UTC calendar) so tests are timezone-independent.
- Tests must be hermetic: no real HealthKit, no real UserDefaults pollution, no reliance on device locale/timezone.
- Run the full suite after any change touching `Models/`, `Services/`, or schema. All existing tests must keep passing.

## 7. Code Style Quick Reference

- Access control: mark types/members `private` / `private(set)` by default; widen only as needed.
- Prefer `struct` value types; use `final class` only with a reason (identity, reference semantics, framework requirement).
- Enums with `rawValue` storage for persisted string-backed values (pattern: `BiologicalSex`, `TDEEEquation`, `NutritionGoal`, `WeightLossPace`) — never persist raw enum cases or new stringly-typed values without a `rawValue` enum.
- `guard` for early exits; avoid deep nesting.
- Errors: define `LocalizedError` enums with `errorDescription` / `failureReason` / `recoverySuggestion` for user-facing failures (pattern: `PersistenceStatus.PersistenceError`).
- Dates/formatting: use `Date.now`, `.formatted(...)`, and injected `Calendar` — never assume `Calendar.current` in calculations (inject it, as tests do).
- No magic numbers in view logic; named constants (`private static let`) as in `simply_trackApp.swift`.

## 8. What NOT to do

- Do not add third-party packages, analytics, crash reporters, ads, or network calls.
- Do not refactor working code gratuitously; change only what the task requires, plus directly adjacent cleanup.
- Do not rename the project/target (`simply-track` / `simply_track`) or restructure the folder layout without an explicit request.
- Do not weaken error handling, remove fallbacks, or silence failures to make code "cleaner."
- Do not introduce `ObservableObject` in new types, `DispatchQueue` where actors suffice, or completion-handler APIs where `async` fits.
- Do not modify `ci_scripts/`, `Info.plist`, entitlements, or the Xcode project unless the task explicitly requires it — and call it out clearly when you do.

## 9. Definition of Done for any change

1. Compiles cleanly with no new warnings.
2. Follows the layer rules (no math in views, no framework calls leaked into views, payloads across boundaries).
3. New logic covered by XCTest in the existing test bundle.
4. `AGENTS.md` / `README.md` updated if structure, schema, or behavior changed.
5. Privacy posture unchanged (still local-first, still no third parties).
