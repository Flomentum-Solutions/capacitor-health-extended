# Changelog
All notable changes to **@flomentumsolutions/capacitor-health-extended** will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/) style guide.

---

## [0.8.1] – 2026-01-14
### Added
- None

### Fixed
- iOS `saveMetrics` now requests read access for the same metric types when asking for write authorization, preventing read permissions from being dropped after a write prompt.

### Security
- None

---

## [0.8.0] – 2026-01-14
### Added
- Documentation note and TypeScript helper snippet for iOS optimistic read permissions, plus guidance to show a "no data" hint when queries return empty.

### Changed
- iOS `checkHealthPermissions` now reports write permissions strictly and read permissions optimistically for sample types, returning false only when the read permission is not determined; invalid permission strings return false.

### Security
- None

---

## [0.7.7] – 2026-01-12
### Added
- None

### Fixed
- iOS now implements the `queryWeight()`/`queryHeight()` helpers (plus `queryHeartRate()`/`querySteps()`), keeping latest-sample convenience queries in sync with Android and avoiding missing weight updates.
- iOS now exposes `openHealthConnectSettings()` (aliasing `openAppleHealthSettings()`) and `showHealthConnectInPlayStore()` (no-op) for API parity.

### Security
- None

---

## [0.7.6] – 2026-01-05
### Added
- None

### Fixed
- Android `getCharacteristics` stub now uses a safe string template so interpolation renders correctly without tripping Kotlin parsing.

### Security
- None

---

## [0.7.5] - 2026-01-04
### Added
- `getCharacteristics` accepts an optional `fields` filter to request individual characteristics and narrow required permissions.

### Fixed
- None

### Security
- None

---

## [0.7.4] – 2026-01-04
### Added
- None

### Fixed
- iOS `requestHealthPermissions` no longer requests write/share authorization when only read permissions are provided (avoids Info.plist `NSHealthUpdateUsageDescription` crash); write permissions for weight/height/body fat/resting heart rate now map explicitly to share types.

### Security
- None

---

## [0.7.3] – 2026-01-03
### Added
- None

### Fixed
- Android package/namespace now matches the plugin id so source files live under the correct `com.flomentumsolutions.capacitorhealthextended` path (no hyphen).

### Security
- None

---

## [0.7.1 & 0.7.2] – 2026-01-03
### Added
- `saveMetrics()` to write manual health metrics (weight, height, body fat %, resting heart rate) to HealthKit and Health Connect with manual-entry metadata.
- WRITE permissions for weight/height/body fat/resting heart rate exposed in the API so apps can request them before saving metrics.

### Fixed
- None

### Security
- None

---

## [0.7.0] – 2026-01-02
### Added
- New `saveWorkout()` API to create workouts with optional totals, routes, and heart-rate samples on iOS and Android.
- WRITE_* permissions for workouts, calories, distance, routes, and heart rate added to the API and Android manifest guidance so apps can request/write data.

### Fixed
- None

### Security
- None

---

## [0.6.4] – 2025-12-17
### Added
- `sleep-rem` latest-sample data type to return REM duration minutes for the most recent sleep session (iOS 16+ sleep stages; Android Health Connect REM stages).

### Fixed
- None

### Security
- None

---

## [0.6.3] – 2025-12-15
### Fixed
- iOS now requests HealthKit characteristic permissions and fallsback gracefully

### Security
- None

---

## [0.6.2] – 2025-12-15
### Fixed
- iOS now requests HealthKit characteristic permissions on the main thread so the authorization sheet appears reliably.
- `getCharacteristics()` proactively requests characteristic access and returns a platform message when not granted instead of an empty unsupported notice.

### Security
- None

---

## [0.6.0] – 2025-12-15
### Added
- New `getCharacteristics()` API on iOS to read biological sex, blood type, date of birth, Fitzpatrick skin type, and wheelchair use, plus new characteristic permission constants and TypeScript enums.
- Android scaffolding for characteristics now returns `platformSupported: false` alongside a user-facing `platformMessage` instead of null data, so UIs can show the empty-state note for Android-only users while still accepting data synced from iOS.

### Fixed
- SwiftPM/Xcode builds now declare the Cordova binary target alongside Capacitor so the module resolves correctly.
- iOS latest sleep query now gates new sleep stages to iOS 16+ and falls back to the legacy `asleep` value on earlier OS versions, avoiding missing symbol errors.
- Daily bucket end-date calculation now uses `Calendar.Component.day` to advance one full day, fixing the build error and keeping day buckets aligned.

### Security
- None

---

## [0.4.4] – 2025-12-14
### Fixed
- `total-calories` now correctly derives active + basal energy on both iOS and Android for latest samples, aggregated queries, and workouts; falls back to the platform total or active calories when basal data/permission is unavailable.
- Latest sleep sample on iOS now returns the most recent complete sleep session (asleep states only) within the last 36 hours and ignores in-bed/awake noise to avoid inflated durations.

### Security
- None

---

## [0.4.0] – 2025-12-13  
### Changed
- Daily aggregated queries now align to local calendar days (start-of-day to end-of-day) instead of a trailing 24-hour window so “today” matches Health app totals.
- Documentation refreshed to call out the calendar-day bucket behavior for querying current-day values.

### Security
- None

---

## [0.3.0] – 2025-12-13  
### Added
- New cross-platform health types: resting heart rate, respiratory rate, oxygen saturation, blood glucose, body temperature (core + basal), body fat, basal calories, flights climbed, cycling distance, exercise time, and sleep sessions.
- Android Health Connect permissions added for the new types, plus aggregation helpers for sleep/exercise time and floor counts.
- iOS HealthKit mappings for the new quantities and sleep/latest queries with start/end timestamps.
- Mindfulness now uses the dedicated MindfulnessSession record on Android (no longer reusing SleepSession) and the native `mindfulSession` category on iOS for latest samples.

### Security
- None

---

## [0.2.0] – 2025-12-13  
### Added
- Swift Package Manager distribution for Capacitor 8 iOS builds (via `Package.swift` + `capacitor-swift-pm`).

### Changed
- Peer dependency raised to Capacitor 8; toolchains updated to Swift 5.9/Xcode 15 and Android AGP 8.13 + Kotlin 2.2 (SDK 36 defaults).
- HealthKit aggregation switch now covers new discrete aggregation styles to stay compatible with recent iOS releases.

### Fixed
- Workout queries now serialize heart-rate, route, and step aggregation to avoid races when building results.

### Security
- None

---

## [1.0.0] – 2025-07-18  
### Added
- **New Health types (iOS + Android)**  
  `HEIGHT`, `BODY_WEIGHT`, `HR_VARIABILITY_SDNN`, `BLOOD_PRESSURE_SYSTOLIC/ DIASTOLIC`,  
  `ACTIVE_ENERGY_BURNED`, `BASAL_ENERGY_BURNED`, `TOTAL_CALORIES`, `DISTANCE_TOTAL`,  
  `MINDFULNESS_SESSION`
- **Permission constants**  
  `READ_WEIGHT`, `READ_HEIGHT`, `READ_HRV`, `READ_BLOOD_PRESSURE`,  
  `READ_ACTIVE_CALORIES`, `READ_TOTAL_CALORIES`, `READ_MINDFULNESS`
- **Route & step support**  
  – iOS: returns workout routes (lat/lng/alt) with thread-safe aggregation  
  – Android: updated to Health Connect 1.2 multi-segment Route API  
  – Optional step-count per workout (queried & summed on both platforms)  
- **Swift 6 / Kotlin 1.9 compatibility**  
  App builds clean on Xcode 16, Android API 34, Node 20, Capacitor 7  
- **GitHub Actions CI**: lint, iOS build (macOS), Android build (Linux), test matrix
- **Docs**: full permission matrix, setup for Capacitor 7, Node 20, Health Connect entitlements

### Changed
- **Capacitor core bumped** to peer-dependency `^7`  
- **iOS**  
  – Whole plugin annotated `@MainActor`  
  – Concurrency-safe `routeSyncQueue` (serial queue replaces `NSLock`)  
  – Simplified aggregation-style switch (uses `.cumulativeSum`/`.discreteAverage`)  
  – Static `identifier`, `jsName`, `pluginMethods` satisfy `CAPBridgedPlugin`  
- **Android**  
  – `compileSdk` => 34, `minSdk` => 26, Kotlin 1.9.x  
  – Calorie aggregation now combines active + basal energy  
  – Distance uses `TOTAL_DISTANCE` not just walking/running  
- **Build tooling**  
  – CocoaPods remains primary (SPM stubs removed)  
  – `podspec` updated (`Capacitor`, `CapacitorCordova`, `swift_version = 6.0`)  
- **LICENSE** now lists dual copyright (see below)

### Fixed
- Swift-concurrency compile errors:  
  `Capture of 'call' in @Sendable closure`, `Main actor-isolated property …`  
- Race condition when aggregating route-locations  
- Instant → epoch-millis bug in Android timestamp conversion  
- Aggregated-query crash on unknown `HKQuantityAggregationStyle`

### Removed
- Experimental SwiftPM definition (Capacitor 6 SPM binaries incompatible with Swift 6)

### Security
- None

---

## [0.0.1] – 2022-11-03  
Initial release by **Michael Ley** as [`mley/capacitor-health`](https://github.com/mley/capacitor-health)  
Licensed under MIT.

---

## Attribution
This fork began as <https://github.com/mley/capacitor-health> (MIT).
Significant new features and maintenance © 2025 **Flomentum Solutions, LLC**.
