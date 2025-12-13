import Foundation
import Capacitor
import HealthKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(HealthPlugin)
public class HealthPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "HealthPlugin"
    public let jsName = "HealthPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isHealthAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkHealthPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestHealthPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openAppleHealthSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryAggregated", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryWorkouts", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryLatestSample", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryWeight", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryHeight", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "queryHeartRate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "querySteps", returnType: CAPPluginReturnPromise)
    ]
    
    let healthStore = HKHealthStore()
    
    /// Serial queue to make route‑location mutations thread‑safe without locks
    private let routeSyncQueue = DispatchQueue(label: "com.flomentumsolutions.healthplugin.routeSync")
    
    @objc func isHealthAvailable(_ call: CAPPluginCall) {
        let isAvailable = HKHealthStore.isHealthDataAvailable()
        call.resolve(["available": isAvailable])
    }
    
    @objc func checkHealthPermissions(_ call: CAPPluginCall) {
        guard let permissions = call.getArray("permissions") as? [String] else {
            call.reject("Invalid permissions format")
            return
        }

        var result: [String: String] = [:]

        for permission in permissions {
            let hkTypes = permissionToHKObjectType(permission)
            for type in hkTypes {
                let status = healthStore.authorizationStatus(for: type)

                switch status {
                case .notDetermined:
                    result[permission] = "notDetermined"
                case .sharingDenied:
                    result[permission] = "denied"
                case .sharingAuthorized:
                    result[permission] = "authorized"
                @unknown default:
                    result[permission] = "unknown"
                }
            }
        }

        call.resolve(["permissions": result])
    }
    
    @objc func requestHealthPermissions(_ call: CAPPluginCall) {
        guard let permissions = call.getArray("permissions") as? [String] else {
            call.reject("Invalid permissions format")
            return
        }
        
        print("⚡️ [HealthPlugin] Requesting permissions: \(permissions)")
        
        let types: [HKObjectType] = permissions.flatMap { permissionToHKObjectType($0) }
        
        print("⚡️ [HealthPlugin] Mapped to \(types.count) HKObjectTypes")
        
        // Validate that we have at least one valid permission type
        guard !types.isEmpty else {
            let invalidPermissions = permissions.filter { permissionToHKObjectType($0).isEmpty }
            call.reject("No valid permission types found. Invalid permissions: \(invalidPermissions)")
            return
        }
        
        healthStore.requestAuthorization(toShare: nil, read: Set(types)) { success, error in
            if success {
                //we don't know which actual permissions were granted, so we assume all
                var result: [String: Bool] = [:]
                permissions.forEach{ result[$0] = true }
                call.resolve(["permissions": result])
            } else if let error = error {
                call.reject("Authorization failed: \(error.localizedDescription)")
            } else {
                //assume no permissions were granted. We can ask user to adjust them manually
                var result: [String: Bool] = [:]
                permissions.forEach{ result[$0] = false }
                call.resolve(["permissions": result])
            }
        }
    }

    @objc func queryLatestSample(_ call: CAPPluginCall) {
        guard let dataTypeString = call.getString("dataType") else {
            call.reject("Missing data type")
            return
        }
        
        print("⚡️ [HealthPlugin] Querying latest sample for data type: \(dataTypeString)")
        // ---- Special handling for blood‑pressure correlation ----
        if dataTypeString == "blood-pressure" {
            guard let bpType = HKObjectType.correlationType(forIdentifier: .bloodPressure) else {
                call.reject("Blood pressure type not available")
                return
            }
            
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            
            let query = HKSampleQuery(sampleType: bpType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                
                guard let bpCorrelation = samples?.first as? HKCorrelation else {
                    if let error = error {
                        call.reject("Error fetching latest blood pressure sample", "NO_SAMPLE", error)
                    } else {
                        call.reject("No blood pressure sample found", "NO_SAMPLE")
                    }
                    return
                }
                
                let unit = HKUnit.millimeterOfMercury()
                
                let systolicSamples = bpCorrelation.objects(for: HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!)
                let diastolicSamples = bpCorrelation.objects(for: HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!)
                
                guard let systolicSample = systolicSamples.first as? HKQuantitySample,
                      let diastolicSample = diastolicSamples.first as? HKQuantitySample else {
                    call.reject("Incomplete blood pressure data", "NO_SAMPLE")
                    return
                }
                
                let systolicValue = systolicSample.quantity.doubleValue(for: unit)
                let diastolicValue = diastolicSample.quantity.doubleValue(for: unit)
                let timestamp = bpCorrelation.startDate.timeIntervalSince1970 * 1000
                
                call.resolve([
                    "systolic": systolicValue,
                    "diastolic": diastolicValue,
                    "timestamp": timestamp,
                    "unit": unit.unitString
                ])
            }
            
            healthStore.execute(query)
            return
        }
        guard aggregateTypeToHKQuantityType(dataTypeString) != nil else {
            call.reject("Invalid data type")
            return
        }

        let quantityType: HKQuantityType? = {
            switch dataTypeString {
            case "heart-rate":
                return HKObjectType.quantityType(forIdentifier: .heartRate)
            case "weight":
                return HKObjectType.quantityType(forIdentifier: .bodyMass)
            case "steps":
                return HKObjectType.quantityType(forIdentifier: .stepCount)
            case "hrv":
                return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
            case "height":
                return HKObjectType.quantityType(forIdentifier: .height)
            case "distance":
                return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
            case "active-calories":
                return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
            case "total-calories":
                return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
            case "blood-pressure":
                return nil // handled above
            default:
                return nil
            }
        }()

        guard let type = quantityType else {
            call.reject("Invalid or unsupported data type")
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)

        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
            
            print("⚡️ [HealthPlugin] Query completed for \(dataTypeString): \(samples?.count ?? 0) samples, error: \(error?.localizedDescription ?? "none")")
            
            guard let quantitySample = samples?.first as? HKQuantitySample else {
                if let error = error {
                    print("⚡️ [HealthPlugin] Error fetching \(dataTypeString): \(error.localizedDescription)")
                    call.reject("Error fetching latest sample", "NO_SAMPLE", error)
                } else {
                    print("⚡️ [HealthPlugin] No sample found for \(dataTypeString)")
                    call.reject("No sample found", "NO_SAMPLE")
                }
                return
            }

            var unit: HKUnit = .count()
            if dataTypeString == "heart-rate" {
                unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            } else if dataTypeString == "weight" {
                unit = .gramUnit(with: .kilo)
            } else if dataTypeString == "hrv" {
                unit = HKUnit.secondUnit(with: .milli)
            } else if dataTypeString == "distance" {
                unit = HKUnit.meter()
            } else if dataTypeString == "active-calories" || dataTypeString == "total-calories" {
                unit = HKUnit.kilocalorie()
            } else if dataTypeString == "height" {
                unit = HKUnit.meter()
            }
            let value = quantitySample.quantity.doubleValue(for: unit)
            let timestamp = quantitySample.startDate.timeIntervalSince1970 * 1000

            print("⚡️ [HealthPlugin] Successfully fetched \(dataTypeString): value=\(value), unit=\(unit.unitString)")

            call.resolve([
                "value": value,
                "timestamp": timestamp,
                "unit": unit.unitString
            ])
        }

        healthStore.execute(query)
    }
    
    // Convenience methods for specific data types
    @objc func queryWeight(_ call: CAPPluginCall) {
        queryLatestSampleWithType(call, dataType: "weight")
    }
    
    @objc func queryHeight(_ call: CAPPluginCall) {
        queryLatestSampleWithType(call, dataType: "height")
    }
    
    @objc func queryHeartRate(_ call: CAPPluginCall) {
        queryLatestSampleWithType(call, dataType: "heart-rate")
    }
    
    @objc func querySteps(_ call: CAPPluginCall) {
        queryLatestSampleWithType(call, dataType: "steps")
    }
    
    private func queryLatestSampleWithType(_ call: CAPPluginCall, dataType: String) {
        // Safely coerce the original options into a [String: Any] JSObject.
        let originalOptions = call.options as? [String: Any] ?? [:]
        var params = originalOptions
        params["dataType"] = dataType

        // Create a proxy CAPPluginCall using the CURRENT (Capacitor 6) designated initializer.
        // NOTE: The older init(callbackId:options:success:error:) is deprecated and *failable*,
        // so we use the newer initializer that requires a method name. Guard against failure.
        guard let proxyCall = CAPPluginCall(
            callbackId: call.callbackId,
            methodName: "queryLatestSample", // required in new API
            options: params,
            success: { result, _ in
                // Forward the resolved data back to the original JS caller.
                call.resolve(result?.data ?? [:])
            },
            error: { capError in
                // Forward the error to the original call in the legacy reject format.
                if let capError = capError {
                    call.reject(capError.message, capError.code, capError.error, capError.data)
                } else {
                    call.reject("Unknown native error")
                }
            }
        ) else {
            call.reject("Failed to create proxy call")
            return
        }

        // Delegate the actual HealthKit fetch to the common implementation.
        queryLatestSample(proxyCall)
    }
    
    @objc func openAppleHealthSettings(_ call: CAPPluginCall) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                call.resolve()
            }
        } else {
            call.reject("Unable to open app-specific settings")
        }
    }
    
    // Permission helpers
    func permissionToHKObjectType(_ permission: String) -> [HKObjectType] {
        switch permission {
        case "READ_STEPS":
            return [HKObjectType.quantityType(forIdentifier: .stepCount)].compactMap{$0}
        case "READ_WEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .bodyMass)].compactMap{$0}
        case "READ_HEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .height)].compactMap { $0 }
        case "READ_TOTAL_CALORIES":
            return [
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)   // iOS 16+
            ].compactMap { $0 }
        case "READ_ACTIVE_CALORIES":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap{$0}
        case "READ_WORKOUTS":
            return [HKObjectType.workoutType()].compactMap{$0}
        case "READ_HEART_RATE":
            return  [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap{$0}
        case "READ_ROUTE":
            return  [HKSeriesType.workoutRoute()].compactMap{$0}
        case "READ_DISTANCE":
            return [
                HKObjectType.quantityType(forIdentifier: .distanceCycling),
                HKObjectType.quantityType(forIdentifier: .distanceSwimming),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)
            ].compactMap{$0}
        case "READ_MINDFULNESS":
            return [HKObjectType.categoryType(forIdentifier: .mindfulSession)!].compactMap{$0}
        case "READ_HRV":
            return [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)].compactMap { $0 }
        case "READ_BLOOD_PRESSURE":
            return [
                HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
                HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
            ].compactMap { $0 }
        // Add common alternative permission names
        case "steps":
            return [HKObjectType.quantityType(forIdentifier: .stepCount)].compactMap{$0}
        case "weight":
            return [HKObjectType.quantityType(forIdentifier: .bodyMass)].compactMap{$0}
        case "height":
            return [HKObjectType.quantityType(forIdentifier: .height)].compactMap { $0 }
        case "calories", "total-calories":
            return [
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)   // iOS 16+
            ].compactMap { $0 }
        case "active-calories":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap{$0}
        case "workouts":
            return [HKObjectType.workoutType()].compactMap{$0}
        case "heart-rate", "heartrate", "heart_rate":
            return  [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap{$0}
        case "route":
            return  [HKSeriesType.workoutRoute()].compactMap{$0}
        case "distance":
            return [
                HKObjectType.quantityType(forIdentifier: .distanceCycling),
                HKObjectType.quantityType(forIdentifier: .distanceSwimming),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)
            ].compactMap{$0}
        case "mindfulness":
            return [HKObjectType.categoryType(forIdentifier: .mindfulSession)!].compactMap{$0}
        case "hrv", "heart_rate_variability_sdnn":
            return [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)].compactMap { $0 }
        case "blood-pressure", "bloodpressure", "blood_pressure_systolic", "blood_pressure_diastolic":
            return [
                HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
                HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
            ].compactMap { $0 }
        default:
            print("⚡️ [HealthPlugin] Unknown permission: \(permission)")
            return []
        }
    }
    
    func aggregateTypeToHKQuantityType(_ dataType: String) -> HKQuantityType? {
        switch dataType {
        case "steps":
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case "active-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "heart-rate":
            return HKObjectType.quantityType(forIdentifier: .heartRate)
        case "weight":
            return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case "hrv":
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case "distance":
            return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)  // pick one rep type
        case "total-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "height":
            return HKObjectType.quantityType(forIdentifier: .height)
        default:
            return nil
        }
    }
    
    
    @objc func queryAggregated(_ call: CAPPluginCall) {
        guard let startDateString = call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let dataTypeString = call.getString("dataType"),
              let bucket = call.getString("bucket"),
              let startDate = self.isoDateFormatter.date(from: startDateString),
              let endDate = self.isoDateFormatter.date(from: endDateString) else {
            DispatchQueue.main.async {
                call.reject("Invalid parameters")
            }
            return
        }
        if dataTypeString == "mindfulness" {
            self.queryMindfulnessAggregated(startDate: startDate, endDate: endDate) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject(error.localizedDescription)
                    } else if let result = result {
                        call.resolve(["aggregatedData": result])
                    }
                }
            }
        } else {
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            guard let interval = calculateInterval(bucket: bucket) else {
                DispatchQueue.main.async {
                    call.reject("Invalid bucket")
                }
                return
            }
            guard let dataType = aggregateTypeToHKQuantityType(dataTypeString) else {
                DispatchQueue.main.async {
                    call.reject("Invalid data type")
                }
                return
            }
            let options: HKStatisticsOptions = {
                switch dataType.aggregationStyle {
                case .cumulative:
                    return .cumulativeSum
                case .discrete,
                     .discreteArithmetic,
                     .discreteTemporallyWeighted,
                     .discreteEquivalentContinuousLevel:
                    return .discreteAverage
                @unknown default:
                    return .discreteAverage
                }
            }()
            let query = HKStatisticsCollectionQuery(
                quantityType: dataType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: startDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject("Error fetching aggregated data: \(error.localizedDescription)")
                        return
                    }
                    var aggregatedSamples: [[String: Any]] = []
                    result?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                        let quantity: HKQuantity? = options.contains(.cumulativeSum)
                            ? statistics.sumQuantity()
                            : statistics.averageQuantity()
                        guard let quantity = quantity else { return }
                        let bucketStart = statistics.startDate.timeIntervalSince1970 * 1000
                        let bucketEnd   = statistics.endDate.timeIntervalSince1970 * 1000
                        let unit: HKUnit = {
                            switch dataTypeString {
                            case "steps": return .count()
                            case "active-calories", "total-calories": return .kilocalorie()
                            case "distance": return .meter()
                            case "weight": return .gramUnit(with: .kilo)
                            case "height": return .meter()
                            case "heart-rate": return HKUnit.count().unitDivided(by: HKUnit.minute())
                            case "hrv": return HKUnit.secondUnit(with: .milli)
                            case "mindfulness": return HKUnit.second()
                            default: return .count()
                            }
                        }()
                        let value = quantity.doubleValue(for: unit)
                        aggregatedSamples.append([
                            "startDate": bucketStart,
                            "endDate":   bucketEnd,
                            "value":     value
                        ])
                    }
                    call.resolve(["aggregatedData": aggregatedSamples])
                }
            }
            healthStore.execute(query)
        }
    }

    func queryMindfulnessAggregated(startDate: Date, endDate: Date, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
        guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            DispatchQueue.main.async {
                completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "MindfulSession type unavailable"]))
            }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            var dailyDurations: [Date: TimeInterval] = [:]
            let calendar = Calendar.current
            if let categorySamples = samples as? [HKCategorySample], error == nil {
                for sample in categorySamples {
                    let startOfDay = calendar.startOfDay(for: sample.startDate)
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    dailyDurations[startOfDay, default: 0] += duration
                }
                var aggregatedSamples: [[String: Any]] = []
                let dayComponent = DateComponents(day: 1)
                for (date, duration) in dailyDurations {
                    aggregatedSamples.append([
                        "startDate": date,
                        "endDate": calendar.date(byAdding: dayComponent, to: date) as Any,
                        "value": duration
                    ])
                }
                DispatchQueue.main.async {
                    completion(aggregatedSamples, nil)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
        healthStore.execute(query)
    }

    private func queryAggregated(for startDate: Date, for endDate: Date, for dataType: HKQuantityType?, completion: @escaping (Double?) -> Void) {
        guard let quantityType = dataType else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, _ in
            let value: Double? = {
                guard let result = result, let sum = result.sumQuantity() else { return 0.0 }
                return sum.doubleValue(for: HKUnit.count())
            }()
            DispatchQueue.main.async {
                completion(value)
            }
        }
        healthStore.execute(query)
    }
    

    
    
    
    func calculateInterval(bucket: String) -> DateComponents? {
        switch bucket {
        case "hour":
            return DateComponents(hour: 1)
        case "day":
            return DateComponents(day: 1)
        case "week":
            return DateComponents(weekOfYear: 1)
        default:
            return nil
        }
    }
    
    var isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    
    @objc func queryWorkouts(_ call: CAPPluginCall) {
        guard let startDateString =  call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let includeHeartRate = call.getBool("includeHeartRate"),
              let includeRoute = call.getBool("includeRoute"),
              let includeSteps = call.getBool("includeSteps"),
              let startDate = self.isoDateFormatter.date(from: startDateString),
              let endDate = self.isoDateFormatter.date(from: endDateString) else {
            call.reject("Invalid parameters")
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let workoutQuery = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] query, samples, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    call.reject("Error querying workouts: \(error.localizedDescription)")
                }
                return
            }
            guard let workouts = samples as? [HKWorkout] else {
                DispatchQueue.main.async {
                    call.resolve(["workouts": []])
                }
                return
            }
            let outerGroup = DispatchGroup()
            let resultsQueue = DispatchQueue(label: "com.flomentumsolutions.healthplugin.workoutResults")
            var workoutResults: [[String: Any]] = []
            var errors: [String: String] = [:]
            
            for workout in workouts {
                outerGroup.enter()
                var localDict: [String: Any] = [
                    "startDate": workout.startDate,
                    "endDate": workout.endDate,
                    "workoutType": self.workoutTypeMapping[workout.workoutActivityType.rawValue, default: "other"],
                    "sourceName": workout.sourceRevision.source.name,
                    "sourceBundleId": workout.sourceRevision.source.bundleIdentifier,
                    "id": workout.uuid.uuidString,
                    "duration": workout.duration,
                    "calories": workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                    "distance": workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                ]
                let innerGroup = DispatchGroup()
                let heartRateQueue = DispatchQueue(label: "com.flomentumsolutions.healthplugin.heartRates")
                let routeQueue = DispatchQueue(label: "com.flomentumsolutions.healthplugin.routes")
                var localHeartRates: [[String: Any]] = []
                var localRoutes: [[String: Any]] = []
                
                if includeHeartRate {
                    innerGroup.enter()
                    self.queryHeartRate(for: workout) { rates, error in
                        heartRateQueue.async {
                            localHeartRates = rates
                            if let error = error {
                                errors["heart-rate"] = error
                            }
                            innerGroup.leave()
                        }
                    }
                }
                if includeRoute {
                    innerGroup.enter()
                    self.queryRoute(for: workout) { routes, error in
                        routeQueue.async {
                            localRoutes = routes
                            if let error = error {
                                errors["route"] = error
                            }
                            innerGroup.leave()
                        }
                    }
                }
                if includeSteps {
                    innerGroup.enter()
                    self.queryAggregated(for: workout.startDate, for: workout.endDate, for: HKObjectType.quantityType(forIdentifier: .stepCount)) { steps in
                        resultsQueue.async {
                            if let steps = steps {
                                localDict["steps"] = steps
                            }
                            innerGroup.leave()
                        }
                    }
                }
                innerGroup.notify(queue: resultsQueue) {
                    heartRateQueue.sync {
                        localDict["heartRate"] = localHeartRates
                    }
                    routeQueue.sync {
                        localDict["route"] = localRoutes
                    }
                    workoutResults.append(localDict)
                    outerGroup.leave()
                }
            }
            outerGroup.notify(queue: .main) {
                call.resolve(["workouts": workoutResults, "errors": errors])
            }
        }
        healthStore.execute(workoutQuery)
    }
    
    
    
    // MARK: - Query Heart Rate Data
    private func queryHeartRate(for workout: HKWorkout, completion: @escaping @Sendable ([[String: Any]], String?) -> Void) {
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        
        let heartRateQuery = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { query, samples, error in
            guard let heartRateSamplesData =  samples as? [HKQuantitySample], error == nil else {
                completion([], error?.localizedDescription)
                return
            }
            
            var heartRateSamples: [[String: Any]] = []
            
            for sample in heartRateSamplesData {
                let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                
                let sampleDict: [String: Any] = [
                    "timestamp": sample.startDate,
                    "bpm": sample.quantity.doubleValue(for: heartRateUnit)
                ]
                
                heartRateSamples.append(sampleDict)
            }
            
            
            completion(heartRateSamples, nil)
        }
        
        healthStore.execute(heartRateQuery)
    }
    
    // MARK: - Query Route Data
    private func queryRoute(for workout: HKWorkout, completion: @escaping @Sendable ([[String: Any]], String?) -> Void) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        let routeQuery = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, error in
            guard let self = self else { return }
            if let routes = samples as? [HKWorkoutRoute], error == nil {
                let routeDispatchGroup = DispatchGroup()
                let allLocationsQueue = DispatchQueue(label: "com.flomentumsolutions.healthplugin.allLocations")
                var allLocations: [[String: Any]] = []
                
                for route in routes {
                    routeDispatchGroup.enter()
                    self.queryLocations(for: route) { locations in
                        allLocationsQueue.async {
                            allLocations.append(contentsOf: locations)
                        }
                        routeDispatchGroup.leave()
                    }
                }
                routeDispatchGroup.notify(queue: .main) {
                    completion(allLocations, nil)
                }
            } else {
                DispatchQueue.main.async {
                    completion([], error?.localizedDescription)
                }
            }
        }
        
        healthStore.execute(routeQuery)
    }
    
    // MARK: - Query Route Locations
    private func queryLocations(for route: HKWorkoutRoute, completion: @escaping @Sendable ([[String: Any]]) -> Void) {
        let locationQuery = HKWorkoutRouteQuery(route: route) { [weak self] _, locations, done, error in
            guard let self = self else { return }
            guard let locations = locations, error == nil else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            // Process locations on the serial queue to avoid race conditions
            self.routeSyncQueue.async {
                var routeLocations: [[String: Any]] = []
                
                for location in locations {
                    let locationDict: [String: Any] = [
                        "timestamp": location.timestamp,
                        "lat": location.coordinate.latitude,
                        "lng": location.coordinate.longitude,
                        "alt": location.altitude
                    ]
                    routeLocations.append(locationDict)
                }

                if done {
                    DispatchQueue.main.async {
                        completion(routeLocations)
                    }
                }
            }
        }

        healthStore.execute(locationQuery)
    }
    
    
    let workoutTypeMapping: [UInt : String] =  [
        1 : "americanFootball" ,
        2 : "archery" ,
        3 : "australianFootball" ,
        4 : "badminton" ,
        5 : "baseball" ,
        6 : "basketball" ,
        7 : "bowling" ,
        8 : "boxing" ,
        9 : "climbing" ,
        10 : "cricket" ,
        11 : "crossTraining" ,
        12 : "curling" ,
        13 : "cycling" ,
        14 : "dance" ,
        15 : "danceInspiredTraining" ,
        16 : "elliptical" ,
        17 : "equestrianSports" ,
        18 : "fencing" ,
        19 : "fishing" ,
        20 : "functionalStrengthTraining" ,
        21 : "golf" ,
        22 : "gymnastics" ,
        23 : "handball" ,
        24 : "hiking" ,
        25 : "hockey" ,
        26 : "hunting" ,
        27 : "lacrosse" ,
        28 : "martialArts" ,
        29 : "mindAndBody" ,
        30 : "mixedMetabolicCardioTraining" ,
        31 : "paddleSports" ,
        32 : "play" ,
        33 : "preparationAndRecovery" ,
        34 : "racquetball" ,
        35 : "rowing" ,
        36 : "rugby" ,
        37 : "running" ,
        38 : "sailing" ,
        39 : "skatingSports" ,
        40 : "snowSports" ,
        41 : "soccer" ,
        42 : "softball" ,
        43 : "squash" ,
        44 : "stairClimbing" ,
        45 : "surfingSports" ,
        46 : "swimming" ,
        47 : "tableTennis" ,
        48 : "tennis" ,
        49 : "trackAndField" ,
        50 : "traditionalStrengthTraining" ,
        51 : "volleyball" ,
        52 : "walking" ,
        53 : "waterFitness" ,
        54 : "waterPolo" ,
        55 : "waterSports" ,
        56 : "wrestling" ,
        57 : "yoga" ,
        58 : "barre" ,
        59 : "coreTraining" ,
        60 : "crossCountrySkiing" ,
        61 : "downhillSkiing" ,
        62 : "flexibility" ,
        63 : "highIntensityIntervalTraining" ,
        64 : "jumpRope" ,
        65 : "kickboxing" ,
        66 : "pilates" ,
        67 : "snowboarding" ,
        68 : "stairs" ,
        69 : "stepTraining" ,
        70 : "wheelchairWalkPace" ,
        71 : "wheelchairRunPace" ,
        72 : "taiChi" ,
        73 : "mixedCardio" ,
        74 : "handCycling" ,
        75 : "discSports" ,
        76 : "fitnessGaming" ,
        77 : "cardioDance" ,
        78 : "socialDance" ,
        79 : "pickleball" ,
        80 : "cooldown" ,
        82 : "swimBikeRun" ,
        83 : "transition" ,
        84 : "underwaterDiving" ,
        3000 : "other"
    ]
    
}
