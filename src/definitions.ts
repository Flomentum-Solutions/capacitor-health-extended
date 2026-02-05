export interface HealthPlugin {
  /**
   * Checks if health API is available.
   * Android: If false is returned, the Google Health Connect app is probably not installed.
   * See showHealthConnectInPlayStore()
   *
   */
  isHealthAvailable(): Promise<{ available: boolean }>;

  /**
   * Returns whether each permission is granted.
   * Android: Uses Health Connect grant state.
   * iOS: Write permissions are strict. Read permissions for sample types are optimistic because HealthKit does not
   * distinguish denied vs no data; this returns false only when the read permission is not determined. For
   * characteristics, this probes access and returns false when denied.
   * UX tip: If this returns true but a query yields no results, show a hint to check Apple Health settings.
   * @param permissions permissions to query
   */
  checkHealthPermissions(permissions: PermissionsRequest): Promise<PermissionResponse>;

  /**
   * Requests the permissions from the user.
   *
   * Android: Apps can ask only a few times for permissions, after that the user has to grant them manually in
   * the Health Connect app. See openHealthConnectSettings()
   *
   * iOS: If the permissions are already granted or denied, this method will just return without asking the user. In iOS
   * we can't really detect if a user granted or denied a permission. The return value reflects the assumption that all
   * permissions were granted.
   *
   * @param permissions permissions to request
   */
  requestHealthPermissions(permissions: PermissionsRequest): Promise<PermissionResponse>;

  /**
   * Opens the apps settings, which is kind of wrong, because health permissions are configured under:
   * Settings > Apps > (Apple) Health > Access and Devices > [app-name]
   * But we can't go there directly.
   */
  openAppleHealthSettings(): Promise<void>;

  /**
   * Opens the Google Health Connect app
   * iOS: Aliases openAppleHealthSettings().
   */
  openHealthConnectSettings(): Promise<void>;

  /**
   * Opens the Google Health Connect app in PlayStore
   * iOS: Resolves without action.
   */
  showHealthConnectInPlayStore(): Promise<void>;

  /**
   * iOS only: Reads user characteristics such as biological sex, blood type, date of birth, Fitzpatrick skin type, and wheelchair use.
   * Values are null when unavailable or permission was not granted. Android does not expose these characteristics; it returns `platformSupported: false` and a `platformMessage` for UI hints without emitting null values.
   *
   * Passing `fields` lets you request only specific characteristics (e.g., date of birth) to keep permissions scoped narrowly. Defaults to all characteristics when omitted.
   */
  getCharacteristics(request?: CharacteristicsRequest): Promise<CharacteristicsResponse>;

  /**
   * Query aggregated data
   * - Blood-pressure aggregates return the systolic average in `value` plus `systolic`, `diastolic`, and `unit`.
   * - `total-calories` is derived as active + basal energy on both iOS and Android for latest samples, aggregated queries, and workouts. We fall back to the platform's total‑calories metric (or active calories) when basal data isn't available or permission is missing. Request both `READ_ACTIVE_CALORIES` and `READ_BASAL_CALORIES` for full totals.
   * - Weight/height aggregation returns the latest sample per day (no averaging).
   * - Android aggregation currently supports daily buckets; unsupported buckets will be rejected.
   * - Android `distance-cycling` aggregates distance recorded during biking exercise sessions (requires distance + workouts permissions).
   * - Daily `bucket: "day"` queries use calendar-day boundaries in the device time zone (start-of-day through the next start-of-day) instead of a trailing 24-hour window. For “today,” send `startDate` at today’s start-of-day and `endDate` at now or tomorrow’s start-of-day.
   * @param request
   */
  queryAggregated(request: QueryAggregatedRequest): Promise<QueryAggregatedResponse>;

  /**
   * Query workouts
   * @param request
   */
  queryWorkouts(request: QueryWorkoutRequest): Promise<QueryWorkoutResponse>;

  /**
   * Query latest sample for a specific data type
   * - Latest sleep sample returns the most recent complete sleep session (asleep states only) from the last ~36 hours; if a longer overnight session exists, shorter naps are ignored.
   * - `sleep-rem` returns REM duration (minutes) for the latest sleep session; requires iOS 16+ sleep stages and Health Connect REM data on Android.
   * @param request
   */
  queryLatestSample(request: { dataType: LatestDataType }): Promise<QueryLatestSampleResponse>;

  /**
   * Query latest weight sample
   * Convenience wrapper around queryLatestSample({ dataType: 'weight' }).
   */
  queryWeight(): Promise<QueryLatestSampleResponse>;

  /**
   * Query latest height sample
   * Convenience wrapper around queryLatestSample({ dataType: 'height' }).
   */
  queryHeight(): Promise<QueryLatestSampleResponse>;

  /**
   * Query latest heart rate sample
   * Convenience wrapper around queryLatestSample({ dataType: 'heart-rate' }).
   */
  queryHeartRate(): Promise<QueryLatestSampleResponse>;

  /**
   * Query latest steps sample
   * Convenience wrapper around queryLatestSample({ dataType: 'steps' }).
   */
  querySteps(): Promise<QueryLatestSampleResponse>;

  /**
   * Create a workout session with optional totals and route/heart-rate samples.
   * - iOS stores an `HKWorkout` (activityType mapped from `activityType`) with total energy/distance and optional metadata/route/heart-rate samples.
   * - Android stores an `ExerciseSessionRecord` plus `ActiveCaloriesBurnedRecord`, `DistanceRecord`, and `HeartRateRecord` when provided. Routes are attached via `ExerciseRoute`.
   * - Requires matching WRITE_* permissions for the values you include (e.g., WRITE_WORKOUTS + WRITE_ACTIVE_CALORIES + WRITE_DISTANCE + WRITE_HEART_RATE + WRITE_ROUTE).
   */
  saveWorkout(request: SaveWorkoutRequest): Promise<SaveWorkoutResponse>;

  /**
   * Save user-provided body metrics to the health platform.
   * iOS: Requests read access for the same metric types when writing to preserve read permissions.
   */
  saveMetrics(request: SaveMetricsRequest): Promise<SaveMetricsResponse>;
}

export declare type HealthPermission = 'READ_STEPS' | 'READ_WORKOUTS' | 'WRITE_WORKOUTS' | 'READ_ACTIVE_CALORIES' | 'WRITE_ACTIVE_CALORIES' | 'READ_TOTAL_CALORIES' | 'WRITE_TOTAL_CALORIES' | 'READ_DISTANCE' | 'WRITE_DISTANCE' | 'READ_WEIGHT' | 'WRITE_WEIGHT' | 'READ_HEIGHT' | 'WRITE_HEIGHT' | 'READ_HEART_RATE' | 'WRITE_HEART_RATE' | 'READ_RESTING_HEART_RATE' | 'WRITE_RESTING_HEART_RATE' | 'READ_ROUTE' | 'WRITE_ROUTE' | 'READ_MINDFULNESS' | 'READ_HRV' | 'READ_BLOOD_PRESSURE' | 'READ_BASAL_CALORIES' | 'READ_RESPIRATORY_RATE' | 'READ_OXYGEN_SATURATION' | 'READ_BLOOD_GLUCOSE' | 'READ_BODY_TEMPERATURE' | 'READ_BASAL_BODY_TEMPERATURE' | 'READ_BODY_FAT' | 'WRITE_BODY_FAT' | 'READ_FLOORS_CLIMBED' | 'READ_SLEEP' | 'READ_EXERCISE_TIME' | 'READ_BIOLOGICAL_SEX' | 'READ_BLOOD_TYPE' | 'READ_DATE_OF_BIRTH' | 'READ_FITZPATRICK_SKIN_TYPE' | 'READ_WHEELCHAIR_USE';

export type LatestDataType =
  | 'steps'
  | 'active-calories'
  | 'total-calories'
  | 'basal-calories'
  | 'distance'
  | 'weight'
  | 'height'
  | 'heart-rate'
  | 'resting-heart-rate'
  | 'respiratory-rate'
  | 'oxygen-saturation'
  | 'blood-glucose'
  | 'body-temperature'
  | 'basal-body-temperature'
  | 'body-fat'
  | 'flights-climbed'
  | 'exercise-time'
  | 'distance-cycling'
  | 'mindfulness'
  | 'sleep'
  | 'sleep-rem'
  | 'hrv'
  | 'blood-pressure';

export interface PermissionsRequest {
  permissions: HealthPermission[];
}

export interface PermissionResponse {
  permissions: Record<HealthPermission, boolean>;
}

export interface QueryWorkoutRequest {
  startDate: string;
  endDate: string;
  includeHeartRate: boolean;
  includeRoute: boolean;
  includeSteps: boolean;
}

export interface HeartRateSample {
  timestamp: string;
  bpm: number;
}

export interface RouteSample {
  timestamp: string;
  lat: number;
  lng: number;
  alt?: number;
}

export interface QueryWorkoutResponse {
  workouts: Workout[];
  errors?: Record<string, string>;
}

export type WorkoutActivityType =
  | 'rock-climbing'
  | 'climbing'
  | 'hiking'
  | 'running'
  | 'walking'
  | 'cycling'
  | 'biking'
  | 'strength-training'
  | 'yoga'
  | 'other';

export interface SaveWorkoutRequest {
  activityType: WorkoutActivityType;
  startDate: string;
  endDate: string;
  calories?: number;
  distance?: number;
  metadata?: Record<string, any>;
  route?: RouteSample[];
  heartRateSamples?: HeartRateSample[];
}

export interface SaveWorkoutResponse {
  success: boolean;
  id?: string;
}

export interface SaveMetricsRequest {
    weightKg?: number;
    heightCm?: number;
    bodyFatPercent?: number;
    restingHeartRate?: number;
}

export interface SaveMetricsResponse {
    success: boolean;
    inserted?: number;
}

export interface Workout {
  startDate: string;
  endDate: string;
  workoutType: string;
  sourceName: string;
  id?: string;
  duration: number;
  distance?: number;
  steps?: number;
  calories: number;
  sourceBundleId: string;
  route?: RouteSample[];
  heartRate?: HeartRateSample[];
}

export interface QueryAggregatedRequest {
  startDate: string;
  endDate: string;
  dataType:
    | 'steps'
    | 'active-calories'
    | 'total-calories'
    | 'basal-calories'
    | 'distance'
    | 'weight'
    | 'height'
    | 'heart-rate'
    | 'resting-heart-rate'
    | 'respiratory-rate'
    | 'oxygen-saturation'
    | 'blood-glucose'
    | 'body-temperature'
    | 'basal-body-temperature'
    | 'body-fat'
    | 'flights-climbed'
    | 'exercise-time'
    | 'distance-cycling'
    | 'sleep'
    | 'mindfulness'
    | 'hrv'
    | 'blood-pressure';
  bucket: string;
}

export interface QueryAggregatedResponse {
  aggregatedData: AggregatedSample[];
}

export interface AggregatedSample {
  startDate: string;
  endDate: string;
  value: number;
  systolic?: number;
  diastolic?: number;
  unit?: string;
}

export interface QueryLatestSampleResponse {
  value?: number;
  systolic?: number;
  diastolic?: number;
  timestamp: number;
  endTimestamp?: number;
  unit: string;
  metadata?: Record<string, unknown>;
}

export interface CharacteristicsResponse {
  biologicalSex?: HealthBiologicalSex | null;
  bloodType?: HealthBloodType | null;
  dateOfBirth?: string | null;
  fitzpatrickSkinType?: HealthFitzpatrickSkinType | null;
  wheelchairUse?: HealthWheelchairUse | null;
  /**
   * Indicates whether the platform exposes these characteristics via the plugin (true on iOS, false on Android).
   */
  platformSupported?: boolean;
  /**
   * Optional platform-specific message; on Android we return a user-facing note explaining that values remain empty unless synced from iOS.
   */
  platformMessage?: string;
}

export type CharacteristicField =
  | 'biologicalSex'
  | 'bloodType'
  | 'dateOfBirth'
  | 'fitzpatrickSkinType'
  | 'wheelchairUse';

export interface CharacteristicsRequest {
  /**
   * Characteristics to query. Defaults to all characteristics when omitted.
   */
  fields?: CharacteristicField[];
}

export type HealthBiologicalSex = 'female' | 'male' | 'other' | 'not_set' | 'unknown';

export type HealthBloodType =
  | 'a-positive'
  | 'a-negative'
  | 'b-positive'
  | 'b-negative'
  | 'ab-positive'
  | 'ab-negative'
  | 'o-positive'
  | 'o-negative'
  | 'not_set'
  | 'unknown';

export type HealthFitzpatrickSkinType = 'type1' | 'type2' | 'type3' | 'type4' | 'type5' | 'type6' | 'not_set' | 'unknown';

export type HealthWheelchairUse = 'wheelchair_user' | 'not_wheelchair_user' | 'not_set' | 'unknown';
