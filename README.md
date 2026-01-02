# @flomentumsolutions/capacitor-health-extended

Cross‑platform Capacitor plugin for reading data from Apple HealthKit and
Google Health Connect. The plugin requires **Node.js 22+** and is compatible
with **Capacitor 8**. For iOS the plugin ships a **Swift Package Manager**
distribution (Capacitor 8 default), while the CocoaPods spec
`FlomentumsolutionsCapacitorHealthExtended` remains for legacy projects.

## Thanks and attribution

Forked from [capacitor-health](https://github.com/mley/capacitor-health) and as such...
- Some parts, concepts and ideas are borrowed from [cordova-plugin-health](https://github.com/dariosalvi78/cordova-plugin-health/).
- Big thanks to [@dariosalvi78](https://github.com/dariosalvi78) for the support.

Thanks [@mley](https://github.com/mley) for the ground work. The goal of this fork is to extend functionality and datapoints and keep up with the ever-changing brand-new Android Health Connect Platform. I'm hoping to create platform parity for capacitor API-based health data access.

## Requirements (Plugin & Consuming Apps)

- Node.js 22+ (Latest LTS version is recommended)
- Capacitor 8
- iOS 15+ (Xcode 26 + HealthKit + SwiftPM toolchain)
- Android 16+ (Android Studio Otter 2025.2.1 + Health Connect 1.2.0-alpha02 + Gradle 8.13.0 + Kotlin 2.2.20)

## Features

- Check if health functionality is available on the device
- Request and verify health permissions
- Query aggregated data like steps or calories
- Retrieve workout sessions with optional route and heart rate data
- Create workout sessions (e.g., rock climbing) with totals, optional routes, and heart-rate samples (write APIs)
- Fetch the latest samples for steps, distance (incl. cycling), calories (active/total/basal), heart‑rate, resting HR, HRV, respiratory rate, blood pressure, oxygen saturation, blood glucose, body temperature (basal + core), body fat, height, weight, flights climbed, sleep (incl. REM duration), and exercise time.
- Read profile characteristics on iOS: biological sex, blood type, date of birth, Fitzpatrick skin type, wheelchair use.

### Supported data types (parity iOS + Android)
- Activity: steps, distance, distance‑cycling, exercise time (Apple Exercise Time), workouts (with routes/steps/calories), flights climbed
- Energy: active calories, total calories, basal calories
- Vitals: heart rate, resting heart rate, HRV, respiratory rate, blood pressure, oxygen saturation, blood glucose, body temperature, basal body temperature
- Body: weight, height, body fat
- Characteristics (iOS): biological sex, blood type, date of birth, Fitzpatrick skin type, wheelchair use
- Sessions: mindfulness, sleep, sleep REM (latest sample only)

## Install

```bash
npm install @flomentumsolutions/capacitor-health-extended
npx cap sync
```

## Setup Consuming Apps

### iOS

Capacitor 8 resolves iOS plugins via SwiftPM. Running `npx cap sync ios` will
add the `FlomentumSolutionsCapacitorHealthExtended` package (backed by
`capacitor-swift-pm`) to your Xcode project. If you are pinned to Capacitor 7,
you can keep using the CocoaPods spec `FlomentumSolutionsCapacitorHealthExtended`.

* Make sure your app id has the 'HealthKit' entitlement when this plugin is installed (see iOS dev center).
* Also, make sure your app and App Store description comply with the Apple review guidelines.
* There are two keys to be added to the info.plist file: NSHealthShareUsageDescription and NSHealthUpdateUsageDescription.
* Request WRITE_* permissions with `requestHealthPermissions` to enable saving workouts/energy/distance/routes/heart-rate samples to HealthKit.

### Android

* Android Manifest in root tag right after opening manifest tag
```xml
    <!-- Make Health Connect visible to detect installation -->
    <queries>
        <package android:name="com.google.android.apps.healthdata" />
    </queries>

    <!-- Declare permissions you’ll request -->
    <uses-permission android:name="android.permission.health.READ_STEPS" />
    <uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.READ_TOTAL_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.READ_DISTANCE" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE" />
    <uses-permission android:name="android.permission.health.READ_EXERCISE_ROUTE" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_WEIGHT" />
    <uses-permission android:name="android.permission.health.READ_HEIGHT" />
    <uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY" />
    <uses-permission android:name="android.permission.health.READ_BLOOD_PRESSURE" />
    <uses-permission android:name="android.permission.health.READ_MINDFULNESS" />
    <uses-permission android:name="android.permission.health.READ_RESTING_HEART_RATE" />
    <uses-permission android:name="android.permission.health.READ_RESPIRATORY_RATE" />
    <uses-permission android:name="android.permission.health.READ_OXYGEN_SATURATION" />
    <uses-permission android:name="android.permission.health.READ_BLOOD_GLUCOSE" />
    <uses-permission android:name="android.permission.health.READ_BODY_TEMPERATURE" />
    <uses-permission android:name="android.permission.health.READ_BASAL_BODY_TEMPERATURE" />
    <uses-permission android:name="android.permission.health.READ_BODY_FAT" />
    <uses-permission android:name="android.permission.health.READ_FLOORS_CLIMBED" />
    <uses-permission android:name="android.permission.health.READ_BASAL_METABOLIC_RATE" />
    <uses-permission android:name="android.permission.health.READ_SLEEP" />
    <uses-permission android:name="android.permission.health.WRITE_EXERCISE" />
    <uses-permission android:name="android.permission.health.WRITE_ACTIVE_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.WRITE_TOTAL_CALORIES_BURNED" />
    <uses-permission android:name="android.permission.health.WRITE_DISTANCE" />
    <uses-permission android:name="android.permission.health.WRITE_HEART_RATE" />
    <uses-permission android:name="android.permission.health.WRITE_EXERCISE_ROUTE" />
```

Include the WRITE_* entries when you call `saveWorkout` to insert exercise sessions, energy, distance, routes, or heart rate samples.

* Android Manifest in application tag
```xml
    <!-- Handle Health Connect rationale (Android 13-) -->
    <activity
        android:name=".PermissionsRationaleActivity"
        android:exported="true">
        <intent-filter>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE"/>
            <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
        </intent-filter>
    </activity>

    <!-- Handle Android 14+ alias -->
    <activity-alias
        android:name="ViewPermissionUsageActivity"
        android:exported="true"
        android:targetActivity=".PermissionsRationaleActivity"
        android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
        <intent-filter>
            <action android:name="android.intent.action.VIEW_PERMISSION_USAGE"/>
            <category android:name="android.intent.category.HEALTH_PERMISSIONS"/>
        </intent-filter>
    </activity-alias>
```

* Android Manifest in application tag for secure WebView content
```xml
    <!-- Configure secure WebView and allow HTTPS loading -->
    <application
        android:usesCleartextTraffic="false"
        android:networkSecurityConfig="@xml/network_security_config">
        ...
    </application>
```

* Create `com.my.app.PermissionsRationaleActivity.kt` with:
```xml
package com.my.app

import android.os.Bundle
import android.util.Log
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.addCallback
import androidx.appcompat.app.AppCompatActivity

class PermissionsRationaleActivity : AppCompatActivity() {
    private lateinit var webView: WebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        supportActionBar?.apply {
            title = "Privacy Policy"
            setDisplayHomeAsUpEnabled(true)
        }

        webView = WebView(this).apply {
            settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                useWideViewPort = true
                loadWithOverviewMode = true
            }
            webChromeClient = WebChromeClient()
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: android.webkit.WebResourceRequest) = false
                override fun onReceivedError(
                    view: WebView,
                    request: android.webkit.WebResourceRequest,
                    error: android.webkit.WebResourceError
                ) {
                    Log.e("WebView", "Failed to load: ${error.description}")
                }
                override fun onPageFinished(view: WebView, url: String) {
                    Log.d("WebView", "Loaded: $url")
                }
            }
            loadUrl("https://mywebsite.com/privacy-policy")
        }

        setContentView(webView)

        // Device back button behavior
        onBackPressedDispatcher.addCallback(this) {
            finish()
        }
    }

    // Toolbar Up button behavior
    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}
```

* Create `res/xml/network_security_config.xml` with:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false">
    <trust-anchors>
      <certificates src="system"/>
    </trust-anchors>
  </base-config>
</network-security-config>
```

This setup ensures your WebView will load HTTPS content securely and complies with Android's default network security policy.

## API
```
<docgen-index>

* [`isHealthAvailable()`](#ishealthavailable)
* [`checkHealthPermissions(...)`](#checkhealthpermissions)
* [`requestHealthPermissions(...)`](#requesthealthpermissions)
* [`openAppleHealthSettings()`](#openapplehealthsettings)
* [`openHealthConnectSettings()`](#openhealthconnectsettings)
* [`showHealthConnectInPlayStore()`](#showhealthconnectinplaystore)
* [`getCharacteristics()`](#getcharacteristics)
* [`queryAggregated(...)`](#queryaggregated)
* [`queryWorkouts(...)`](#queryworkouts)
* [`queryLatestSample(...)`](#querylatestsample)
* [`queryWeight()`](#queryweight)
* [`queryHeight()`](#queryheight)
* [`queryHeartRate()`](#queryheartrate)
* [`querySteps()`](#querysteps)
* [`saveWorkout(...)`](#saveworkout)
* [Interfaces](#interfaces)
* [Type Aliases](#type-aliases)

</docgen-index>
```
<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### isHealthAvailable()

```typescript
isHealthAvailable() => Promise<{ available: boolean; }>
```

Checks if health API is available.
Android: If false is returned, the Google Health Connect app is probably not installed.
See showHealthConnectInPlayStore()

**Returns:** <code>Promise&lt;{ available: boolean; }&gt;</code>

--------------------


### checkHealthPermissions(...)

```typescript
checkHealthPermissions(permissions: PermissionsRequest) => Promise<PermissionResponse>
```

Android only: Returns for each given permission, if it was granted by the underlying health API

| Param             | Type                                                              | Description          |
| ----------------- | ----------------------------------------------------------------- | -------------------- |
| **`permissions`** | <code><a href="#permissionsrequest">PermissionsRequest</a></code> | permissions to query |

**Returns:** <code>Promise&lt;<a href="#permissionresponse">PermissionResponse</a>&gt;</code>

--------------------


### requestHealthPermissions(...)

```typescript
requestHealthPermissions(permissions: PermissionsRequest) => Promise<PermissionResponse>
```

Requests the permissions from the user.

Android: Apps can ask only a few times for permissions, after that the user has to grant them manually in
the Health Connect app. See openHealthConnectSettings()

iOS: If the permissions are already granted or denied, this method will just return without asking the user. In iOS
we can't really detect if a user granted or denied a permission. The return value reflects the assumption that all
permissions were granted.

| Param             | Type                                                              | Description            |
| ----------------- | ----------------------------------------------------------------- | ---------------------- |
| **`permissions`** | <code><a href="#permissionsrequest">PermissionsRequest</a></code> | permissions to request |

**Returns:** <code>Promise&lt;<a href="#permissionresponse">PermissionResponse</a>&gt;</code>

--------------------


### openAppleHealthSettings()

```typescript
openAppleHealthSettings() => Promise<void>
```

Opens the apps settings, which is kind of wrong, because health permissions are configured under:
Settings &gt; Apps &gt; (Apple) Health &gt; Access and Devices &gt; [app-name]
But we can't go there directly.

--------------------


### openHealthConnectSettings()

```typescript
openHealthConnectSettings() => Promise<void>
```

Opens the Google Health Connect app

--------------------


### showHealthConnectInPlayStore()

```typescript
showHealthConnectInPlayStore() => Promise<void>
```

Opens the Google Health Connect app in PlayStore

--------------------


### getCharacteristics()

```typescript
getCharacteristics() => Promise<CharacteristicsResponse>
```

iOS only: Reads user characteristics such as biological sex, blood type, date of birth, Fitzpatrick skin type, and wheelchair use.
Values are null when unavailable or permission was not granted. Android does not expose these characteristics; it returns `platformSupported: false` and a `platformMessage` for UI hints without emitting null values.

**Returns:** <code>Promise&lt;<a href="#characteristicsresponse">CharacteristicsResponse</a>&gt;</code>

--------------------


### queryAggregated(...)

```typescript
queryAggregated(request: QueryAggregatedRequest) => Promise<QueryAggregatedResponse>
```

Query aggregated data
- Blood-pressure aggregates return the systolic average in `value` plus `systolic`, `diastolic`, and `unit`.
- `total-calories` is derived as active + basal energy on both iOS and Android for latest samples, aggregated queries, and workouts. We fall back to the platform's total‑calories metric (or active calories) when basal data isn't available or permission is missing. Request both `READ_ACTIVE_CALORIES` and `READ_BASAL_CALORIES` for full totals.
- Weight/height aggregation returns the latest sample per day (no averaging).
- Android aggregation currently supports daily buckets; unsupported buckets will be rejected.
- Android `distance-cycling` aggregates distance recorded during biking exercise sessions (requires distance + workouts permissions).
- Daily `bucket: "day"` queries use calendar-day boundaries in the device time zone (start-of-day through the next start-of-day) instead of a trailing 24-hour window. For “today,” send `startDate` at today’s start-of-day and `endDate` at now or tomorrow’s start-of-day.

| Param         | Type                                                                      |
| ------------- | ------------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryaggregatedrequest">QueryAggregatedRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryaggregatedresponse">QueryAggregatedResponse</a>&gt;</code>

--------------------


### queryWorkouts(...)

```typescript
queryWorkouts(request: QueryWorkoutRequest) => Promise<QueryWorkoutResponse>
```

Query workouts

| Param         | Type                                                                |
| ------------- | ------------------------------------------------------------------- |
| **`request`** | <code><a href="#queryworkoutrequest">QueryWorkoutRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#queryworkoutresponse">QueryWorkoutResponse</a>&gt;</code>

--------------------


### queryLatestSample(...)

```typescript
queryLatestSample(request: { dataType: LatestDataType; }) => Promise<QueryLatestSampleResponse>
```

Query latest sample for a specific data type
- Latest sleep sample returns the most recent complete sleep session (asleep states only) from the last ~36 hours; if a longer overnight session exists, shorter naps are ignored.
- `sleep-rem` returns REM duration (minutes) for the latest sleep session; requires iOS 16+ sleep stages and Health Connect REM data on Android.

| Param         | Type                                                                     |
| ------------- | ------------------------------------------------------------------------ |
| **`request`** | <code>{ dataType: <a href="#latestdatatype">LatestDataType</a>; }</code> |

**Returns:** <code>Promise&lt;<a href="#querylatestsampleresponse">QueryLatestSampleResponse</a>&gt;</code>

--------------------


### queryWeight()

```typescript
queryWeight() => Promise<QueryLatestSampleResponse>
```

Query latest weight sample

**Returns:** <code>Promise&lt;<a href="#querylatestsampleresponse">QueryLatestSampleResponse</a>&gt;</code>

--------------------


### queryHeight()

```typescript
queryHeight() => Promise<QueryLatestSampleResponse>
```

Query latest height sample

**Returns:** <code>Promise&lt;<a href="#querylatestsampleresponse">QueryLatestSampleResponse</a>&gt;</code>

--------------------


### queryHeartRate()

```typescript
queryHeartRate() => Promise<QueryLatestSampleResponse>
```

Query latest heart rate sample

**Returns:** <code>Promise&lt;<a href="#querylatestsampleresponse">QueryLatestSampleResponse</a>&gt;</code>

--------------------


### querySteps()

```typescript
querySteps() => Promise<QueryLatestSampleResponse>
```

Query latest steps sample

**Returns:** <code>Promise&lt;<a href="#querylatestsampleresponse">QueryLatestSampleResponse</a>&gt;</code>

--------------------


### saveWorkout(...)

```typescript
saveWorkout(request: SaveWorkoutRequest) => Promise<SaveWorkoutResponse>
```

Create a workout session with optional totals and route/heart-rate samples.
- iOS stores an `HKWorkout` (activityType mapped from `activityType`) with total energy/distance and optional metadata/route/heart-rate samples.
- Android stores an `ExerciseSessionRecord` plus `ActiveCaloriesBurnedRecord`, `DistanceRecord`, and `HeartRateRecord` when provided. Routes are attached via `ExerciseRoute`.
- Requires matching WRITE_* permissions for the values you include (e.g., WRITE_WORKOUTS + WRITE_ACTIVE_CALORIES + WRITE_DISTANCE + WRITE_HEART_RATE + WRITE_ROUTE).

| Param         | Type                                                              |
| ------------- | ----------------------------------------------------------------- |
| **`request`** | <code><a href="#saveworkoutrequest">SaveWorkoutRequest</a></code> |

**Returns:** <code>Promise&lt;<a href="#saveworkoutresponse">SaveWorkoutResponse</a>&gt;</code>

--------------------


### Interfaces


#### PermissionResponse

| Prop              | Type                                                                                                       |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| **`permissions`** | <code><a href="#record">Record</a>&lt;<a href="#healthpermission">HealthPermission</a>, boolean&gt;</code> |


#### PermissionsRequest

| Prop              | Type                            |
| ----------------- | ------------------------------- |
| **`permissions`** | <code>HealthPermission[]</code> |


#### CharacteristicsResponse

| Prop                      | Type                                                                                    | Description                                                                                                                             |
| ------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **`biologicalSex`**       | <code><a href="#healthbiologicalsex">HealthBiologicalSex</a> \| null</code>             |                                                                                                                                         |
| **`bloodType`**           | <code><a href="#healthbloodtype">HealthBloodType</a> \| null</code>                     |                                                                                                                                         |
| **`dateOfBirth`**         | <code>string \| null</code>                                                             |                                                                                                                                         |
| **`fitzpatrickSkinType`** | <code><a href="#healthfitzpatrickskintype">HealthFitzpatrickSkinType</a> \| null</code> |                                                                                                                                         |
| **`wheelchairUse`**       | <code><a href="#healthwheelchairuse">HealthWheelchairUse</a> \| null</code>             |                                                                                                                                         |
| **`platformSupported`**   | <code>boolean</code>                                                                    | Indicates whether the platform exposes these characteristics via the plugin (true on iOS, false on Android).                            |
| **`platformMessage`**     | <code>string</code>                                                                     | Optional platform-specific message; on Android we return a user-facing note explaining that values remain empty unless synced from iOS. |


#### QueryAggregatedResponse

| Prop                 | Type                            |
| -------------------- | ------------------------------- |
| **`aggregatedData`** | <code>AggregatedSample[]</code> |


#### AggregatedSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`startDate`** | <code>string</code> |
| **`endDate`**   | <code>string</code> |
| **`value`**     | <code>number</code> |
| **`systolic`**  | <code>number</code> |
| **`diastolic`** | <code>number</code> |
| **`unit`**      | <code>string</code> |


#### QueryAggregatedRequest

| Prop            | Type                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`startDate`** | <code>string</code>                                                                                                                                                                                                                                                                                                                                                                                                    |
| **`endDate`**   | <code>string</code>                                                                                                                                                                                                                                                                                                                                                                                                    |
| **`dataType`**  | <code>'steps' \| 'active-calories' \| 'total-calories' \| 'basal-calories' \| 'distance' \| 'weight' \| 'height' \| 'heart-rate' \| 'resting-heart-rate' \| 'respiratory-rate' \| 'oxygen-saturation' \| 'blood-glucose' \| 'body-temperature' \| 'basal-body-temperature' \| 'body-fat' \| 'flights-climbed' \| 'exercise-time' \| 'distance-cycling' \| 'mindfulness' \| 'sleep' \| 'hrv' \| 'blood-pressure'</code> |
| **`bucket`**    | <code>string</code>                                                                                                                                                                                                                                                                                                                                                                                                    |


#### QueryWorkoutResponse

| Prop           | Type                   |
| -------------- | ---------------------- |
| **`workouts`** | <code>Workout[]</code> |


#### Workout

| Prop                 | Type                           |
| -------------------- | ------------------------------ |
| **`startDate`**      | <code>string</code>            |
| **`endDate`**        | <code>string</code>            |
| **`workoutType`**    | <code>string</code>            |
| **`sourceName`**     | <code>string</code>            |
| **`id`**             | <code>string</code>            |
| **`duration`**       | <code>number</code>            |
| **`distance`**       | <code>number</code>            |
| **`steps`**          | <code>number</code>            |
| **`calories`**       | <code>number</code>            |
| **`sourceBundleId`** | <code>string</code>            |
| **`route`**          | <code>RouteSample[]</code>     |
| **`heartRate`**      | <code>HeartRateSample[]</code> |


#### RouteSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`timestamp`** | <code>string</code> |
| **`lat`**       | <code>number</code> |
| **`lng`**       | <code>number</code> |
| **`alt`**       | <code>number</code> |


#### HeartRateSample

| Prop            | Type                |
| --------------- | ------------------- |
| **`timestamp`** | <code>string</code> |
| **`bpm`**       | <code>number</code> |


#### QueryWorkoutRequest

| Prop                   | Type                 |
| ---------------------- | -------------------- |
| **`startDate`**        | <code>string</code>  |
| **`endDate`**          | <code>string</code>  |
| **`includeHeartRate`** | <code>boolean</code> |
| **`includeRoute`**     | <code>boolean</code> |
| **`includeSteps`**     | <code>boolean</code> |


#### QueryLatestSampleResponse

| Prop               | Type                                                             |
| ------------------ | ---------------------------------------------------------------- |
| **`value`**        | <code>number</code>                                              |
| **`systolic`**     | <code>number</code>                                              |
| **`diastolic`**    | <code>number</code>                                              |
| **`timestamp`**    | <code>number</code>                                              |
| **`endTimestamp`** | <code>number</code>                                              |
| **`unit`**         | <code>string</code>                                              |
| **`metadata`**     | <code><a href="#record">Record</a>&lt;string, unknown&gt;</code> |


#### SaveWorkoutResponse

| Prop          | Type                 |
| ------------- | -------------------- |
| **`success`** | <code>boolean</code> |
| **`id`**      | <code>string</code>  |


#### SaveWorkoutRequest

| Prop                   | Type                                                                |
| ---------------------- | ------------------------------------------------------------------- |
| **`activityType`**     | <code><a href="#workoutactivitytype">WorkoutActivityType</a></code> |
| **`startDate`**        | <code>string</code>                                                 |
| **`endDate`**          | <code>string</code>                                                 |
| **`calories`**         | <code>number</code>                                                 |
| **`distance`**         | <code>number</code>                                                 |
| **`metadata`**         | <code><a href="#record">Record</a>&lt;string, any&gt;</code>        |
| **`route`**            | <code>RouteSample[]</code>                                          |
| **`heartRateSamples`** | <code>HeartRateSample[]</code>                                      |


### Type Aliases


#### Record

Construct a type with a set of properties K of type T

<code>{ [P in K]: T; }</code>


#### HealthPermission

<code>'READ_STEPS' | 'READ_WORKOUTS' | 'WRITE_WORKOUTS' | 'READ_ACTIVE_CALORIES' | 'WRITE_ACTIVE_CALORIES' | 'READ_TOTAL_CALORIES' | 'WRITE_TOTAL_CALORIES' | 'READ_DISTANCE' | 'WRITE_DISTANCE' | 'READ_WEIGHT' | 'READ_HEIGHT' | 'READ_HEART_RATE' | 'WRITE_HEART_RATE' | 'READ_RESTING_HEART_RATE' | 'READ_ROUTE' | 'WRITE_ROUTE' | 'READ_MINDFULNESS' | 'READ_HRV' | 'READ_BLOOD_PRESSURE' | 'READ_BASAL_CALORIES' | 'READ_RESPIRATORY_RATE' | 'READ_OXYGEN_SATURATION' | 'READ_BLOOD_GLUCOSE' | 'READ_BODY_TEMPERATURE' | 'READ_BASAL_BODY_TEMPERATURE' | 'READ_BODY_FAT' | 'READ_FLOORS_CLIMBED' | 'READ_SLEEP' | 'READ_EXERCISE_TIME' | 'READ_BIOLOGICAL_SEX' | 'READ_BLOOD_TYPE' | 'READ_DATE_OF_BIRTH' | 'READ_FITZPATRICK_SKIN_TYPE' | 'READ_WHEELCHAIR_USE'</code>


#### HealthBiologicalSex

<code>'female' | 'male' | 'other' | 'not_set' | 'unknown'</code>


#### HealthBloodType

<code>'a-positive' | 'a-negative' | 'b-positive' | 'b-negative' | 'ab-positive' | 'ab-negative' | 'o-positive' | 'o-negative' | 'not_set' | 'unknown'</code>


#### HealthFitzpatrickSkinType

<code>'type1' | 'type2' | 'type3' | 'type4' | 'type5' | 'type6' | 'not_set' | 'unknown'</code>


#### HealthWheelchairUse

<code>'wheelchair_user' | 'not_wheelchair_user' | 'not_set' | 'unknown'</code>


#### LatestDataType

<code>'steps' | 'active-calories' | 'total-calories' | 'basal-calories' | 'distance' | 'weight' | 'height' | 'heart-rate' | 'resting-heart-rate' | 'respiratory-rate' | 'oxygen-saturation' | 'blood-glucose' | 'body-temperature' | 'basal-body-temperature' | 'body-fat' | 'flights-climbed' | 'exercise-time' | 'distance-cycling' | 'mindfulness' | 'sleep' | 'sleep-rem' | 'hrv' | 'blood-pressure'</code>


#### WorkoutActivityType

<code>'rock-climbing' | 'climbing' | 'hiking' | 'running' | 'walking' | 'cycling' | 'biking' | 'strength-training' | 'yoga' | 'other'</code>

</docgen-api>
