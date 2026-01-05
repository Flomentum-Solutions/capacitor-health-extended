package com.flomentumsolutions.capacitorhealthextended.capacitor

import android.content.Intent
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.units.kilocalories
import androidx.health.connect.client.units.kilograms
import androidx.health.connect.client.units.meters
import androidx.health.connect.client.units.percent
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicReference
import androidx.core.net.toUri
import kotlin.reflect.KClass

enum class CapHealthPermission {
    READ_STEPS,
    READ_WORKOUTS,
    READ_EXERCISE_TIME,
    READ_HEART_RATE,
    READ_RESTING_HEART_RATE,
    READ_ACTIVE_CALORIES,
    READ_TOTAL_CALORIES,
    READ_DISTANCE,
    READ_WEIGHT,
    READ_HRV,
    READ_BLOOD_PRESSURE,
    READ_HEIGHT,
    READ_ROUTE,
    READ_MINDFULNESS,
    READ_RESPIRATORY_RATE,
    READ_OXYGEN_SATURATION,
    READ_BLOOD_GLUCOSE,
    READ_BODY_TEMPERATURE,
    READ_BASAL_BODY_TEMPERATURE,
    READ_BODY_FAT,
    READ_FLOORS_CLIMBED,
    READ_BASAL_CALORIES,
    READ_SLEEP,
    WRITE_WORKOUTS,
    WRITE_ACTIVE_CALORIES,
    WRITE_TOTAL_CALORIES,
    WRITE_DISTANCE,
    WRITE_HEART_RATE,
    WRITE_ROUTE,
    WRITE_WEIGHT,
    WRITE_HEIGHT,
    WRITE_BODY_FAT,
    WRITE_RESTING_HEART_RATE;

    companion object {
        fun from(s: String): CapHealthPermission? {
            return try {
                CapHealthPermission.valueOf(s)
            } catch (_: Exception) {
                null
            }
        }
    }
}

@CapacitorPlugin(
    name = "HealthPlugin",
    permissions = [
        Permission(alias = "READ_STEPS", strings = ["android.permission.health.READ_STEPS"]),
        Permission(alias = "READ_WEIGHT", strings = ["android.permission.health.READ_WEIGHT"]),
        Permission(alias = "READ_HEIGHT", strings = ["android.permission.health.READ_HEIGHT"]),
        Permission(alias = "READ_WORKOUTS", strings = ["android.permission.health.READ_EXERCISE"]),
        Permission(alias = "READ_EXERCISE_TIME", strings = ["android.permission.health.READ_EXERCISE"]),
        Permission(alias = "READ_DISTANCE", strings = ["android.permission.health.READ_DISTANCE"]),
        Permission(alias = "READ_ACTIVE_CALORIES", strings = ["android.permission.health.READ_ACTIVE_CALORIES_BURNED"]),
        Permission(alias = "READ_TOTAL_CALORIES", strings = ["android.permission.health.READ_TOTAL_CALORIES_BURNED"]),
        Permission(alias = "READ_HEART_RATE", strings = ["android.permission.health.READ_HEART_RATE"]),
        Permission(alias = "READ_RESTING_HEART_RATE", strings = ["android.permission.health.READ_RESTING_HEART_RATE"]),
        Permission(alias = "READ_HRV", strings = ["android.permission.health.READ_HEART_RATE_VARIABILITY"]),
        Permission(alias = "READ_BLOOD_PRESSURE", strings = ["android.permission.health.READ_BLOOD_PRESSURE"]),
        Permission(alias = "READ_ROUTE", strings = ["android.permission.health.READ_EXERCISE"]),
        Permission(alias = "READ_MINDFULNESS", strings = ["android.permission.health.READ_MINDFULNESS"]),
        Permission(alias = "READ_RESPIRATORY_RATE", strings = ["android.permission.health.READ_RESPIRATORY_RATE"]),
        Permission(alias = "READ_OXYGEN_SATURATION", strings = ["android.permission.health.READ_OXYGEN_SATURATION"]),
        Permission(alias = "READ_BLOOD_GLUCOSE", strings = ["android.permission.health.READ_BLOOD_GLUCOSE"]),
        Permission(alias = "READ_BODY_TEMPERATURE", strings = ["android.permission.health.READ_BODY_TEMPERATURE"]),
        Permission(alias = "READ_BASAL_BODY_TEMPERATURE", strings = ["android.permission.health.READ_BASAL_BODY_TEMPERATURE"]),
        Permission(alias = "READ_BODY_FAT", strings = ["android.permission.health.READ_BODY_FAT"]),
        Permission(alias = "READ_FLOORS_CLIMBED", strings = ["android.permission.health.READ_FLOORS_CLIMBED"]),
        Permission(alias = "READ_BASAL_CALORIES", strings = ["android.permission.health.READ_BASAL_METABOLIC_RATE"]),
        Permission(alias = "READ_SLEEP", strings = ["android.permission.health.READ_SLEEP"]),
        Permission(alias = "WRITE_WORKOUTS", strings = ["android.permission.health.WRITE_EXERCISE"]),
        Permission(alias = "WRITE_ACTIVE_CALORIES", strings = ["android.permission.health.WRITE_ACTIVE_CALORIES_BURNED"]),
        Permission(alias = "WRITE_TOTAL_CALORIES", strings = ["android.permission.health.WRITE_TOTAL_CALORIES_BURNED"]),
        Permission(alias = "WRITE_DISTANCE", strings = ["android.permission.health.WRITE_DISTANCE"]),
        Permission(alias = "WRITE_HEART_RATE", strings = ["android.permission.health.WRITE_HEART_RATE"]),
        Permission(alias = "WRITE_ROUTE", strings = ["android.permission.health.WRITE_EXERCISE_ROUTE"]),
        Permission(alias = "WRITE_WEIGHT", strings = ["android.permission.health.WRITE_WEIGHT"]),
        Permission(alias = "WRITE_HEIGHT", strings = ["android.permission.health.WRITE_HEIGHT"]),
        Permission(alias = "WRITE_BODY_FAT", strings = ["android.permission.health.WRITE_BODY_FAT"]),
        Permission(alias = "WRITE_RESTING_HEART_RATE", strings = ["android.permission.health.WRITE_RESTING_HEART_RATE"])
    ]
)

@Suppress("unused", "MemberVisibilityCanBePrivate")
class HealthPlugin : Plugin() {

    private val tag = "HealthPlugin"

    private lateinit var healthConnectClient: HealthConnectClient
    private var available: Boolean = false

    private lateinit var permissionsLauncher: ActivityResultLauncher<Set<String>>

    private val permissionMapping: Map<CapHealthPermission, String> = mapOf(
        CapHealthPermission.READ_STEPS to HealthPermission.getReadPermission(StepsRecord::class),
        CapHealthPermission.READ_HEART_RATE to HealthPermission.getReadPermission(HeartRateRecord::class),
        CapHealthPermission.READ_WEIGHT to HealthPermission.getReadPermission(WeightRecord::class),
        CapHealthPermission.READ_HEIGHT to HealthPermission.getReadPermission(HeightRecord::class),
        CapHealthPermission.READ_ACTIVE_CALORIES to HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        CapHealthPermission.READ_TOTAL_CALORIES to HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        CapHealthPermission.READ_DISTANCE to HealthPermission.getReadPermission(DistanceRecord::class),
        CapHealthPermission.READ_WORKOUTS to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        CapHealthPermission.READ_EXERCISE_TIME to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        CapHealthPermission.READ_HRV to HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        CapHealthPermission.READ_BLOOD_PRESSURE to HealthPermission.getReadPermission(BloodPressureRecord::class),
        CapHealthPermission.READ_ROUTE to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        CapHealthPermission.READ_MINDFULNESS to HealthPermission.getReadPermission(MindfulnessSessionRecord::class),
        CapHealthPermission.READ_RESTING_HEART_RATE to HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        CapHealthPermission.READ_RESPIRATORY_RATE to HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        CapHealthPermission.READ_OXYGEN_SATURATION to HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        CapHealthPermission.READ_BLOOD_GLUCOSE to HealthPermission.getReadPermission(BloodGlucoseRecord::class),
        CapHealthPermission.READ_BODY_TEMPERATURE to HealthPermission.getReadPermission(BodyTemperatureRecord::class),
        CapHealthPermission.READ_BASAL_BODY_TEMPERATURE to HealthPermission.getReadPermission(BasalBodyTemperatureRecord::class),
        CapHealthPermission.READ_BODY_FAT to HealthPermission.getReadPermission(BodyFatRecord::class),
        CapHealthPermission.READ_FLOORS_CLIMBED to HealthPermission.getReadPermission(FloorsClimbedRecord::class),
        CapHealthPermission.READ_BASAL_CALORIES to HealthPermission.getReadPermission(BasalMetabolicRateRecord::class),
        CapHealthPermission.READ_SLEEP to HealthPermission.getReadPermission(SleepSessionRecord::class),
        CapHealthPermission.WRITE_WORKOUTS to HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        CapHealthPermission.WRITE_ACTIVE_CALORIES to HealthPermission.getWritePermission(ActiveCaloriesBurnedRecord::class),
        CapHealthPermission.WRITE_TOTAL_CALORIES to HealthPermission.getWritePermission(TotalCaloriesBurnedRecord::class),
        CapHealthPermission.WRITE_DISTANCE to HealthPermission.getWritePermission(DistanceRecord::class),
        CapHealthPermission.WRITE_HEART_RATE to HealthPermission.getWritePermission(HeartRateRecord::class),
        CapHealthPermission.WRITE_ROUTE to HealthPermission.PERMISSION_WRITE_EXERCISE_ROUTE,
        CapHealthPermission.WRITE_WEIGHT to HealthPermission.getWritePermission(WeightRecord::class),
        CapHealthPermission.WRITE_HEIGHT to HealthPermission.getWritePermission(HeightRecord::class),
        CapHealthPermission.WRITE_BODY_FAT to HealthPermission.getWritePermission(BodyFatRecord::class),
        CapHealthPermission.WRITE_RESTING_HEART_RATE to HealthPermission.getWritePermission(RestingHeartRateRecord::class)
    )

    override fun load() {
        super.load()
        initializePermissionLauncher()
    }

    private fun initializePermissionLauncher() {
        permissionsLauncher = bridge.activity.registerForActivityResult(
            PermissionController.createRequestPermissionResultContract()
        ) { grantedPermissions: Set<String> ->
            onPermissionsResult(grantedPermissions)
        }
    }

    private fun onPermissionsResult(grantedPermissions: Set<String>) {
        Log.i(tag, "Permissions callback: $grantedPermissions")
        val context = requestPermissionContext.getAndSet(null) ?: return

        val result = buildPermissionsResult(context, grantedPermissions)
        context.pluginCal.resolve(result)
    }

    private fun buildPermissionsResult(
        context: RequestPermissionContext,
        grantedPermissions: Set<String>
    ): JSObject {
        val perms = JSObject()
        context.requestedPermissions.forEach { cap ->
            val hp = permissionMapping[cap]
            val isGranted = hp != null && grantedPermissions.contains(hp)
            perms.put(cap.name, isGranted)
        }
        return JSObject().apply {
            put("permissions", perms)
        }
    }

    // Check if Google Health Connect is available. Must be called before anything else
    @PluginMethod
    fun isHealthAvailable(call: PluginCall) {

        if (!available) {
            try {
                healthConnectClient = HealthConnectClient.getOrCreate(context)
                available = true
            } catch (e: Exception) {
                Log.e(tag, "isHealthAvailable: Failed to initialize HealthConnectClient", e)
                available = false
            }
        }

        val result = JSObject()
        result.put("available", available)
        call.resolve(result)
    }

    // Helper to ensure HealthConnectClient is ready; attempts init lazily
    private fun ensureClientInitialized(call: PluginCall): Boolean {
        if (available) return true

        return try {
            healthConnectClient = HealthConnectClient.getOrCreate(context)
            available = true
            true
        } catch (e: Exception) {
            Log.e(tag, "Failed to initialise HealthConnectClient", e)
            call.reject("Health Connect is not available on this device.")
            false
        }
    }

    // Check if a set of permissions are granted
    @PluginMethod
    fun checkHealthPermissions(call: PluginCall) {
        if (!ensureClientInitialized(call)) return
        val permissionsToCheck = call.getArray("permissions")
        if (permissionsToCheck == null) {
            call.reject("Must provide permissions to check")
            return
        }

        val permissions =
            permissionsToCheck.toList<String>().mapNotNull { CapHealthPermission.from(it) }.toSet()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val grantedPermissions = healthConnectClient.permissionController.getGrantedPermissions()
                val result = grantedPermissionResult(permissions, grantedPermissions)
                call.resolve(result)
            } catch (e: Exception) {
                call.reject("Checking permissions failed: ${e.message}")
            }
        }
    }

    private fun grantedPermissionResult(
        requestPermissions: Set<CapHealthPermission>,
        grantedPermissions: Set<String>
    ): JSObject {
        val readPermissions = JSObject()
        for (permission in requestPermissions) {
            val hp = permissionMapping[permission]!!
            // Check by object equality
            readPermissions.put(permission.name, grantedPermissions.contains(hp))
        }
        return JSObject().apply {
            put("permissions", readPermissions)
        }
    }

    data class RequestPermissionContext(val requestedPermissions: Set<CapHealthPermission>, val pluginCal: PluginCall)

    private val requestPermissionContext = AtomicReference<RequestPermissionContext>()

    // Request a set of permissions from the user
    @PluginMethod
    fun requestHealthPermissions(call: PluginCall) {
        if (!ensureClientInitialized(call)) return
        val requestedCaps = call.getArray("permissions")
            ?.toList<String>()
            ?.mapNotNull { CapHealthPermission.from(it) }
            ?.toSet() ?: return call.reject("Provide permissions array.")

        val hcPermissions: Set<String> = requestedCaps
            .mapNotNull { permissionMapping[it] }
            .toSet()

        if (hcPermissions.isEmpty()) {
            return call.reject("No valid Health Connect permissions.")
        }

        requestPermissionContext.set(RequestPermissionContext(requestedCaps, call))

        // Show rationale if available
        context.packageManager?.let { pm ->
            Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE").apply {
                setPackage("com.google.android.apps.healthdata")
            }.takeIf { pm.resolveActivity(it, 0) != null }
                ?.also { context.startActivity(it) }
                ?: Log.w(tag, "Health Connect rationale screen not found")
        }

        CoroutineScope(Dispatchers.Main).launch {
            permissionsLauncher.launch(hcPermissions)
            Log.i(tag, "Launched Health Connect permission request: $hcPermissions")
        }
    }

    // Open Google Health Connect app settings
    @PluginMethod
    fun openHealthConnectSettings(call: PluginCall) {
        try {
            val intent = Intent().apply {
                action = HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS
            }
            context.startActivity(intent)
            call.resolve()
        } catch(e: Exception) {
            call.reject(e.message)
        }
    }

    // Alias for iOS compatibility
    @PluginMethod
    fun openAppleHealthSettings(call: PluginCall) {
        openHealthConnectSettings(call)
    }

    // Open the Google Play Store to install Health Connect
    @PluginMethod
    fun showHealthConnectInPlayStore(call: PluginCall) {
        val uri =
            "https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata".toUri()
        val intent = Intent(Intent.ACTION_VIEW, uri)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        call.resolve()
    }

    @PluginMethod
    fun getCharacteristics(call: PluginCall) {
        val requestedFields = call.getArray("fields")
            ?.toList<String>()
            ?.filter { it.isNotBlank() }
            ?: emptyList()
        val result = JSObject()
        result.put("platformSupported", false)
        result.put(
            "platformMessage",
            "Health Connect does not expose characteristics; this section stays empty unless synced from an iOS device.${if (requestedFields.isEmpty()) "" else " Requested fields: ${requestedFields.joinToString(\", \")}."}"
        )
        call.resolve(result)
    }

    private fun getMetricAndMapper(dataType: String): MetricAndMapper {
        return when (dataType) {
            "steps" -> metricAndMapper("steps", CapHealthPermission.READ_STEPS, StepsRecord.COUNT_TOTAL) { it?.toDouble() }
            "heart-rate", "heartRate" -> metricAndMapper(
                "heartRate",
                CapHealthPermission.READ_HEART_RATE,
                HeartRateRecord.BPM_AVG
            ) { it?.toDouble() }
            "active-calories", "activeCalories" -> metricAndMapper(
                "calories",
                CapHealthPermission.READ_ACTIVE_CALORIES,
                ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL
            ) { it?.inKilocalories }
            "total-calories" -> metricAndMapper(
                "calories",
                CapHealthPermission.READ_TOTAL_CALORIES,
                TotalCaloriesBurnedRecord.ENERGY_TOTAL
            ) { it?.inKilocalories }
            "distance" -> metricAndMapper("distance", CapHealthPermission.READ_DISTANCE, DistanceRecord.DISTANCE_TOTAL) { it?.inMeters }
            "flights-climbed" -> metricAndMapper(
                "flightsClimbed",
                CapHealthPermission.READ_FLOORS_CLIMBED,
                FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL
            ) { it }
            "mindfulness" -> metricAndMapper(
                "mindfulness",
                CapHealthPermission.READ_MINDFULNESS,
                MindfulnessSessionRecord.MINDFULNESS_DURATION_TOTAL
            ) { it?.seconds?.toDouble() }
            "basal-calories" -> metricAndMapper(
                "basalCalories",
                CapHealthPermission.READ_BASAL_CALORIES,
                BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL
            ) { it?.inKilocalories }
            "resting-heart-rate" -> metricAndMapper(
                "restingHeartRate",
                CapHealthPermission.READ_RESTING_HEART_RATE,
                RestingHeartRateRecord.BPM_AVG
            ) { it?.toDouble() }
            else -> throw RuntimeException("Unsupported dataType: $dataType")
        }
    }

    @PluginMethod
    fun queryLatestSample(call: PluginCall) {
        if (!ensureClientInitialized(call)) return
        val dataType = call.getString("dataType")
        if (dataType == null) {
            call.reject("Missing required parameter: dataType")
            return
        }
        queryLatestSampleInternal(call, dataType)
    }

    private fun queryLatestSampleInternal(call: PluginCall, dataType: String) {
        if (!ensureClientInitialized(call)) return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val result = when (dataType) {
                    "heart-rate", "heartRate" -> readLatestHeartRate()
                    "resting-heart-rate" -> readLatestRestingHeartRate()
                    "weight" -> readLatestWeight()
                    "height" -> readLatestHeight()
                    "steps" -> readLatestSteps()
                    "hrv" -> readLatestHrv()
                    "blood-pressure" -> readLatestBloodPressure()
                    "distance" -> readLatestDistance()
                    "distance-cycling" -> readLatestDistance()
                    "active-calories" -> readLatestActiveCalories()
                    "total-calories" -> readLatestTotalCalories()
                    "basal-calories" -> readLatestBasalCalories()
                    "respiratory-rate" -> readLatestRespiratoryRate()
                    "oxygen-saturation" -> readLatestOxygenSaturation()
                    "blood-glucose" -> readLatestBloodGlucose()
                    "body-temperature" -> readLatestBodyTemperature()
                    "basal-body-temperature" -> readLatestBasalBodyTemperature()
                    "body-fat" -> readLatestBodyFat()
                    "flights-climbed" -> readLatestFlightsClimbed()
                    "exercise-time" -> readLatestExerciseTime()
                    "mindfulness" -> readLatestMindfulness()
                    "sleep" -> readLatestSleep()
                    "sleep-rem" -> readLatestSleepRem()
                    else -> throw IllegalArgumentException("Unsupported data type: $dataType")
                }
                call.resolve(result)
            } catch (e: Exception) {
                Log.e(tag, "queryLatestSampleInternal: Error fetching latest $dataType", e)
                call.reject("Error fetching latest $dataType: ${e.message}")
            }
        }
    }

    // Convenience methods for specific data types
    @PluginMethod
    fun queryWeight(call: PluginCall) {
        queryLatestSampleInternal(call, "weight")
    }

    @PluginMethod
    fun queryHeight(call: PluginCall) {
        queryLatestSampleInternal(call, "height")
    }

    @PluginMethod
    fun queryHeartRate(call: PluginCall) {
        queryLatestSampleInternal(call, "heart-rate")
    }

    @PluginMethod
    fun querySteps(call: PluginCall) {
        queryLatestSampleInternal(call, "steps")
    }

    private suspend fun readLatestHeartRate(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_HEART_RATE)) {
            throw Exception("Permission for heart rate not granted")
        }
        val request = ReadRecordsRequest(
            recordType = HeartRateRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No heart rate data found")

        val lastSample = record.samples.lastOrNull()
        return JSObject().apply {
            put("value", lastSample?.beatsPerMinute ?: 0)
            put("timestamp", (lastSample?.time?.epochSecond ?: 0) * 1000) // Convert to milliseconds like iOS
            put("unit", "count/min")
        }
    }

    private suspend fun readLatestWeight(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_WEIGHT)) {
            throw Exception("Permission for weight not granted")
        }
        val request = ReadRecordsRequest(
            recordType = WeightRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            ascendingOrder = false,
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()

        return JSObject().apply {
            put("value", record?.weight?.inKilograms)
            put("timestamp", record?.time?.toEpochMilli())
            put("unit", "kg")
        }
    }

    private suspend fun readLatestSteps(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_STEPS)) {
            throw Exception("Permission for steps not granted")
        }
        val request = ReadRecordsRequest(
            recordType = StepsRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.count ?: 0)
            put("timestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "count")
        }
    }

    private suspend fun readLatestHrv(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_HRV)) {
            throw Exception("Permission for HRV not granted")
        }
        val request = ReadRecordsRequest(
            recordType = HeartRateVariabilityRmssdRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()

        return JSObject().apply {
            put("value", record?.heartRateVariabilityMillis ?: 0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "ms")
        }
    }

    private suspend fun readLatestBloodPressure(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BLOOD_PRESSURE)) {
            throw Exception("Permission for blood pressure not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BloodPressureRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()

        return JSObject().apply {
            put("systolic", record?.systolic?.inMillimetersOfMercury ?: 0)
            put("diastolic", record?.diastolic?.inMillimetersOfMercury ?: 0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "mmHg")
        }
    }

    private suspend fun readLatestHeight(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_HEIGHT)) {
            throw Exception("Permission for height not granted")
        }
        val request = ReadRecordsRequest(
            recordType = HeightRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            ascendingOrder = false,
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()

        return JSObject().apply {
            put("value", record?.height?.inMeters)
            put("timestamp", record?.time?.toEpochMilli())
            put("unit", "m")
        }
    }

    private suspend fun readLatestDistance(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_DISTANCE)) {
            throw Exception("Permission for distance not granted")
        }
        val request = ReadRecordsRequest(
            recordType = DistanceRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.distance?.inMeters ?: 0)
            put("timestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "m")
        }
    }

    private suspend fun readLatestActiveCalories(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_ACTIVE_CALORIES)) {
            throw Exception("Permission for active calories not granted")
        }
        val request = ReadRecordsRequest(
            recordType = ActiveCaloriesBurnedRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.energy?.inKilocalories ?: 0)
            put("timestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "kcal")
        }
    }

    private suspend fun readLatestRestingHeartRate(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_RESTING_HEART_RATE)) {
            throw Exception("Permission for resting heart rate not granted")
        }
        val request = ReadRecordsRequest(
            recordType = RestingHeartRateRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.beatsPerMinute ?: 0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "count/min")
        }
    }

    private suspend fun readLatestRespiratoryRate(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_RESPIRATORY_RATE)) {
            throw Exception("Permission for respiratory rate not granted")
        }
        val request = ReadRecordsRequest(
            recordType = RespiratoryRateRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.rate ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "count/min")
        }
    }

    private suspend fun readLatestOxygenSaturation(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_OXYGEN_SATURATION)) {
            throw Exception("Permission for oxygen saturation not granted")
        }
        val request = ReadRecordsRequest(
            recordType = OxygenSaturationRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.percentage?.value ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "percent")
        }
    }

    private suspend fun readLatestBloodGlucose(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BLOOD_GLUCOSE)) {
            throw Exception("Permission for blood glucose not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BloodGlucoseRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        val meta = JSObject()
        record?.let {
            meta.put("specimenSource", it.specimenSource)
            meta.put("relationToMeal", it.relationToMeal)
            meta.put("mealType", it.mealType)
        }
        return JSObject().apply {
            put("value", record?.level?.inMilligramsPerDeciliter ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "mg/dL")
            put("metadata", meta)
        }
    }

    private suspend fun readLatestBodyTemperature(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BODY_TEMPERATURE)) {
            throw Exception("Permission for body temperature not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BodyTemperatureRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.temperature?.inCelsius ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "degC")
        }
    }

    private suspend fun readLatestBasalBodyTemperature(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BASAL_BODY_TEMPERATURE)) {
            throw Exception("Permission for basal body temperature not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BasalBodyTemperatureRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.temperature?.inCelsius ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "degC")
        }
    }

    private suspend fun readLatestBodyFat(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BODY_FAT)) {
            throw Exception("Permission for body fat not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BodyFatRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.percentage?.value ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "percent")
        }
    }

    private suspend fun readLatestBasalCalories(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_BASAL_CALORIES)) {
            throw Exception("Permission for basal calories not granted")
        }
        val request = ReadRecordsRequest(
            recordType = BasalMetabolicRateRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.basalMetabolicRate?.inKilocaloriesPerDay ?: 0.0)
            put("timestamp", (record?.time?.epochSecond ?: 0) * 1000)
            put("unit", "kcal/day")
        }
    }

    private suspend fun readLatestFlightsClimbed(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_FLOORS_CLIMBED)) {
            throw Exception("Permission for floors climbed not granted")
        }
        val request = ReadRecordsRequest(
            recordType = FloorsClimbedRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.floors ?: 0.0)
            put("timestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "count")
        }
    }

    private suspend fun readLatestExerciseTime(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_WORKOUTS)) {
            throw Exception("Permission for exercise sessions not granted")
        }
        val request = ReadRecordsRequest(
            recordType = ExerciseSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        val duration = record?.let { session ->
            if (session.segments.isEmpty()) {
                session.endTime.epochSecond - session.startTime.epochSecond
            } else {
                session.segments.sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
            }
        } ?: 0
        return JSObject().apply {
            put("value", duration / 60.0)
            put("timestamp", (record?.startTime?.epochSecond ?: 0) * 1000)
            put("endTimestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "min")
        }
    }

    private suspend fun readLatestMindfulness(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_MINDFULNESS)) {
            throw Exception("Permission for mindfulness not granted")
        }
        val request = ReadRecordsRequest(
            recordType = MindfulnessSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        val durationSeconds = record?.let { it.endTime.epochSecond - it.startTime.epochSecond } ?: 0
        val metadata = JSObject()
        record?.notes?.let { metadata.put("notes", it) }
        record?.title?.let { metadata.put("title", it) }
        record?.mindfulnessSessionType?.let { metadata.put("type", it) }
        return JSObject().apply {
            put("value", durationSeconds / 60.0)
            put("timestamp", (record?.startTime?.epochSecond ?: 0) * 1000)
            put("endTimestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "min")
            put("metadata", metadata)
        }
    }

    private suspend fun readLatestSleep(): JSObject {
        val hasSleepPermission = hasPermission(CapHealthPermission.READ_SLEEP)
        if (!hasSleepPermission) {
            throw Exception("Permission for sleep not granted")
        }
        val request = ReadRecordsRequest(
            recordType = SleepSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        val durationMinutes = record?.let { (it.endTime.epochSecond - it.startTime.epochSecond) / 60.0 } ?: 0.0
        val metadata = JSObject()
        record?.title?.let { metadata.put("title", it) }
        metadata.put("stagesCount", record?.stages?.size ?: 0)
        return JSObject().apply {
            put("value", durationMinutes)
            put("timestamp", (record?.startTime?.epochSecond ?: 0) * 1000)
            put("endTimestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "min")
            put("metadata", metadata)
        }
    }

    private suspend fun readLatestSleepRem(): JSObject {
        val hasSleepPermission = hasPermission(CapHealthPermission.READ_SLEEP)
        if (!hasSleepPermission) {
            throw Exception("Permission for sleep not granted")
        }
        val request = ReadRecordsRequest(
            recordType = SleepSessionRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
            ?: throw Exception("No sleep data found")
        val remMinutes = record.stages
            .filter { it.stage == SleepSessionRecord.STAGE_TYPE_REM }
            .sumOf { it.endTime.epochSecond - it.startTime.epochSecond } / 60.0
        if (remMinutes <= 0) {
            throw Exception("No REM sleep data found")
        }
        return JSObject().apply {
            put("value", remMinutes)
            put("timestamp", record.startTime.epochSecond * 1000)
            put("endTimestamp", record.endTime.epochSecond * 1000)
            put("unit", "min")
        }
    }

    private suspend fun sumActiveAndBasalCalories(
        timeRange: TimeRangeFilter,
        includeTotalMetricFallback: Boolean = false
    ): Double? {
        val metrics = mutableSetOf<AggregateMetric<*>>()
        val includeActive = hasPermission(CapHealthPermission.READ_ACTIVE_CALORIES)
        val includeBasal = hasPermission(CapHealthPermission.READ_BASAL_CALORIES)
        val includeTotal = includeTotalMetricFallback && hasPermission(CapHealthPermission.READ_TOTAL_CALORIES)

        if (includeActive) metrics.add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
        if (includeBasal) metrics.add(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL)
        if (includeTotal) metrics.add(TotalCaloriesBurnedRecord.ENERGY_TOTAL)

        if (metrics.isEmpty()) {
            return null
        }

        val aggregation = healthConnectClient.aggregate(
            AggregateRequest(
                metrics = metrics,
                timeRangeFilter = timeRange,
                dataOriginFilter = emptySet()
            )
        )

        val active = if (includeActive) {
            aggregation[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories
        } else null
        val basal = if (includeBasal) {
            aggregation[BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]?.inKilocalories
        } else null
        val total = if (includeTotal) {
            aggregation[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories
        } else null

        return when {
            active != null || basal != null -> (active ?: 0.0) + (basal ?: 0.0)
            includeTotal -> total
            else -> null
        }
    }

    private suspend fun readLatestTotalCalories(): JSObject {
        val zone = ZoneId.systemDefault()
        val now = LocalDateTime.now(zone)

        val derivedTotal = try {
            sumActiveAndBasalCalories(
                TimeRangeFilter.between(
                    now.toLocalDate().atStartOfDay(),
                    now
                )
            )
        } catch (e: Exception) {
            Log.w(tag, "readLatestTotalCalories: Failed to derive active+basal calories, falling back to total metric", e)
            null
        }

        if (derivedTotal != null) {
            return JSObject().apply {
                put("value", derivedTotal)
                put("timestamp", now.atZone(zone).toInstant().toEpochMilli())
                put("unit", "kcal")
            }
        }

        if (!hasPermission(CapHealthPermission.READ_TOTAL_CALORIES)) {
            throw Exception("Permission for total calories not granted")
        }
        val request = ReadRecordsRequest(
            recordType = TotalCaloriesBurnedRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val record = healthConnectClient.readRecords(request).records.firstOrNull()
        return JSObject().apply {
            put("value", record?.energy?.inKilocalories ?: 0)
            put("timestamp", (record?.endTime?.epochSecond ?: 0) * 1000)
            put("unit", "kcal")
        }
    }

    @PluginMethod
    fun queryAggregated(call: PluginCall) {
        if (!ensureClientInitialized(call)) return
        try {
            val startDate = call.getString("startDate")
            val endDate = call.getString("endDate")
            val dataType = call.getString("dataType")
            val bucket = call.getString("bucket")

            if (startDate == null || endDate == null || dataType == null || bucket == null) {
                call.reject("Missing required parameters: startDate, endDate, dataType, or bucket")
                return
            }

            val (startDateTime, endDateTime) = normalizeTimeRangeForBucket(
                Instant.parse(startDate),
                Instant.parse(endDate),
                bucket
            )

            val period = when (bucket) {
                "day" -> Period.ofDays(1)
                else -> throw RuntimeException("Unsupported bucket: $bucket")
            }

            val timeRange = TimeRangeFilter.between(startDateTime, endDateTime)

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val aggregatedList = JSArray()

                    when {
                        // Special handling for HRV (RMSSD) because aggregate metrics were
                        // removed in Health Connect 1.1‑rc03. We calculate the daily average
                        // from raw samples instead.
                        dataType == "hrv" -> aggregateHrvByPeriod(timeRange, period)
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "exercise-time" -> aggregateExerciseTime(timeRange, period)
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "sleep" -> aggregateSleepSessions(timeRange, period)
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "blood-pressure" -> aggregateBloodPressure(timeRange, period)
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "distance-cycling" -> aggregateCyclingDistance(timeRange, period)
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "weight" -> aggregateInstantLatestPerDay(
                            WeightRecord::class,
                            CapHealthPermission.READ_WEIGHT,
                            timeRange,
                            period,
                            { it.time }
                        ) { it.weight.inKilograms }
                            .forEach { aggregatedList.put(it.toJs()) }

                        dataType == "height" -> aggregateInstantLatestPerDay(
                            HeightRecord::class,
                            CapHealthPermission.READ_HEIGHT,
                            timeRange,
                            period,
                            { it.time }
                        ) { it.height.inMeters }
                            .forEach { aggregatedList.put(it.toJs()) }

                        setOf(
                            "respiratory-rate",
                            "oxygen-saturation",
                            "blood-glucose",
                            "body-temperature",
                            "basal-body-temperature",
                            "body-fat"
                        ).contains(dataType) -> {
                            val aggregated = when (dataType) {
                                "respiratory-rate" -> aggregateInstantAverage(
                                    RespiratoryRateRecord::class,
                                    CapHealthPermission.READ_RESPIRATORY_RATE,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.rate }

                                "oxygen-saturation" -> aggregateInstantAverage(
                                    OxygenSaturationRecord::class,
                                    CapHealthPermission.READ_OXYGEN_SATURATION,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.percentage.value }

                                "blood-glucose" -> aggregateInstantAverage(
                                    BloodGlucoseRecord::class,
                                    CapHealthPermission.READ_BLOOD_GLUCOSE,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.level.inMilligramsPerDeciliter }

                                "body-temperature" -> aggregateInstantAverage(
                                    BodyTemperatureRecord::class,
                                    CapHealthPermission.READ_BODY_TEMPERATURE,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.temperature.inCelsius }

                                "basal-body-temperature" -> aggregateInstantAverage(
                                    BasalBodyTemperatureRecord::class,
                                    CapHealthPermission.READ_BASAL_BODY_TEMPERATURE,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.temperature.inCelsius }

                                "body-fat" -> aggregateInstantAverage(
                                    BodyFatRecord::class,
                                    CapHealthPermission.READ_BODY_FAT,
                                    timeRange,
                                    period,
                                    { it.time }
                                ) { it.percentage.value }

                                else -> emptyList()
                            }
                            aggregated.forEach { aggregatedList.put(it.toJs()) }
                        }

                        else -> {
                            val aggregated = if (dataType == "total-calories") {
                                aggregateTotalCalories(timeRange, period)
                            } else {
                                val metricAndMapper = getMetricAndMapper(dataType)
                                queryAggregatedMetric(
                                    metricAndMapper,
                                    timeRange,
                                    period
                                )
                            }
                            aggregated.forEach { aggregatedList.put(it.toJs()) }
                        }
                    }

                    val finalResult = JSObject()
                    finalResult.put("aggregatedData", aggregatedList)
                    call.resolve(finalResult)
                } catch (e: Exception) {
                    call.reject("Error querying aggregated data: ${e.message}")
                }
            }
        } catch (e: Exception) {
            call.reject(e.message)
            return
        }
    }


    private fun normalizeTimeRangeForBucket(
        startInstant: Instant,
        endInstant: Instant,
        bucket: String
    ): Pair<LocalDateTime, LocalDateTime> {
        val zone = ZoneId.systemDefault()
        if (bucket == "day") {
            val startOfDay = startInstant.atZone(zone).toLocalDate().atStartOfDay()
            val endOfDay = endInstant.atZone(zone).toLocalDate().plusDays(1).atStartOfDay()
            return Pair(startOfDay, endOfDay)
        }

        return Pair(
            startInstant.atZone(zone).toLocalDateTime(),
            endInstant.atZone(zone).toLocalDateTime()
        )
    }


    private fun <M : Any> metricAndMapper(
        name: String,
        permission: CapHealthPermission,
        metric: AggregateMetric<M>,
        mapper: (M?) -> Double?
    ): MetricAndMapper {
        @Suppress("UNCHECKED_CAST")
        return MetricAndMapper(name, permission, metric, mapper as (Any?) -> Double?)
    }

    data class MetricAndMapper(
        val name: String,
        val permission: CapHealthPermission,
        val metric: AggregateMetric<Any>,
        val mapper: (Any?) -> Double?
    ) {
        fun getValue(a: AggregationResult): Double? {
            return mapper(a[metric])
        }
    }

    data class AggregatedSample(val startDate: LocalDateTime, val endDate: LocalDateTime, val value: Double?) {
        fun toJs(): JSObject {
            val o = JSObject()
            o.put("startDate", startDate)
            o.put("endDate", endDate)
            o.put("value", value)

            return o

        }
    }

    data class AggregatedBloodPressureSample(
        val startDate: LocalDateTime,
        val endDate: LocalDateTime,
        val systolic: Double?,
        val diastolic: Double?
    ) {
        fun toJs(): JSObject {
            val o = JSObject()
            o.put("startDate", startDate)
            o.put("endDate", endDate)
            o.put("systolic", systolic)
            o.put("diastolic", diastolic)
            o.put("value", systolic)
            o.put("unit", "mmHg")
            return o
        }
    }

    private suspend fun queryAggregatedMetric(
        metricAndMapper: MetricAndMapper, timeRange: TimeRangeFilter, period: Period,
    ): List<AggregatedSample> {
        if (!hasPermission(metricAndMapper.permission)) {
            return emptyList()
        }

        val response: List<AggregationResultGroupedByPeriod> = healthConnectClient.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = setOf(metricAndMapper.metric),
                timeRangeFilter = timeRange,
                timeRangeSlicer = period
            )
        )

        return response.map {
            val mappedValue = metricAndMapper.getValue(it.result) ?: 0.0
            AggregatedSample(it.startTime, it.endTime, mappedValue)
        }

    }

    private suspend fun aggregateTotalCalories(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedSample> {
        val includeActive = hasPermission(CapHealthPermission.READ_ACTIVE_CALORIES)
        val includeBasal = hasPermission(CapHealthPermission.READ_BASAL_CALORIES)
        val includeTotal = hasPermission(CapHealthPermission.READ_TOTAL_CALORIES)

        val metrics = mutableSetOf<AggregateMetric<*>>()
        if (includeActive) metrics.add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
        if (includeBasal) metrics.add(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL)
        if (includeTotal) metrics.add(TotalCaloriesBurnedRecord.ENERGY_TOTAL)

        if (metrics.isEmpty()) {
            return emptyList()
        }

        val response: List<AggregationResultGroupedByPeriod> = healthConnectClient.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = metrics,
                timeRangeFilter = timeRange,
                timeRangeSlicer = period
            )
        )

        return response.map {
            val active = if (includeActive) {
                it.result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories
            } else null
            val basal = if (includeBasal) {
                it.result[BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]?.inKilocalories
            } else null
            val total = if (includeTotal) {
                it.result[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories
            } else null

            val value = when {
                active != null || basal != null -> (active ?: 0.0) + (basal ?: 0.0)
                else -> total ?: 0.0
            }

            AggregatedSample(it.startTime, it.endTime, value)
        }
    }

    private suspend fun aggregateHrvByPeriod(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedSample> {
        if (!hasPermission(CapHealthPermission.READ_HRV)) {
            return emptyList()
        }

        // Currently only daily buckets are supported.
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket for HRV aggregation")
        }

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = HeartRateVariabilityRmssdRecord::class,
                timeRangeFilter = timeRange
            )
        )

        // Group raw RMSSD samples by local date and compute the arithmetic mean.
        return response.records
            .groupBy { it.time.atZone(ZoneId.systemDefault()).toLocalDate() }
            .map { (localDate, recs) ->
                val avg = recs.map { it.heartRateVariabilityMillis }.average()
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    if (avg.isNaN()) null else avg
                )
            }
            .sortedBy { it.startDate }
    }

    private suspend fun <T : Record> aggregateInstantAverage(
        recordType: KClass<T>,
        permission: CapHealthPermission,
        timeRange: TimeRangeFilter,
        period: Period,
        timeSelector: (T) -> Instant,
        valueSelector: (T) -> Double?
    ): List<AggregatedSample> {
        if (!hasPermission(permission)) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket for aggregation")
        }

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = recordType,
                timeRangeFilter = timeRange
            )
        )

        return response.records
            .groupBy { timeSelector(it).atZone(ZoneId.systemDefault()).toLocalDate() }
            .map { (localDate, recs) ->
                val avg = recs.mapNotNull(valueSelector).average()
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    if (avg.isNaN()) null else avg
                )
            }
            .sortedBy { it.startDate }
    }

    // Average systolic/diastolic per day from raw blood pressure samples.
    private suspend fun aggregateBloodPressure(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedBloodPressureSample> {
        if (!hasPermission(CapHealthPermission.READ_BLOOD_PRESSURE)) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket for blood pressure aggregation")
        }

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = BloodPressureRecord::class,
                timeRangeFilter = timeRange
            )
        )

        return response.records
            .groupBy { it.time.atZone(ZoneId.systemDefault()).toLocalDate() }
            .map { (localDate, recs) ->
                val systolicAvg = recs.map { it.systolic.inMillimetersOfMercury }.average()
                val diastolicAvg = recs.map { it.diastolic.inMillimetersOfMercury }.average()
                val start = localDate.atStartOfDay()
                AggregatedBloodPressureSample(
                    start,
                    start.plusDays(1),
                    if (systolicAvg.isNaN()) null else systolicAvg,
                    if (diastolicAvg.isNaN()) null else diastolicAvg
                )
            }
            .sortedBy { it.startDate }
    }

    // Sum cycling distance by restricting to biking sessions to avoid mixing in walking/running data.
    private suspend fun aggregateCyclingDistance(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedSample> {
        if (!hasPermission(CapHealthPermission.READ_WORKOUTS) || !hasPermission(CapHealthPermission.READ_DISTANCE)) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket for cycling distance aggregation")
        }

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = ExerciseSessionRecord::class,
                timeRangeFilter = timeRange,
                dataOriginFilter = emptySet(),
                ascendingOrder = true,
                pageSize = 1000
            )
        )

        val cyclingTypes = setOf(
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
            ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY
        )

        val dailyDistance = mutableMapOf<LocalDate, Double>()
        for (session in response.records.filter { cyclingTypes.contains(it.exerciseType) }) {
            try {
                val request = AggregateRequest(
                    setOf(DistanceRecord.DISTANCE_TOTAL),
                    TimeRangeFilter.between(session.startTime, session.endTime),
                    setOf(session.metadata.dataOrigin)
                )
                val aggregation = healthConnectClient.aggregate(request)
                val distance = aggregation[DistanceRecord.DISTANCE_TOTAL]?.inMeters ?: 0.0
                val localDate = session.startTime.atZone(ZoneId.systemDefault()).toLocalDate()
                dailyDistance[localDate] = dailyDistance.getOrDefault(localDate, 0.0) + distance
            } catch (e: Exception) {
                Log.e(tag, "aggregateCyclingDistance: Failed to aggregate session distance", e)
            }
        }

        return dailyDistance.entries
            .map { (localDate, distance) ->
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    distance
                )
            }
            .sortedBy { it.startDate }
    }

    private suspend fun aggregateExerciseTime(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedSample> {
        if (!hasPermission(CapHealthPermission.READ_WORKOUTS)) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket: $period")
        }
        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = ExerciseSessionRecord::class,
                timeRangeFilter = timeRange,
                dataOriginFilter = emptySet(),
                ascendingOrder = true,
                pageSize = 1000
            )
        )
        return response.records
            .groupBy { it.startTime.atZone(ZoneId.systemDefault()).toLocalDate() }
            .map { (localDate, sessions) ->
                val totalSeconds = sessions.sumOf { session ->
                    if (session.segments.isEmpty()) {
                        session.endTime.epochSecond - session.startTime.epochSecond
                    } else {
                        session.segments.sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                    }
                }
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    totalSeconds / 60.0
                )
            }
            .sortedBy { it.startDate }
    }

    private suspend fun <T : Record> aggregateInstantLatestPerDay(
        recordType: KClass<T>,
        permission: CapHealthPermission,
        timeRange: TimeRangeFilter,
        period: Period,
        timeSelector: (T) -> Instant,
        valueSelector: (T) -> Double?
    ): List<AggregatedSample> {
        if (!hasPermission(permission)) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket for aggregation")
        }

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = recordType,
                timeRangeFilter = timeRange,
                dataOriginFilter = emptySet(),
                ascendingOrder = false,
                pageSize = 1000
            )
        )

        return response.records
            .groupBy { timeSelector(it).atZone(ZoneId.systemDefault()).toLocalDate() }
            .mapNotNull { (localDate, recs) ->
                val latest = recs.maxByOrNull { timeSelector(it) } ?: return@mapNotNull null
                val value = valueSelector(latest)
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    value
                )
            }
            .sortedBy { it.startDate }
    }

    private suspend fun aggregateSleepSessions(
        timeRange: TimeRangeFilter,
        period: Period
    ): List<AggregatedSample> {
        val hasSleepPermission = hasPermission(CapHealthPermission.READ_SLEEP)
        if (!hasSleepPermission) {
            return emptyList()
        }
        if (period != Period.ofDays(1)) {
            throw RuntimeException("Unsupported bucket: $period")
        }
        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = timeRange
            )
        )
        return response.records
            .groupBy { it.startTime.atZone(ZoneId.systemDefault()).toLocalDate() }
            .map { (localDate, sessions) ->
                val totalSeconds = sessions.sumOf { it.endTime.epochSecond - it.startTime.epochSecond }
                val start = localDate.atStartOfDay()
                AggregatedSample(
                    start,
                    start.plusDays(1),
                    totalSeconds.toDouble()
                )
            }
            .sortedBy { it.startDate }
    }

    private suspend fun hasPermission(p: CapHealthPermission): Boolean {
        val granted = healthConnectClient.permissionController.getGrantedPermissions()
        val targetPermission = permissionMapping[p]
        return granted.contains(targetPermission)
    }

    @PluginMethod
    fun saveMetrics(call: PluginCall) {
        if (!ensureClientInitialized(call)) return

        val weightKg = call.getDouble("weightKg")
        val heightCm = call.getDouble("heightCm")
        val bodyFatPercent = call.getDouble("bodyFatPercent")
        val restingHeartRate = call.getDouble("restingHeartRate")

        if (weightKg == null && heightCm == null && bodyFatPercent == null && restingHeartRate == null) {
            call.reject("No metrics provided")
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val granted = healthConnectClient.permissionController.getGrantedPermissions()
                fun ensurePermission(cap: CapHealthPermission, name: String): Boolean {
                    val hc = permissionMapping[cap]
                    val ok = hc != null && granted.contains(hc)
                    if (!ok) {
                        call.reject("Missing $name permission")
                    }
                    return ok
                }

                val now = Instant.now()
                val offset = now.atZone(ZoneId.systemDefault()).offset

                val records = mutableListOf<Record>()

                weightKg?.let {
                    if (!ensurePermission(CapHealthPermission.WRITE_WEIGHT, "WRITE_WEIGHT")) return@launch
                    records.add(
                        WeightRecord(
                            time = now,
                            zoneOffset = offset,
                            weight = it.kilograms,
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                heightCm?.let {
                    if (!ensurePermission(CapHealthPermission.WRITE_HEIGHT, "WRITE_HEIGHT")) return@launch
                    records.add(
                        HeightRecord(
                            time = now,
                            zoneOffset = offset,
                            height = (it / 100.0).meters,
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                bodyFatPercent?.let {
                    if (!ensurePermission(CapHealthPermission.WRITE_BODY_FAT, "WRITE_BODY_FAT")) return@launch
                    records.add(
                        BodyFatRecord(
                            time = now,
                            zoneOffset = offset,
                            percentage = it.percent,
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                restingHeartRate?.let {
                    if (!ensurePermission(CapHealthPermission.WRITE_RESTING_HEART_RATE, "WRITE_RESTING_HEART_RATE")) return@launch
                    records.add(
                        RestingHeartRateRecord(
                            time = now,
                            zoneOffset = offset,
                            beatsPerMinute = it.toLong(),
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                if (records.isEmpty()) {
                    call.reject("No metrics were added; missing permissions?")
                    return@launch
                }

                val response = healthConnectClient.insertRecords(records)
                val result = JSObject()
                result.put("success", true)
                result.put("inserted", response.recordIdsList.size)
                call.resolve(result)
            } catch (e: Exception) {
                call.reject("Failed to save metrics: ${e.message}")
            }
        }
    }

    @PluginMethod
    fun saveWorkout(call: PluginCall) {
        if (!ensureClientInitialized(call)) return

        val activityTypeRaw = call.getString("activityType")
        val startDate = call.getString("startDate")
        val endDate = call.getString("endDate")
        val calories = call.getDouble("calories")
        val distance = call.getDouble("distance")
        val metadata = call.getObject("metadata")
        val routeArray = call.getArray("route")
        val heartRateArray = call.getArray("heartRateSamples")

        if (activityTypeRaw == null || startDate == null || endDate == null) {
            call.reject("Missing required parameters: activityType, startDate, endDate")
            return
        }

        val startInstant = parseInstant(startDate)
        val endInstant = parseInstant(endDate)
        if (startInstant == null || endInstant == null) {
            call.reject("Invalid startDate or endDate; must be ISO-8601 strings.")
            return
        }
        if (!startInstant.isBefore(endInstant)) {
            call.reject("startDate must be before endDate")
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val granted = healthConnectClient.permissionController.getGrantedPermissions()
                fun ensurePermission(cap: CapHealthPermission, name: String): Boolean {
                    val hc = permissionMapping[cap]
                    val ok = hc != null && granted.contains(hc)
                    if (!ok) {
                        call.reject("Missing $name permission")
                    }
                    return ok
                }

                if (!ensurePermission(CapHealthPermission.WRITE_WORKOUTS, "WRITE_WORKOUTS")) return@launch

                val startZoneOffset = startInstant.atZone(ZoneId.systemDefault()).offset
                val endZoneOffset = endInstant.atZone(ZoneId.systemDefault()).offset

                val exerciseType = resolveExerciseType(activityTypeRaw)
                val title = metadata?.optString("title")?.takeIf { it.isNotBlank() }
                val notes = metadata?.optString("notes")?.takeIf { it.isNotBlank() }
                    ?: metadata?.optString("description")?.takeIf { it.isNotBlank() }

                val route = buildExerciseRoute(routeArray, startInstant, endInstant)
                if (route != null && !granted.contains(HealthPermission.PERMISSION_WRITE_EXERCISE_ROUTE)) {
                    call.reject("Missing WRITE_ROUTE permission")
                    return@launch
                }

                val records = mutableListOf<Record>()
                records.add(
                    ExerciseSessionRecord(
                        startTime = startInstant,
                        startZoneOffset = startZoneOffset,
                        endTime = endInstant,
                        endZoneOffset = endZoneOffset,
                        metadata = Metadata.manualEntry(),
                        exerciseType = exerciseType,
                        title = title,
                        notes = notes,
                        exerciseRoute = route
                    )
                )

                if (calories != null) {
                    when {
                        granted.contains(permissionMapping[CapHealthPermission.WRITE_ACTIVE_CALORIES]) -> {
                            records.add(
                                ActiveCaloriesBurnedRecord(
                                    startTime = startInstant,
                                    startZoneOffset = startZoneOffset,
                                    endTime = endInstant,
                                    endZoneOffset = endZoneOffset,
                                    energy = calories.kilocalories,
                                    metadata = Metadata.manualEntry()
                                )
                            )
                        }
                        granted.contains(permissionMapping[CapHealthPermission.WRITE_TOTAL_CALORIES]) -> {
                            records.add(
                                TotalCaloriesBurnedRecord(
                                    startTime = startInstant,
                                    startZoneOffset = startZoneOffset,
                                    endTime = endInstant,
                                    endZoneOffset = endZoneOffset,
                                    energy = calories.kilocalories,
                                    metadata = Metadata.manualEntry()
                                )
                            )
                        }
                        else -> {
                            call.reject("Missing WRITE_ACTIVE_CALORIES or WRITE_TOTAL_CALORIES permission")
                            return@launch
                        }
                    }
                }

                if (distance != null) {
                    if (!ensurePermission(CapHealthPermission.WRITE_DISTANCE, "WRITE_DISTANCE")) return@launch
                    records.add(
                        DistanceRecord(
                            startTime = startInstant,
                            startZoneOffset = startZoneOffset,
                            endTime = endInstant,
                            endZoneOffset = endZoneOffset,
                            distance = distance.meters,
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                val heartRateSamples = buildHeartRateSamples(heartRateArray, startInstant, endInstant)
                if (heartRateSamples.isNotEmpty()) {
                    if (!ensurePermission(CapHealthPermission.WRITE_HEART_RATE, "WRITE_HEART_RATE")) return@launch
                    records.add(
                        HeartRateRecord(
                            startTime = heartRateSamples.first().time,
                            startZoneOffset = heartRateSamples.first().time.atZone(ZoneId.systemDefault()).offset,
                            endTime = heartRateSamples.last().time,
                            endZoneOffset = heartRateSamples.last().time.atZone(ZoneId.systemDefault()).offset,
                            samples = heartRateSamples,
                            metadata = Metadata.manualEntry()
                        )
                    )
                }

                val response = healthConnectClient.insertRecords(records)
                val result = JSObject()
                result.put("success", true)
                response.recordIdsList.firstOrNull()?.let { result.put("id", it) }
                call.resolve(result)
            } catch (e: Exception) {
                call.reject("Failed to save workout: ${e.message}")
            }
        }
    }

    @PluginMethod
    fun queryWorkouts(call: PluginCall) {
        if (!ensureClientInitialized(call)) return
        val startDate = call.getString("startDate")
        val endDate = call.getString("endDate")
        val includeHeartRate: Boolean = call.getBoolean("includeHeartRate", false) == true
        val includeRoute: Boolean = call.getBoolean("includeRoute", false) == true
        val includeSteps: Boolean = call.getBoolean("includeSteps", false) == true
        if (startDate == null || endDate == null) {
            call.reject("Missing required parameters: startDate or endDate")
            return
        }

        val startDateTime = Instant.parse(startDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
        val endDateTime = Instant.parse(endDate).atZone(ZoneId.systemDefault()).toLocalDateTime()

        val timeRange = TimeRangeFilter.between(startDateTime, endDateTime)
        val request =
            ReadRecordsRequest(
                recordType = ExerciseSessionRecord::class,
                timeRangeFilter = timeRange,
                dataOriginFilter = emptySet(),
                ascendingOrder = true,
                pageSize = 1000
            )

        CoroutineScope(Dispatchers.IO).launch {
            try {
                // Check permission for heart rate before loop
                val hasHeartRatePermission = hasPermission(CapHealthPermission.READ_HEART_RATE)

                // Log warning if requested data but permission not granted
                if (includeHeartRate && !hasHeartRatePermission) {
                    Log.w(tag, "queryWorkouts: Heart rate requested but not permitted")
                }

                // Query workouts (exercise sessions)
                val response = healthConnectClient.readRecords(request)

                val workoutsArray = JSArray()

                for (workout in response.records) {
                    val workoutObject = JSObject()
                    workoutObject.put("id", workout.metadata.id)
                    val sourceModel = workout.metadata.device?.model ?: ""
                    workoutObject.put("sourceName", sourceModel)
                    workoutObject.put("sourceBundleId", workout.metadata.dataOrigin.packageName)
                    workoutObject.put("startDate", workout.startTime.toString())
                    workoutObject.put("endDate", workout.endTime.toString())
                    workoutObject.put("workoutType", exerciseTypeMapping.getOrDefault(workout.exerciseType, "OTHER"))
                    workoutObject.put("title", workout.title)
                    val duration = if (workout.segments.isEmpty()) {
                        workout.endTime.epochSecond - workout.startTime.epochSecond
                    } else {
                        workout.segments.map { it.endTime.epochSecond - it.startTime.epochSecond }
                            .stream().mapToLong { it }.sum()
                    }
                    workoutObject.put("duration", duration)

                    if (includeSteps) {
                        addWorkoutMetric(workout, workoutObject, getMetricAndMapper("steps"))
                    }

                    val derivedTotalAdded = addWorkoutTotalCalories(workout, workoutObject)
                    if (!derivedTotalAdded) {
                        val readTotalCaloriesResult = addWorkoutMetric(workout, workoutObject, getMetricAndMapper("total-calories"))
                        if(!readTotalCaloriesResult) {
                            addWorkoutMetric(workout, workoutObject, getMetricAndMapper("active-calories"))
                        }
                    }

                    addWorkoutMetric(workout, workoutObject, getMetricAndMapper("distance"))

                    if (includeHeartRate && hasHeartRatePermission) {
                        // Query and add heart rate data if requested
                        val heartRates =
                            queryHeartRateForWorkout(workout.startTime, workout.endTime)
                        if (heartRates.length() > 0) {
                            workoutObject.put("heartRate", heartRates)
                        }
                    }

                    /* Updated route logic for Health Connect RC02 */
                    if (includeRoute) {
                        if (!hasPermission(CapHealthPermission.READ_WORKOUTS)) {
                            Log.w(tag, "queryWorkouts: Route requested but READ_WORKOUTS permission missing")
                        } else if (workout.exerciseRouteResult is ExerciseRouteResult.Data) {
                            val data = workout.exerciseRouteResult as ExerciseRouteResult.Data
                            val routeJson = queryRouteForWorkout(data)
                            if (routeJson.length() > 0) {
                                workoutObject.put("route", routeJson)
                            }
                        }
                    }

                    workoutsArray.put(workoutObject)
                }

                val result = JSObject()
                result.put("workouts", workoutsArray)
                call.resolve(result)

            } catch (e: Exception) {
                call.reject("Error querying workouts: ${e.message}")
            }
        }
    }

    private suspend fun addWorkoutTotalCalories(
        workout: ExerciseSessionRecord,
        jsWorkout: JSObject
    ): Boolean {
        return try {
            val totalCalories = sumActiveAndBasalCalories(
                TimeRangeFilter.between(workout.startTime, workout.endTime),
                includeTotalMetricFallback = true
            )
            if (totalCalories != null) {
                jsWorkout.put("calories", totalCalories)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(tag, "addWorkoutTotalCalories: Failed to derive calories", e)
            false
        }
    }

    private suspend fun addWorkoutMetric(
        workout: ExerciseSessionRecord,
        jsWorkout: JSObject,
        metricAndMapper: MetricAndMapper,
    ): Boolean {
        if (!hasPermission(metricAndMapper.permission)) {
            Log.w(tag, "addWorkoutMetric: Skipped ${metricAndMapper.name} due to missing permission")
            return false
        }
        try {
            val request = AggregateRequest(
                setOf(metricAndMapper.metric),
                TimeRangeFilter.between(workout.startTime, workout.endTime),
                emptySet()
            )
            val aggregation = healthConnectClient.aggregate(request)
            val value = metricAndMapper.getValue(aggregation)
            if(value != null) {
                jsWorkout.put(metricAndMapper.name, value)
                return true
            }
        } catch (e: Exception) {
            Log.e(tag, "addWorkoutMetric: Failed to aggregate ${metricAndMapper.name}", e)
        }
        return false
    }


    private suspend fun queryHeartRateForWorkout(startTime: Instant, endTime: Instant): JSArray {
        if (!hasPermission(CapHealthPermission.READ_HEART_RATE)) {
            return JSArray()
        }

        val request =
            ReadRecordsRequest(HeartRateRecord::class, TimeRangeFilter.between(startTime, endTime))
        val heartRateRecords = healthConnectClient.readRecords(request)

        val heartRateArray = JSArray()
        val samples = heartRateRecords.records.flatMap { it.samples }
        for (sample in samples) {
            val heartRateObject = JSObject()
            heartRateObject.put("timestamp", sample.time.toString())
            heartRateObject.put("bpm", sample.beatsPerMinute)
            heartRateArray.put(heartRateObject)
        }
        return heartRateArray
    }

    private fun queryRouteForWorkout(routeResult: ExerciseRouteResult.Data): JSArray {

        val routeArray = JSArray()
        for (record in routeResult.exerciseRoute.route) {
            val routeObject = JSObject()
            routeObject.put("timestamp", record.time.toString())
            routeObject.put("lat", record.latitude)
            routeObject.put("lng", record.longitude)
            routeObject.put("alt", record.altitude)
            routeArray.put(routeObject)
        }
        return routeArray
    }

    private fun parseInstant(value: Any?): Instant? {
        return when (value) {
            is String -> {
                try {
                    Instant.parse(value)
                } catch (_: Exception) {
                    value.toDoubleOrNull()?.let { Instant.ofEpochMilli(it.toLong()) }
                }
            }
            is Number -> Instant.ofEpochMilli(value.toLong())
            else -> null
        }
    }

    private fun resolveExerciseType(activityTypeRaw: String): Int {
        val normalized = activityTypeRaw.lowercase().replace("-", "_")
        return ExerciseSessionRecord.EXERCISE_TYPE_STRING_TO_INT_MAP[normalized]
            ?: exerciseTypeMapping.entries.firstOrNull { it.value.equals(activityTypeRaw, ignoreCase = true) }?.key?.toInt()
            ?: ExerciseSessionRecord.EXERCISE_TYPE_OTHER_WORKOUT
    }

    private fun buildExerciseRoute(routeArray: JSArray?, startTime: Instant, endTime: Instant): ExerciseRoute? {
        val locations = routeArray
            ?.toList<JSObject>()
            ?.mapNotNull { point ->
                val lat = point.optDouble("lat", Double.NaN)
                val lng = point.optDouble("lng", Double.NaN)
                val ts = parseInstant(point.opt("timestamp")) ?: return@mapNotNull null
                if (lat.isNaN() || lng.isNaN()) return@mapNotNull null
                if (ts.isBefore(startTime) || ts.isAfter(endTime)) return@mapNotNull null
                val altitudeValue = point.optDouble("alt", Double.NaN)
                ExerciseRoute.Location(
                    time = ts,
                    latitude = lat,
                    longitude = lng,
                    altitude = if (altitudeValue.isNaN()) null else altitudeValue.meters
                )
            }
            ?.sortedBy { it.time }
            ?.toList()

        if (locations.isNullOrEmpty()) {
            return null
        }
        return ExerciseRoute(locations)
    }

    private fun buildHeartRateSamples(array: JSArray?, startTime: Instant, endTime: Instant): List<HeartRateRecord.Sample> {
        return array
            ?.toList<JSObject>()
            ?.mapNotNull { point ->
                val bpm = point.optDouble("bpm", Double.NaN)
                val ts = parseInstant(point.opt("timestamp")) ?: return@mapNotNull null
                if (bpm.isNaN()) return@mapNotNull null
                val clampedBpm = bpm.toLong().coerceIn(1, 300)
                HeartRateRecord.Sample(
                    time = ts,
                    beatsPerMinute = clampedBpm
                )
            }
            ?.filter { !it.time.isBefore(startTime) && !it.time.isAfter(endTime) }
            ?.sortedBy { it.time }
            ?: emptyList()
    }


    private val exerciseTypeMapping = mapOf(
        0 to "OTHER",
        2 to "BADMINTON",
        4 to "BASEBALL",
        5 to "BASKETBALL",
        8 to "BIKING",
        9 to "BIKING_STATIONARY",
        10 to "BOOT_CAMP",
        11 to "BOXING",
        13 to "CALISTHENICS",
        14 to "CRICKET",
        16 to "DANCING",
        25 to "ELLIPTICAL",
        26 to "EXERCISE_CLASS",
        27 to "FENCING",
        28 to "FOOTBALL_AMERICAN",
        29 to "FOOTBALL_AUSTRALIAN",
        31 to "FRISBEE_DISC",
        32 to "GOLF",
        33 to "GUIDED_BREATHING",
        34 to "GYMNASTICS",
        35 to "HANDBALL",
        36 to "HIGH_INTENSITY_INTERVAL_TRAINING",
        37 to "HIKING",
        38 to "ICE_HOCKEY",
        39 to "ICE_SKATING",
        44 to "MARTIAL_ARTS",
        46 to "PADDLING",
        47 to "PARAGLIDING",
        48 to "PILATES",
        50 to "RACQUETBALL",
        51 to "ROCK_CLIMBING",
        52 to "ROLLER_HOCKEY",
        53 to "ROWING",
        54 to "ROWING_MACHINE",
        55 to "RUGBY",
        56 to "RUNNING",
        57 to "RUNNING_TREADMILL",
        58 to "SAILING",
        59 to "SCUBA_DIVING",
        60 to "SKATING",
        61 to "SKIING",
        62 to "SNOWBOARDING",
        63 to "SNOWSHOEING",
        64 to "SOCCER",
        65 to "SOFTBALL",
        66 to "SQUASH",
        68 to "STAIR_CLIMBING",
        69 to "STAIR_CLIMBING_MACHINE",
        70 to "STRENGTH_TRAINING",
        71 to "STRETCHING",
        72 to "SURFING",
        73 to "SWIMMING_OPEN_WATER",
        74 to "SWIMMING_POOL",
        75 to "TABLE_TENNIS",
        76 to "TENNIS",
        78 to "VOLLEYBALL",
        79 to "WALKING",
        80 to "WATER_POLO",
        81 to "WEIGHTLIFTING",
        82 to "WHEELCHAIR",
        83 to "YOGA"
    )
}
