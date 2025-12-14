# Changelog
All notable changes to **@flomentumsolutions/capacitor-health-extended** will be documented in this file.  
This project adheres to [Semantic Versioning](https://semver.org/) and the
[Keep a Changelog](https://keepachangelog.com/) style guide.

---

## [0.4.5] – Unreleased  
### Fixed
- SwiftPM/Xcode builds now declare the Cordova binary target alongside Capacitor so the module resolves correctly.
- iOS latest sleep query now gates new sleep stages to iOS 16+ and falls back to the legacy `asleep` value on earlier OS versions, avoiding missing symbol errors.
- Daily bucket end-date calculation now uses `Calendar.Component.day` to advance one full day, fixing the build error and keeping day buckets aligned.

### Security
- None

---

## [0.4.4] – 2025-12-15  
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
