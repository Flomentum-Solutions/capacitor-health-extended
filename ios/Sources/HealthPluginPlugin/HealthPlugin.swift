import Foundation
import UIKit
import Capacitor
import HealthKit
import CoreLocation

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
        CAPPluginMethod(name: "getCharacteristics", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveMetrics", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveWorkout", returnType: CAPPluginReturnPromise)
    ]
    
    let healthStore = HKHealthStore()
    
    /// Serial queue to make route‑location mutations thread‑safe without locks
    private let routeSyncQueue = DispatchQueue(label: "com.flomentumsolutions.capacitorhealthextended.routeSync")

    private enum CharacteristicField: String, CaseIterable {
        case biologicalSex
        case bloodType
        case dateOfBirth
        case fitzpatrickSkinType
        case wheelchairUse

        var hkObjectType: HKObjectType? {
            switch self {
            case .biologicalSex:
                return HKObjectType.characteristicType(forIdentifier: .biologicalSex)
            case .bloodType:
                return HKObjectType.characteristicType(forIdentifier: .bloodType)
            case .dateOfBirth:
                return HKObjectType.characteristicType(forIdentifier: .dateOfBirth)
            case .fitzpatrickSkinType:
                return HKObjectType.characteristicType(forIdentifier: .fitzpatrickSkinType)
            case .wheelchairUse:
                return HKObjectType.characteristicType(forIdentifier: .wheelchairUse)
            }
        }
    }
    
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
            let hkTypes = permissionToHKObjectType(permission) + permissionToHKSampleType(permission)
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
        
        let readTypes: [HKObjectType] = permissions.flatMap { permissionToHKObjectType($0) }
        let shareTypes: [HKSampleType] = permissions.flatMap { permissionToHKSampleType($0) }
        
        print("⚡️ [HealthPlugin] Mapped to \(readTypes.count) HKObjectTypes (read) and \(shareTypes.count) HKSampleTypes (share)")
        
        // Validate that we have at least one valid permission type
        guard !readTypes.isEmpty || !shareTypes.isEmpty else {
            let invalidPermissions = permissions.filter { permissionToHKObjectType($0).isEmpty }
            call.reject("No valid permission types found. Invalid permissions: \(invalidPermissions)")
            return
        }
        
        DispatchQueue.main.async {
            self.healthStore.requestAuthorization(toShare: Set(shareTypes), read: Set(readTypes)) { success, error in
                DispatchQueue.main.async {
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
        }
    }

    @objc func getCharacteristics(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.resolve([
                "platformSupported": false,
                "platformMessage": "Health data is unavailable on this device."
            ])
            return
        }

        let requestedFields = call.getArray("fields") as? [String] ?? []
        let fieldsToLoad: [CharacteristicField]
        if requestedFields.isEmpty {
            fieldsToLoad = CharacteristicField.allCases
        } else {
            var normalized: [CharacteristicField] = []
            var invalid: [String] = []

            for name in requestedFields {
                if let field = CharacteristicField(rawValue: name) {
                    if !normalized.contains(field) {
                        normalized.append(field)
                    }
                } else {
                    invalid.append(name)
                }
            }

            if !invalid.isEmpty {
                let validFields = CharacteristicField.allCases.map { $0.rawValue }.joined(separator: ", ")
                call.reject("Invalid characteristic field(s): \(invalid.joined(separator: ", ")). Valid fields are: \(validFields)")
                return
            }

            fieldsToLoad = normalized.isEmpty ? CharacteristicField.allCases : normalized
        }

        let characteristicTypes: [HKObjectType] = fieldsToLoad.compactMap { $0.hkObjectType }

        if characteristicTypes.count != fieldsToLoad.count {
            let missing = fieldsToLoad.filter { $0.hkObjectType == nil }.map { $0.rawValue }
            let missingList = missing.joined(separator: ", ")
            let message = missing.isEmpty ? "HealthKit characteristics are unavailable on this device." : "Requested characteristics are unavailable on this device: \(missingList)"
            call.reject(message)
            return
        }

        guard !characteristicTypes.isEmpty else {
            call.reject("HealthKit characteristics are unavailable on this device.")
            return
        }

        func resolveCharacteristics(for fields: [CharacteristicField]) {
            var result: [String: Any] = [:]

            func setValue(_ key: CharacteristicField, _ value: String?) {
                result[key.rawValue] = value ?? NSNull()
            }

            for field in fields {
                switch field {
                case .biologicalSex:
                    if let biologicalSexObject = try? healthStore.biologicalSex() {
                        setValue(field, mapBiologicalSex(biologicalSexObject.biologicalSex))
                    } else {
                        setValue(field, nil)
                    }
                case .bloodType:
                    if let bloodTypeObject = try? healthStore.bloodType() {
                        setValue(field, mapBloodType(bloodTypeObject.bloodType))
                    } else {
                        setValue(field, nil)
                    }
                case .dateOfBirth:
                    if let dateComponents = try? healthStore.dateOfBirthComponents() {
                        setValue(field, isoBirthDateString(from: dateComponents))
                    } else {
                        setValue(field, nil)
                    }
                case .fitzpatrickSkinType:
                    if let fitzpatrickObject = try? healthStore.fitzpatrickSkinType() {
                        setValue(field, mapFitzpatrickSkinType(fitzpatrickObject.skinType))
                    } else {
                        setValue(field, nil)
                    }
                case .wheelchairUse:
                    if let wheelchairUseObject = try? healthStore.wheelchairUse() {
                        setValue(field, mapWheelchairUse(wheelchairUseObject.wheelchairUse))
                    } else {
                        setValue(field, nil)
                    }
                }
            }

            result["platformSupported"] = true
            call.resolve(result)
        }

        func requestCharacteristicsAccess(for fields: [CharacteristicField], types: [HKObjectType]) {
            self.healthStore.requestAuthorization(toShare: nil, read: Set(types)) { success, error in
                DispatchQueue.main.async {
                    if success {
                        resolveCharacteristics(for: fields)
                    } else if let error = error {
                        call.reject("Authorization failed: \(error.localizedDescription)")
                    } else {
                        call.resolve([
                            "platformSupported": true,
                            "platformMessage": "Characteristics access was not granted. Update permissions in the Health app."
                        ])
                    }
                }
            }
        }

        healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: Set(characteristicTypes)) { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    call.reject("Failed to determine HealthKit authorization status: \(error.localizedDescription)")
                    return
                }

                switch status {
                case .shouldRequest, .unknown:
                    requestCharacteristicsAccess(for: fieldsToLoad, types: characteristicTypes)
                default:
                    resolveCharacteristics(for: fieldsToLoad)
                }
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
        // ---- Derived total calories (active + basal) ----
        if dataTypeString == "total-calories" {
            queryLatestTotalCalories(call)
            return
        }
        // ---- Special handling for sleep sessions (category samples) ----
        if dataTypeString == "sleep" {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                call.reject("Sleep type not available")
                return
            }

            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .hour, value: -36, to: endDate) ?? endDate.addingTimeInterval(-36 * 3600)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)

            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    call.reject("Error fetching latest sleep sample", "NO_SAMPLE", error)
                    return
                }
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    call.reject("No sleep sample found", "NO_SAMPLE")
                    return
                }

                let asleepValues: Set<Int> = {
                    if #available(iOS 16.0, *) {
                        return Set([
                            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        ])
                    } else {
                        // Pre-iOS 16 only exposes the legacy "asleep" value.
                        return Set([HKCategoryValueSleepAnalysis.asleep.rawValue])
                    }
                }()

                func isAsleep(_ value: Int) -> Bool {
                    if asleepValues.contains(value) {
                        return true
                    }
                    // Fallback: treat any non in-bed/awake as asleep
                    return value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
                        value != HKCategoryValueSleepAnalysis.awake.rawValue
                }

                let asleepSamples = categorySamples
                    .filter { isAsleep($0.value) }
                    .sorted { $0.startDate < $1.startDate }

                guard !asleepSamples.isEmpty else {
                    call.reject("No sleep sample found", "NO_SAMPLE")
                    return
                }

                let maxGap: TimeInterval = 90 * 60 // 90 minutes separates sessions
                var sessions: [(start: Date, end: Date, duration: TimeInterval)] = []
                var currentStart: Date?
                var currentEnd: Date?
                var currentDuration: TimeInterval = 0

                for sample in asleepSamples {
                    if let lastEnd = currentEnd, sample.startDate.timeIntervalSince(lastEnd) > maxGap {
                        sessions.append((start: currentStart ?? lastEnd, end: lastEnd, duration: currentDuration))
                        currentStart = nil
                        currentEnd = nil
                        currentDuration = 0
                    }
                    if currentStart == nil { currentStart = sample.startDate }
                    currentEnd = sample.endDate
                    currentDuration += sample.endDate.timeIntervalSince(sample.startDate)
                }
                if let start = currentStart, let end = currentEnd {
                    sessions.append((start: start, end: end, duration: currentDuration))
                }

                guard !sessions.isEmpty else {
                    call.reject("No sleep sample found", "NO_SAMPLE")
                    return
                }

                let minSessionDuration: TimeInterval = 3 * 3600 // prefer sessions 3h+
                let preferredSession = sessions.reversed().first { $0.duration >= minSessionDuration } ?? sessions.last!

                call.resolve([
                    "value": preferredSession.duration / 60,
                    "timestamp": preferredSession.start.timeIntervalSince1970 * 1000,
                    "endTimestamp": preferredSession.end.timeIntervalSince1970 * 1000,
                    "unit": "min"
                ])
            }
            healthStore.execute(query)
            return
        }
        // ---- Special handling for REM sleep sessions (category samples) ----
        if dataTypeString == "sleep-rem" {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                call.reject("Sleep type not available")
                return
            }

            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .hour, value: -36, to: endDate) ?? endDate.addingTimeInterval(-36 * 3600)
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)

            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    call.reject("Error fetching latest REM sleep sample", "NO_SAMPLE", error)
                    return
                }
                guard let categorySamples = samples as? [HKCategorySample], !categorySamples.isEmpty else {
                    call.reject("No REM sleep sample found", "NO_SAMPLE")
                    return
                }

                let asleepValues: Set<Int> = {
                    if #available(iOS 16.0, *) {
                        return Set([
                            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        ])
                    } else {
                        return Set([HKCategoryValueSleepAnalysis.asleep.rawValue])
                    }
                }()

                let remValue: Int? = {
                    if #available(iOS 16.0, *) {
                        return HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    }
                    return nil
                }()

                func isAsleep(_ value: Int) -> Bool {
                    if asleepValues.contains(value) {
                        return true
                    }
                    return value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
                        value != HKCategoryValueSleepAnalysis.awake.rawValue
                }

                let asleepSamples = categorySamples
                    .filter { isAsleep($0.value) }
                    .sorted { $0.startDate < $1.startDate }

                guard !asleepSamples.isEmpty else {
                    call.reject("No REM sleep sample found", "NO_SAMPLE")
                    return
                }

                let maxGap: TimeInterval = 90 * 60 // 90 minutes separates sessions
                var sessions: [(start: Date, end: Date, duration: TimeInterval, remDuration: TimeInterval)] = []
                var currentStart: Date?
                var currentEnd: Date?
                var currentDuration: TimeInterval = 0
                var currentRemDuration: TimeInterval = 0

                for sample in asleepSamples {
                    if let lastEnd = currentEnd, sample.startDate.timeIntervalSince(lastEnd) > maxGap {
                        sessions.append((start: currentStart ?? lastEnd, end: lastEnd, duration: currentDuration, remDuration: currentRemDuration))
                        currentStart = nil
                        currentEnd = nil
                        currentDuration = 0
                        currentRemDuration = 0
                    }
                    if currentStart == nil { currentStart = sample.startDate }
                    currentEnd = sample.endDate
                    let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
                    currentDuration += sampleDuration
                    if let remValue = remValue, sample.value == remValue {
                        currentRemDuration += sampleDuration
                    }
                }
                if let start = currentStart, let end = currentEnd {
                    sessions.append((start: start, end: end, duration: currentDuration, remDuration: currentRemDuration))
                }

                guard !sessions.isEmpty else {
                    call.reject("No REM sleep sample found", "NO_SAMPLE")
                    return
                }

                let minSessionDuration: TimeInterval = 3 * 3600 // prefer sessions 3h+
                let preferredSession = sessions.reversed().first { $0.duration >= minSessionDuration } ?? sessions.last!
                if preferredSession.remDuration <= 0 {
                    call.reject("No REM sleep sample found", "NO_SAMPLE")
                    return
                }

                call.resolve([
                    "value": preferredSession.remDuration / 60,
                    "timestamp": preferredSession.start.timeIntervalSince1970 * 1000,
                    "endTimestamp": preferredSession.end.timeIntervalSince1970 * 1000,
                    "unit": "min"
                ])
            }
            healthStore.execute(query)
            return
        }
        // ---- Special handling for mindfulness sessions (category samples) ----
        if dataTypeString == "mindfulness" {
            guard let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
                call.reject("Mindfulness type not available")
                return
            }
            
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
            
            let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
                guard let mindfulSample = samples?.first as? HKCategorySample else {
                    if let error = error {
                        call.reject("Error fetching latest mindfulness sample", "NO_SAMPLE", error)
                    } else {
                        call.reject("No mindfulness sample found", "NO_SAMPLE")
                    }
                    return
                }
                let durationMinutes = mindfulSample.endDate.timeIntervalSince(mindfulSample.startDate) / 60
                call.resolve([
                    "value": durationMinutes,
                    "timestamp": mindfulSample.startDate.timeIntervalSince1970 * 1000,
                    "endTimestamp": mindfulSample.endDate.timeIntervalSince1970 * 1000,
                    "unit": "min",
                    "metadata": ["value": mindfulSample.value]
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
            case "resting-heart-rate":
                return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
            case "respiratory-rate":
                return HKObjectType.quantityType(forIdentifier: .respiratoryRate)
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
        case "distance-cycling":
            return HKObjectType.quantityType(forIdentifier: .distanceCycling)
        case "active-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "basal-calories":
            return HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        case "blood-pressure":
            return nil // handled above
        case "oxygen-saturation":
                return HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
            case "blood-glucose":
                return HKObjectType.quantityType(forIdentifier: .bloodGlucose)
            case "body-temperature":
                return HKObjectType.quantityType(forIdentifier: .bodyTemperature)
            case "basal-body-temperature":
                return HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)
            case "body-fat":
                return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
            case "flights-climbed":
                return HKObjectType.quantityType(forIdentifier: .flightsClimbed)
            case "exercise-time":
                return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
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
            } else if dataTypeString == "resting-heart-rate" {
                unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            } else if dataTypeString == "weight" {
                unit = .gramUnit(with: .kilo)
            } else if dataTypeString == "hrv" {
                unit = HKUnit.secondUnit(with: .milli)
            } else if dataTypeString == "distance" {
                unit = HKUnit.meter()
            } else if dataTypeString == "distance-cycling" {
                unit = HKUnit.meter()
            } else if dataTypeString == "active-calories" || dataTypeString == "total-calories" {
                unit = HKUnit.kilocalorie()
            } else if dataTypeString == "basal-calories" {
                unit = HKUnit.kilocalorie()
            } else if dataTypeString == "height" {
                unit = HKUnit.meter()
            } else if dataTypeString == "oxygen-saturation" {
                unit = HKUnit.percent()
            } else if dataTypeString == "blood-glucose" {
                unit = HKUnit(from: "mg/dL")
            } else if dataTypeString == "body-temperature" || dataTypeString == "basal-body-temperature" {
                unit = HKUnit.degreeCelsius()
            } else if dataTypeString == "body-fat" {
                unit = HKUnit.percent()
            } else if dataTypeString == "flights-climbed" {
                unit = HKUnit.count()
            } else if dataTypeString == "exercise-time" {
                unit = HKUnit.minute()
            } else if dataTypeString == "respiratory-rate" {
                unit = HKUnit.count().unitDivided(by: HKUnit.minute())
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
    
    @objc func saveMetrics(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("Health data is unavailable on this device.")
            return
        }

        let weightKg = call.getDouble("weightKg")
        let heightCm = call.getDouble("heightCm")
        let bodyFatPercent = call.getDouble("bodyFatPercent")
        let restingHeartRate = call.getDouble("restingHeartRate")

        if weightKg == nil && heightCm == nil && bodyFatPercent == nil && restingHeartRate == nil {
            call.reject("No metrics provided")
            return
        }

        let shareTypes: Set<HKSampleType> = [
            weightKg != nil ? HKObjectType.quantityType(forIdentifier: .bodyMass) : nil,
            heightCm != nil ? HKObjectType.quantityType(forIdentifier: .height) : nil,
            bodyFatPercent != nil ? HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) : nil,
            restingHeartRate != nil ? HKObjectType.quantityType(forIdentifier: .restingHeartRate) : nil
        ].compactMap { $0 as? HKSampleType }.reduce(into: Set<HKSampleType>()) { $0.insert($1) }

        guard !shareTypes.isEmpty else {
            call.reject("No valid metric types available on this device")
            return
        }

        healthStore.requestAuthorization(toShare: shareTypes, read: nil) { [weak self] success, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    call.reject("Authorization failed: \(error.localizedDescription)")
                    return
                }
                guard success else {
                    call.reject("Authorization not granted for metrics")
                    return
                }

                let now = Date()
                var samples: [HKSample] = []

                if let weightKg = weightKg, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) {
                    let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weightKg)
                    samples.append(HKQuantitySample(type: type, quantity: quantity, start: now, end: now, metadata: nil))
                }

                if let heightCm = heightCm, let type = HKObjectType.quantityType(forIdentifier: .height) {
                    let quantity = HKQuantity(unit: HKUnit.meter(), doubleValue: heightCm / 100.0)
                    samples.append(HKQuantitySample(type: type, quantity: quantity, start: now, end: now, metadata: nil))
                }

                if let bodyFatPercent = bodyFatPercent, let type = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
                    let quantity = HKQuantity(unit: HKUnit.percent(), doubleValue: bodyFatPercent / 100.0)
                    samples.append(HKQuantitySample(type: type, quantity: quantity, start: now, end: now, metadata: nil))
                }

                if let restingHeartRate = restingHeartRate, let type = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
                    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                    let quantity = HKQuantity(unit: unit, doubleValue: restingHeartRate)
                    samples.append(HKQuantitySample(type: type, quantity: quantity, start: now, end: now, metadata: nil))
                }

                guard !samples.isEmpty else {
                    call.reject("No metrics to save after validation")
                    return
                }

                self.healthStore.save(samples) { saveSuccess, saveError in
                    DispatchQueue.main.async {
                        if let saveError = saveError {
                            call.reject("Failed to save metrics: \(saveError.localizedDescription)")
                        } else if !saveSuccess {
                            call.reject("Failed to save metrics")
                        } else {
                            call.resolve(["success": true, "inserted": samples.count])
                        }
                    }
                }
            }
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
        case "WRITE_TOTAL_CALORIES":
            return [
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
            ].compactMap { $0 }
        case "READ_ACTIVE_CALORIES":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap{$0}
        case "WRITE_ACTIVE_CALORIES":
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap{$0}
        case "READ_WORKOUTS":
            return [HKObjectType.workoutType()].compactMap{$0}
        case "WRITE_WORKOUTS":
            return [HKObjectType.workoutType()].compactMap{$0}
        case "READ_HEART_RATE":
            return  [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap{$0}
        case "WRITE_HEART_RATE":
            return  [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap{$0}
        case "READ_RESTING_HEART_RATE":
            return [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap { $0 }
        case "READ_ROUTE":
            return  [HKSeriesType.workoutRoute()].compactMap{$0}
        case "WRITE_ROUTE":
            return  [HKSeriesType.workoutRoute()].compactMap{$0}
        case "WRITE_WEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .bodyMass)].compactMap { $0 as? HKSampleType }
        case "WRITE_HEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .height)].compactMap { $0 as? HKSampleType }
        case "WRITE_BODY_FAT":
            return [HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)].compactMap { $0 as? HKSampleType }
        case "WRITE_RESTING_HEART_RATE":
            return [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap { $0 as? HKSampleType }
        case "READ_DISTANCE":
            return [
                HKObjectType.quantityType(forIdentifier: .distanceCycling),
                HKObjectType.quantityType(forIdentifier: .distanceSwimming),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)
            ].compactMap{$0}
        case "WRITE_DISTANCE":
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
        case "READ_RESPIRATORY_RATE":
            return [HKObjectType.quantityType(forIdentifier: .respiratoryRate)].compactMap { $0 }
        case "READ_OXYGEN_SATURATION":
            return [HKObjectType.quantityType(forIdentifier: .oxygenSaturation)].compactMap { $0 }
        case "READ_BLOOD_GLUCOSE":
            return [HKObjectType.quantityType(forIdentifier: .bloodGlucose)].compactMap { $0 }
        case "READ_BODY_TEMPERATURE":
            return [HKObjectType.quantityType(forIdentifier: .bodyTemperature)].compactMap { $0 }
        case "READ_BASAL_BODY_TEMPERATURE":
            return [HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)].compactMap { $0 }
        case "READ_BODY_FAT":
            return [HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)].compactMap { $0 }
        case "READ_FLOORS_CLIMBED":
            return [HKObjectType.quantityType(forIdentifier: .flightsClimbed)].compactMap { $0 }
        case "READ_BASAL_CALORIES":
            return [
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
            ].compactMap { $0 }
        case "READ_SLEEP":
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!].compactMap { $0 }
        case "READ_EXERCISE_TIME":
            return [HKObjectType.quantityType(forIdentifier: .appleExerciseTime)].compactMap { $0 }
        case "READ_BIOLOGICAL_SEX":
            return [HKObjectType.characteristicType(forIdentifier: .biologicalSex)].compactMap { $0 }
        case "READ_BLOOD_TYPE":
            return [HKObjectType.characteristicType(forIdentifier: .bloodType)].compactMap { $0 }
        case "READ_DATE_OF_BIRTH":
            return [HKObjectType.characteristicType(forIdentifier: .dateOfBirth)].compactMap { $0 }
        case "READ_FITZPATRICK_SKIN_TYPE":
            return [HKObjectType.characteristicType(forIdentifier: .fitzpatrickSkinType)].compactMap { $0 }
        case "READ_WHEELCHAIR_USE":
            return [HKObjectType.characteristicType(forIdentifier: .wheelchairUse)].compactMap { $0 }
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
        case "respiratory-rate":
            return [HKObjectType.quantityType(forIdentifier: .respiratoryRate)].compactMap { $0 }
        case "oxygen-saturation":
            return [HKObjectType.quantityType(forIdentifier: .oxygenSaturation)].compactMap { $0 }
        case "blood-glucose":
            return [HKObjectType.quantityType(forIdentifier: .bloodGlucose)].compactMap { $0 }
        case "body-temperature":
            return [HKObjectType.quantityType(forIdentifier: .bodyTemperature)].compactMap { $0 }
        case "basal-body-temperature":
            return [HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)].compactMap { $0 }
        case "body-fat":
            return [HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)].compactMap { $0 }
        case "flights-climbed":
            return [HKObjectType.quantityType(forIdentifier: .flightsClimbed)].compactMap { $0 }
        case "basal-calories":
            return [HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)].compactMap { $0 }
        case "exercise-time":
            return [HKObjectType.quantityType(forIdentifier: .appleExerciseTime)].compactMap { $0 }
        case "sleep":
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!].compactMap { $0 }
        default:
            print("⚡️ [HealthPlugin] Unknown permission: \(permission)")
            return []
        }
    }

    func permissionToHKSampleType(_ permission: String) -> [HKSampleType] {
        switch permission {
        case "WRITE_WORKOUTS":
            return [HKObjectType.workoutType()].compactMap { $0 as? HKSampleType }
        case "WRITE_ACTIVE_CALORIES":
            fallthrough
        case "WRITE_TOTAL_CALORIES":
            return [
                HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
                HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
            ].compactMap { $0 as? HKSampleType }
        case "WRITE_DISTANCE":
            return [
                HKObjectType.quantityType(forIdentifier: .distanceCycling),
                HKObjectType.quantityType(forIdentifier: .distanceSwimming),
                HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKObjectType.quantityType(forIdentifier: .distanceDownhillSnowSports)
            ].compactMap { $0 as? HKSampleType }
        case "WRITE_HEART_RATE":
            return [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap { $0 as? HKSampleType }
        case "WRITE_ROUTE":
            return [HKSeriesType.workoutRoute()].compactMap { $0 as? HKSampleType }
        case "WRITE_WEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .bodyMass)].compactMap { $0 as? HKSampleType }
        case "WRITE_HEIGHT":
            return [HKObjectType.quantityType(forIdentifier: .height)].compactMap { $0 as? HKSampleType }
        case "WRITE_BODY_FAT":
            return [HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)].compactMap { $0 as? HKSampleType }
        case "WRITE_RESTING_HEART_RATE":
            return [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap { $0 as? HKSampleType }
        default:
            // Avoid requesting write/share authorization when only read permissions are supplied.
            return []
        }
    }

    private func mapBiologicalSex(_ biologicalSex: HKBiologicalSex) -> String {
        switch biologicalSex {
        case .female:
            return "female"
        case .male:
            return "male"
        case .other:
            return "other"
        case .notSet:
            return "not_set"
        @unknown default:
            return "unknown"
        }
    }

    private func mapBloodType(_ bloodType: HKBloodType) -> String {
        switch bloodType {
        case .aPositive:
            return "a-positive"
        case .aNegative:
            return "a-negative"
        case .bPositive:
            return "b-positive"
        case .bNegative:
            return "b-negative"
        case .abPositive:
            return "ab-positive"
        case .abNegative:
            return "ab-negative"
        case .oPositive:
            return "o-positive"
        case .oNegative:
            return "o-negative"
        case .notSet:
            return "not_set"
        @unknown default:
            return "unknown"
        }
    }

    private func mapFitzpatrickSkinType(_ skinType: HKFitzpatrickSkinType) -> String {
        switch skinType {
        case .I:
            return "type1"
        case .II:
            return "type2"
        case .III:
            return "type3"
        case .IV:
            return "type4"
        case .V:
            return "type5"
        case .VI:
            return "type6"
        case .notSet:
            return "not_set"
        @unknown default:
            return "unknown"
        }
    }

    private func mapWheelchairUse(_ wheelchairUse: HKWheelchairUse) -> String {
        switch wheelchairUse {
        case .yes:
            return "wheelchair_user"
        case .no:
            return "not_wheelchair_user"
        case .notSet:
            return "not_set"
        @unknown default:
            return "unknown"
        }
    }

    private func isoBirthDateString(from components: DateComponents) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func aggregateTypeToHKQuantityType(_ dataType: String) -> HKQuantityType? {
        switch dataType {
        case "steps":
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case "active-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "heart-rate":
            return HKObjectType.quantityType(forIdentifier: .heartRate)
        case "resting-heart-rate":
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case "weight":
            return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case "hrv":
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case "distance":
            return HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)  // pick one rep type
        case "distance-cycling":
            return HKObjectType.quantityType(forIdentifier: .distanceCycling)
        case "total-calories":
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case "basal-calories":
            return HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        case "height":
            return HKObjectType.quantityType(forIdentifier: .height)
        case "respiratory-rate":
            return HKObjectType.quantityType(forIdentifier: .respiratoryRate)
        case "oxygen-saturation":
            return HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case "blood-glucose":
            return HKObjectType.quantityType(forIdentifier: .bloodGlucose)
        case "body-temperature":
            return HKObjectType.quantityType(forIdentifier: .bodyTemperature)
        case "basal-body-temperature":
            return HKObjectType.quantityType(forIdentifier: .basalBodyTemperature)
        case "body-fat":
            return HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        case "flights-climbed":
            return HKObjectType.quantityType(forIdentifier: .flightsClimbed)
        case "exercise-time":
            return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        default:
            return nil
        }
    }
    
    
    @objc func queryAggregated(_ call: CAPPluginCall) {
        guard let startDateString = call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let dataTypeString = call.getString("dataType"),
              let bucket = call.getString("bucket"),
              let rawStartDate = self.isoDateFormatter.date(from: startDateString),
              let rawEndDate = self.isoDateFormatter.date(from: endDateString) else {
            DispatchQueue.main.async {
                call.reject("Invalid parameters")
            }
            return
        }
        let calendar = Calendar.current
        var startDate = rawStartDate
        var endDate = rawEndDate
        if bucket == "day" {
            startDate = calendar.startOfDay(for: rawStartDate)
            let endDayStart = calendar.startOfDay(for: rawEndDate)
            endDate = calendar.date(byAdding: .day, value: 1, to: endDayStart) ?? endDayStart
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
        } else if dataTypeString == "blood-pressure" {
            guard bucket == "day" else {
                DispatchQueue.main.async {
                    call.reject("Blood pressure aggregation only supports daily buckets")
                }
                return
            }
            self.queryBloodPressureAggregated(startDate: startDate, endDate: endDate) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject(error.localizedDescription)
                    } else if let result = result {
                        call.resolve(["aggregatedData": result])
                    }
                }
            }
        } else if dataTypeString == "total-calories" {
            guard let interval = calculateInterval(bucket: bucket) else {
                DispatchQueue.main.async {
                    call.reject("Invalid bucket")
                }
                return
            }
            self.queryTotalCaloriesAggregated(startDate: startDate, endDate: endDate, interval: interval) { result, error in
                DispatchQueue.main.async {
                    if let error = error {
                        call.reject(error.localizedDescription)
                    } else if let result = result {
                        call.resolve(["aggregatedData": result])
                    }
                }
            }
        } else if dataTypeString == "sleep" {
            self.querySleepAggregated(startDate: startDate, endDate: endDate) { result, error in
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
                            case "active-calories", "total-calories", "basal-calories": return .kilocalorie()
                            case "distance", "distance-cycling": return .meter()
                            case "weight": return .gramUnit(with: .kilo)
                            case "height": return .meter()
                            case "heart-rate", "resting-heart-rate": return HKUnit.count().unitDivided(by: HKUnit.minute())
                            case "respiratory-rate": return HKUnit.count().unitDivided(by: HKUnit.minute())
                            case "hrv": return HKUnit.secondUnit(with: .milli)
                            case "oxygen-saturation": return HKUnit.percent()
                            case "blood-glucose": return HKUnit(from: "mg/dL")
                            case "body-temperature", "basal-body-temperature": return HKUnit.degreeCelsius()
                            case "body-fat": return HKUnit.percent()
                            case "flights-climbed": return .count()
                            case "exercise-time": return HKUnit.minute()
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
    
    func querySleepAggregated(startDate: Date, endDate: Date, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async {
                completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "SleepAnalysis type unavailable"]))
            }
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            var dailyDurations: [Date: TimeInterval] = [:]
            let calendar = Calendar.current
            if let categorySamples = samples as? [HKCategorySample], error == nil {
                for sample in categorySamples {
                    // Ignore in-bed and awake samples; we care about actual sleep
                    if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue { continue }
                    if sample.value == HKCategoryValueSleepAnalysis.awake.rawValue { continue }
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
    
    func queryBloodPressureAggregated(startDate: Date, endDate: Date, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
        guard let bpType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            DispatchQueue.main.async {
                completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Blood pressure types unavailable"]))
            }
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: bpType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }

            guard let correlations = samples as? [HKCorrelation] else {
                DispatchQueue.main.async {
                    completion([], nil)
                }
                return
            }

            let calendar = Calendar.current
            let dayComponent = DateComponents(day: 1)
            let unit = HKUnit.millimeterOfMercury()

            var grouped: [Date: [(Double, Double)]] = [:]
            for correlation in correlations {
                guard let systolicSample = correlation.objects(for: systolicType).first as? HKQuantitySample,
                      let diastolicSample = correlation.objects(for: diastolicType).first as? HKQuantitySample else { continue }
                let dayStart = calendar.startOfDay(for: correlation.startDate)
                let systolicValue = systolicSample.quantity.doubleValue(for: unit)
                let diastolicValue = diastolicSample.quantity.doubleValue(for: unit)
                grouped[dayStart, default: []].append((systolicValue, diastolicValue))
            }

            var aggregatedSamples: [[String: Any]] = []
            for (dayStart, readings) in grouped {
                guard !readings.isEmpty else { continue }
                let systolicAvg = readings.map { $0.0 }.reduce(0, +) / Double(readings.count)
                let diastolicAvg = readings.map { $0.1 }.reduce(0, +) / Double(readings.count)
                let bucketStart = dayStart.timeIntervalSince1970 * 1000
                let bucketEnd = (calendar.date(byAdding: dayComponent, to: dayStart)?.timeIntervalSince1970 ?? dayStart.timeIntervalSince1970) * 1000
                aggregatedSamples.append([
                    "startDate": bucketStart,
                    "endDate": bucketEnd,
                    "systolic": systolicAvg,
                    "diastolic": diastolicAvg,
                    "value": systolicAvg,
                    "unit": unit.unitString
                ])
            }

            aggregatedSamples.sort { (lhs, rhs) in
                guard let lhsStart = lhs["startDate"] as? Double, let rhsStart = rhs["startDate"] as? Double else { return false }
                return lhsStart < rhsStart
            }

            DispatchQueue.main.async {
                completion(aggregatedSamples, nil)
            }
        }
        healthStore.execute(query)
    }

    private func sumEnergy(
        _ identifier: HKQuantityTypeIdentifier,
        startDate: Date,
        endDate: Date,
        completion: @escaping (Double?, Error?) -> Void
    ) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(nil, NSError(domain: "HealthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Quantity type unavailable"]))
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            let value = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie())
            completion(value, nil)
        }
        healthStore.execute(query)
    }

    private func queryLatestTotalCalories(_ call: CAPPluginCall) {
        let unit = HKUnit.kilocalorie()
        let group = DispatchGroup()
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        var activeTotal: Double?
        var basalTotal: Double?
        var queryError: Error?
        let basalSupported = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) != nil

        group.enter()
        sumEnergy(.activeEnergyBurned, startDate: startOfDay, endDate: now) { value, error in
            activeTotal = value
            if queryError == nil { queryError = error }
            group.leave()
        }

        if basalSupported {
            group.enter()
            sumEnergy(.basalEnergyBurned, startDate: startOfDay, endDate: now) { value, error in
                basalTotal = value
                if queryError == nil { queryError = error }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = queryError {
                call.reject("Error fetching total calories: \(error.localizedDescription)")
                return
            }
            guard activeTotal != nil || basalTotal != nil else {
                call.reject("No sample found", "NO_SAMPLE")
                return
            }
            let total = (activeTotal ?? 0) + (basalTotal ?? 0)
            call.resolve([
                "value": total,
                "timestamp": now.timeIntervalSince1970 * 1000,
                "unit": unit.unitString
            ])
        }
    }

    private func collectEnergyBuckets(
        _ identifier: HKQuantityTypeIdentifier,
        startDate: Date,
        endDate: Date,
        interval: DateComponents,
        completion: @escaping ([TimeInterval: (start: TimeInterval, end: TimeInterval, value: Double)]?, Error?) -> Void
    ) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion([:], nil)
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startDate,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, result, error in
            if let error = error {
                completion(nil, error)
                return
            }
            var buckets: [TimeInterval: (start: TimeInterval, end: TimeInterval, value: Double)] = [:]
            result?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                guard let quantity = statistics.sumQuantity() else { return }
                let startMs = statistics.startDate.timeIntervalSince1970 * 1000
                let endMs = statistics.endDate.timeIntervalSince1970 * 1000
                buckets[startMs] = (startMs, endMs, quantity.doubleValue(for: HKUnit.kilocalorie()))
            }
            completion(buckets, nil)
        }
        healthStore.execute(query)
    }

    private func queryTotalCaloriesAggregated(
        startDate: Date,
        endDate: Date,
        interval: DateComponents,
        completion: @escaping ([[String: Any]]?, Error?) -> Void
    ) {
        let group = DispatchGroup()
        let basalSupported = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) != nil
        var activeBuckets: [TimeInterval: (start: TimeInterval, end: TimeInterval, value: Double)]?
        var basalBuckets: [TimeInterval: (start: TimeInterval, end: TimeInterval, value: Double)]?
        var queryError: Error?

        group.enter()
        collectEnergyBuckets(.activeEnergyBurned, startDate: startDate, endDate: endDate, interval: interval) { buckets, error in
            activeBuckets = buckets
            queryError = queryError ?? error
            group.leave()
        }

        if basalSupported {
            group.enter()
            collectEnergyBuckets(.basalEnergyBurned, startDate: startDate, endDate: endDate, interval: interval) { buckets, error in
                basalBuckets = buckets
                queryError = queryError ?? error
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = queryError {
                completion(nil, error)
                return
            }
            let active = activeBuckets ?? [:]
            let basal = basalBuckets ?? [:]
            let allKeys = Set(active.keys).union(basal.keys).sorted()
            var aggregated: [[String: Any]] = []
            let calendar = Calendar.current
            for key in allKeys {
                let startMs = key
                let endMs = active[key]?.end ?? basal[key]?.end ?? {
                    let date = Date(timeIntervalSince1970: startMs / 1000)
                    return (calendar.date(byAdding: interval, to: date) ?? date).timeIntervalSince1970 * 1000
                }()
                let value = (active[key]?.value ?? 0) + (basal[key]?.value ?? 0)
                aggregated.append([
                    "startDate": startMs,
                    "endDate": endMs,
                    "value": value
                ])
            }
            completion(aggregated.sorted { ($0["startDate"] as? Double ?? 0) < ($1["startDate"] as? Double ?? 0) }, nil)
        }
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

    private func parseDate(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        if let str = value as? String {
            if let parsed = isoDateFormatter.date(from: str) {
                return parsed
            }
            if let millis = Double(str) {
                return Date(timeIntervalSince1970: millis / 1000)
            }
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        return nil
    }

    private func workoutActivityType(from value: String) -> HKWorkoutActivityType? {
        let normalized = value.lowercased()
        let mapping: [String: UInt] = [
            "rock-climbing": 9,
            "climbing": 9,
            "hiking": 24,
            "running": 37,
            "walking": 52,
            "cycling": 13,
            "biking": 13,
            "strength-training": 50,
            "strength_training": 50,
            "traditional-strength-training": 50,
            "yoga": 57,
            "other": 3000
        ]

        if let raw = mapping[normalized] {
            return HKWorkoutActivityType(rawValue: raw)
        }
        return HKWorkoutActivityType.other
    }

    private func sanitizeMetadata(_ metadata: JSObject?) -> [String: Any]? {
        guard let metadata = metadata else { return nil }
        var cleaned: [String: Any] = [:]
        for (key, value) in metadata {
            switch value {
            case let number as NSNumber:
                cleaned[key] = number
            case let string as NSString:
                cleaned[key] = string
            case let date as Date:
                cleaned[key] = date
            case let string as String:
                cleaned[key] = string
            default:
                continue
            }
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    private func buildRouteLocations(from value: Any?, defaultDate: Date) -> [CLLocation] {
        guard let routeItems = value as? [Any] else { return [] }
        var locations: [CLLocation] = []

        for case let point as JSObject in routeItems {
            guard let lat = point["lat"] as? CLLocationDegrees,
                  let lng = point["lng"] as? CLLocationDegrees else { continue }
            let alt = (point["alt"] as? NSNumber)?.doubleValue ?? 0
            let timestamp = parseDate(point["timestamp"]) ?? defaultDate
            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: alt,
                horizontalAccuracy: kCLLocationAccuracyBest,
                verticalAccuracy: kCLLocationAccuracyBest,
                timestamp: timestamp
            )
            locations.append(location)
        }

        return locations.sorted { $0.timestamp < $1.timestamp }
    }

    private func buildHeartRateSamples(from value: Any?, defaultStart: Date, defaultEnd: Date) -> [HKQuantitySample] {
        guard let arr = value as? [Any],
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }

        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        var samples: [HKQuantitySample] = []
        for case let point as JSObject in arr {
            guard let bpm = point["bpm"] as? NSNumber else { continue }
            let timestamp = parseDate(point["timestamp"]) ?? defaultStart
            let quantity = HKQuantity(unit: unit, doubleValue: bpm.doubleValue)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: timestamp, end: timestamp)
            samples.append(sample)
        }

        // Ensure samples fall within the workout window to avoid HK errors.
        return samples
            .filter { $0.startDate >= defaultStart && $0.endDate <= defaultEnd }
            .sorted { $0.startDate < $1.startDate }
    }
    
    
    @objc func saveWorkout(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("Health data is unavailable on this device.")
            return
        }

        guard let activityTypeString = call.getString("activityType"),
              let startDateString = call.getString("startDate"),
              let endDateString = call.getString("endDate"),
              let startDate = parseDate(startDateString),
              let endDate = parseDate(endDateString) else {
            call.reject("Missing or invalid parameters")
            return
        }

        guard let activityType = workoutActivityType(from: activityTypeString) else {
            call.reject("Unsupported activityType: \(activityTypeString)")
            return
        }

        guard startDate < endDate else {
            call.reject("startDate must be before endDate")
            return
        }

        let energyQuantity: HKQuantity? = {
            if let calories = call.getDouble("calories") {
                return HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
            }
            return nil
        }()
        let distanceQuantity: HKQuantity? = {
            if let distance = call.getDouble("distance") {
                return HKQuantity(unit: HKUnit.meter(), doubleValue: distance)
            }
            return nil
        }()

        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            workoutEvents: nil,
            totalEnergyBurned: energyQuantity,
            totalDistance: distanceQuantity,
            metadata: sanitizeMetadata(call.getObject("metadata"))
        )

        let routeLocations = buildRouteLocations(from: call.getArray("route"), defaultDate: startDate)
        let heartRateSamples = buildHeartRateSamples(from: call.getArray("heartRateSamples"), defaultStart: startDate, defaultEnd: endDate)

        healthStore.save(workout) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    call.reject("Failed to save workout: \(error.localizedDescription)")
                    return
                }
                guard success else {
                    call.reject("Failed to save workout")
                    return
                }

                if routeLocations.isEmpty && heartRateSamples.isEmpty {
                    call.resolve(["success": true, "id": workout.uuid.uuidString])
                    return
                }

                let group = DispatchGroup()
                var saveError: String?

                if !routeLocations.isEmpty {
                    group.enter()
                    let routeBuilder = HKWorkoutRouteBuilder(healthStore: self.healthStore, device: nil)
                    routeBuilder.insertRouteData(routeLocations) { inserted, insertError in
                        if let insertError = insertError {
                            saveError = "Failed to insert route: \(insertError.localizedDescription)"
                            group.leave()
                            return
                        }
                        routeBuilder.finishRoute(with: workout, metadata: nil) { _, finishError in
                            if let finishError = finishError {
                                saveError = "Failed to finish route: \(finishError.localizedDescription)"
                            } else if !inserted {
                                saveError = "Failed to insert route"
                            }
                            group.leave()
                        }
                    }
                }

                if !heartRateSamples.isEmpty {
                    group.enter()
                    self.healthStore.add(heartRateSamples, to: workout) { hrSuccess, hrError in
                        if let hrError = hrError {
                            saveError = "Failed to save heart rate samples: \(hrError.localizedDescription)"
                        } else if !hrSuccess {
                            saveError = "Failed to save heart rate samples"
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    if let saveError = saveError {
                        call.reject(saveError)
                    } else {
                        call.resolve(["success": true, "id": workout.uuid.uuidString])
                    }
                }
            }
        }
    }
    
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
            let resultsQueue = DispatchQueue(label: "com.flomentumsolutions.capacitorhealthextended.workoutResults")
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
                let heartRateQueue = DispatchQueue(label: "com.flomentumsolutions.capacitorhealthextended.heartRates")
                let routeQueue = DispatchQueue(label: "com.flomentumsolutions.capacitorhealthextended.routes")
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
                let allLocationsQueue = DispatchQueue(label: "com.flomentumsolutions.capacitorhealthextended.allLocations")
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
