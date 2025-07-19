package com.flomentum.health.capacitor

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
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
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
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicReference
import androidx.core.net.toUri

enum class CapHealthPermission {
    READ_STEPS, READ_WORKOUTS, READ_HEART_RATE, READ_ACTIVE_CALORIES, READ_TOTAL_CALORIES, READ_DISTANCE, READ_WEIGHT
    , READ_HRV, READ_BLOOD_PRESSURE, READ_HEIGHT, READ_ROUTE, READ_MINDFULNESS;

    companion object {
        fun from(s: String): CapHealthPermission? {
            return try {
                CapHealthPermission.valueOf(s)
            } catch (e: Exception) {
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
        Permission(alias = "READ_DISTANCE", strings = ["android.permission.health.READ_DISTANCE"]),
        Permission(alias = "READ_ACTIVE_CALORIES", strings = ["android.permission.health.READ_ACTIVE_CALORIES_BURNED"]),
        Permission(alias = "READ_TOTAL_CALORIES", strings = ["android.permission.health.READ_TOTAL_CALORIES_BURNED"]),
        Permission(alias = "READ_HEART_RATE", strings = ["android.permission.health.READ_HEART_RATE"]),
        Permission(alias = "READ_HRV", strings = ["android.permission.health.READ_HEART_RATE_VARIABILITY"]),
        Permission(alias = "READ_BLOOD_PRESSURE", strings = ["android.permission.health.READ_BLOOD_PRESSURE"]),
        Permission(alias = "READ_ROUTE", strings = ["android.permission.health.READ_EXERCISE"]),
        Permission(alias = "READ_MINDFULNESS", strings = ["android.permission.health.READ_SLEEP"])
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
        CapHealthPermission.READ_HRV to HealthPermission.getReadPermission(HeartRateVariabilitySdnnRecord::class),
        CapHealthPermission.READ_BLOOD_PRESSURE to HealthPermission.getReadPermission(BloodPressureRecord::class),
        CapHealthPermission.READ_ROUTE to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        CapHealthPermission.READ_MINDFULNESS to HealthPermission.getReadPermission(SleepSessionRecord::class)
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

    // Helper to ensure client is initialized
    private fun ensureClientInitialized(call: PluginCall): Boolean {
        if (!available) {
            call.reject("Health Connect client not initialized. Call isHealthAvailable() first.")
            return false
        }
        return true
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

    private fun getMetricAndMapper(dataType: String): MetricAndMapper {
        return when (dataType) {
            "steps" -> metricAndMapper("steps", CapHealthPermission.READ_STEPS, StepsRecord.COUNT_TOTAL) { it?.toDouble() }
            "active-calories" -> metricAndMapper(
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
            "hrv" -> metricAndMapper("hrv", CapHealthPermission.READ_HRV, HeartRateVariabilitySdnnRecord.SDNN_AVG) { it }
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

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val result = when (dataType) {
                    "heart-rate" -> readLatestHeartRate()
                    "weight" -> readLatestWeight()
                    "height" -> readLatestHeight()
                    "steps" -> readLatestSteps()
                    "hrv" -> readLatestHrv()
                    "blood-pressure" -> readLatestBloodPressure()
                    "distance" -> readLatestDistance()
                    "active-calories" -> readLatestActiveCalories()
                    "total-calories" -> readLatestTotalCalories()
                    else -> {
                        call.reject("Unsupported data type: $dataType")
                        return@launch
                    }
                }
                call.resolve(result)
            } catch (e: Exception) {
                Log.e(tag, "queryLatestSample: Error fetching latest $dataType", e)
                call.reject("Error fetching latest $dataType: ${e.message}")
            }
        }
    }

    // Convenience methods for specific data types
    @PluginMethod
    fun queryWeight(call: PluginCall) {
        call.put("dataType", "weight")
        queryLatestSample(call)
    }

    @PluginMethod
    fun queryHeight(call: PluginCall) {
        call.put("dataType", "height")
        queryLatestSample(call)
    }

    @PluginMethod
    fun queryHeartRate(call: PluginCall) {
        call.put("dataType", "heart-rate")
        queryLatestSample(call)
    }

    @PluginMethod
    fun querySteps(call: PluginCall) {
        call.put("dataType", "steps")
        queryLatestSample(call)
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
            pageSize = 1
        )
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No weight data found")
        return JSObject().apply {
            put("value", record.weight.inKilograms)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No step data found")
        return JSObject().apply {
            put("value", record.count)
            put("timestamp", record.endTime.epochSecond * 1000) // Convert to milliseconds like iOS
            put("unit", "count")
        }
    }

    private suspend fun readLatestHrv(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_HRV)) {
            throw Exception("Permission for HRV not granted")
        }
        val request = ReadRecordsRequest(
            recordType = HeartRateVariabilitySdnnRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No HRV data found")
        return JSObject().apply {
            put("value", record.sdnnMillis)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No blood pressure data found")
        return JSObject().apply {
            put("systolic", record.systolic.inMillimetersOfMercury)
            put("diastolic", record.diastolic.inMillimetersOfMercury)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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
            pageSize = 1
        )
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No height data found")
        return JSObject().apply {
            put("value", record.height.inMeters)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No distance data found")
        return JSObject().apply {
            put("value", record.distance.inMeters)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No active calories data found")
        return JSObject().apply {
            put("value", record.activeCalories.inKilocalories)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
            put("unit", "kcal")
        }
    }

    private suspend fun readLatestTotalCalories(): JSObject {
        if (!hasPermission(CapHealthPermission.READ_TOTAL_CALORIES)) {
            throw Exception("Permission for total calories not granted")
        }
        val request = ReadRecordsRequest(
            recordType = TotalCaloriesBurnedRecord::class,
            timeRangeFilter = TimeRangeFilter.after(Instant.EPOCH),
            pageSize = 1
        )
        val result = healthConnectClient.readRecords(request)
        val record = result.records.firstOrNull() ?: throw Exception("No total calories data found")
        return JSObject().apply {
            put("value", record.energy.inKilocalories)
            put("timestamp", record.time.epochSecond * 1000) // Convert to milliseconds like iOS
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

            val startDateTime = Instant.parse(startDate).atZone(ZoneId.systemDefault()).toLocalDateTime()
            val endDateTime = Instant.parse(endDate).atZone(ZoneId.systemDefault()).toLocalDateTime()

            val metricAndMapper = getMetricAndMapper(dataType)

            val period = when (bucket) {
                "day" -> Period.ofDays(1)
                else -> throw RuntimeException("Unsupported bucket: $bucket")
            }

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val r = queryAggregatedMetric(metricAndMapper, TimeRangeFilter.between(startDateTime, endDateTime), period)
                    val aggregatedList = JSArray()
                    r.forEach { aggregatedList.put(it.toJs()) }
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
            val mappedValue = metricAndMapper.getValue(it.result)
            AggregatedSample(it.startTime, it.endTime, mappedValue)
        }

    }

    private suspend fun hasPermission(p: CapHealthPermission): Boolean {
        val granted = healthConnectClient.permissionController.getGrantedPermissions()
        val targetPermission = permissionMapping[p]
        return granted.contains(targetPermission)
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
            ReadRecordsRequest(ExerciseSessionRecord::class, timeRange, emptySet(), true, 1000)

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

                    val readTotalCaloriesResult = addWorkoutMetric(workout, workoutObject, getMetricAndMapper("total-calories"))
                    if(!readTotalCaloriesResult) {
                        addWorkoutMetric(workout, workoutObject, getMetricAndMapper("active-calories"))
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
                TimeRangeFilter.Companion.between(workout.startTime, workout.endTime),
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