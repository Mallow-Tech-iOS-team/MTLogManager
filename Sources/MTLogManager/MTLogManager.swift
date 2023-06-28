//
//  MTLogManager.swift
//
//
//  Created by Karthikeyan Ramasamy on 26/06/23.
//

import UIKit
import AVFoundation
import CoreLocation
import Photos
import AWSCore

// MARK: - Log Manager

open class MTLogManager {
    private var shouldSendLog: Bool?
    private var eventMessage: String?
    private var eventTimeStamp: Double?
    private var shouldPostPendingEvents: Bool = false
    private var logger: MTAWSLogManagerProtocol
    private var logPersistor: MTLogPersisterProtocol
    private var debounceTimer: Timer?
    public var userID: String?
    public var identityPoolId: String
    public var regionType: AWSRegionType
    
    init(
        logger: MTAWSLogManagerProtocol = MTAWSLogManager(),
        logPersistor: MTLogPersisterProtocol = MTLogPersister(),
        userID: String?,
        identityPoolId: String,
        regionType: AWSRegionType
    ) {
        self.logger = logger
        self.logPersistor = logPersistor
        self.userID = userID
        self.identityPoolId = identityPoolId
        self.regionType = regionType
        MTDataStorage.shared.userID = userID
        configureAWS()
    }
    
    func configureAWS() {
        let credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: regionType,
            identityPoolId: identityPoolId
        )
        let configuration = AWSServiceConfiguration(
            region: regionType,
            credentialsProvider: credentialsProvider
        )
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        configureLogRequest { }
    }
    
    // MARK: - Logging Methods
    
    func postLog(tag: MTLoggingTag, phase: MTLogPhase, module: MTLogModule, message: String) {
        // To make sure that no newLine(\n) is entered in message
        let newMessage = message.replacingOccurrences(of: "\n", with: "-")
        saveLogEvent(tag: tag, phase: phase, module: module, message: newMessage) {
            // Do Nothing
        }
    }
    
    // Checking Logs to upload
    func configureLogRequest(onCompletion: @escaping () -> Void) {
        let dispatchQueue = DispatchQueue(label: "logging", qos: .background)
        let semaphore = DispatchSemaphore(value: 0)
        
    #if DEBUG
        guard
            let lastLogUpdatedTime = UserDefaults.standard.object(forKey: kLastLogUpdatedTime) as? Date,
            let isReachedMaximumLogTime = Calendar.current.dateComponents([.minute], from: lastLogUpdatedTime, to: Date()).minute
        else {
            return
        }
    #else
        guard
            let lastLogUpdatedTime = UserDefaults.standard.object(forKey: kLastLogUpdatedTime) as? Date,
            let isReachedMaximumLogTime = Calendar.current.dateComponents([.hour], from: lastLogUpdatedTime, to: Date()).hour
        else {
            return
        }
    #endif
        dispatchQueue.async { [weak self] in
            guard let self, let data = self.logPersistor.readData(isTempFile: self.shouldSendLog ?? false) else {
                return
            } // Getting logs from file
            defer {
                onCompletion()
            }
            let stringData = String(decoding: data, as: UTF8.self)
            let eventArray = stringData.components(separatedBy: .newlines)
            let eventBatches = self.logger.uploadPendingMessages(arrayEvents: eventArray)
            var batchCount: Int = 0
            var isUploadedAllBatches: Bool?
            var uploadedBatchCount: Int = 0
            var uploadedEventCount: Int = 0
            
            for currentBatch in eventBatches {
                batchCount += 1
                
                // Checking conditions to upload logs
                if (eventArray.count > kMaximumLogsCount || isReachedMaximumLogTime >= kMaximumTimeForLogUpload || self.shouldPostPendingEvents == true), self.userID != nil {
                    self.shouldSendLog = true
                    self.logger.uploadBatches(events: currentBatch) { isUploadedEvent in
                        if isUploadedEvent == true {
                            uploadedBatchCount += 1
                            uploadedEventCount += currentBatch.count
                        }
                        
                        if isUploadedEvent == false {
                            isUploadedAllBatches = false
                        }
                        if isUploadedEvent == true && eventBatches.count == batchCount, eventArray.count - 1 == uploadedEventCount {
                            UserDefaults.standard.set(Date(), forKey: kLastLogUpdatedTime)
                            self.shouldSendLog = false
                            self.logPersistor.deleteFile(isTempFile: false) // if all batches uploaded, deleting the logs file
                            isUploadedAllBatches = true
                            semaphore.signal() // giving a signal once uploaded all the batches
                        }
                        semaphore.signal()  // giving a signal once uploaded each batch
                    }
                    semaphore.wait() // Waiting for a signal once uploaded each batch
                } else {
                    self.shouldSendLog = false
                }
                if isUploadedAllBatches != nil { // To avoid duplicate log uploads, Breaking the loop once uploading process completed
                    break
                }
            }
            // Restoring logs which is failed in uploading logs
            if isUploadedAllBatches == false, uploadedBatchCount != 0 {
                self.logPersistor.removeLogsFromFile(isTempFile: false) // Remove all logs from file
                for batchIndex in uploadedBatchCount...eventBatches.count - 1 { // adding logs batch which is failed in uploading logs
                    for events in eventBatches[batchIndex] {
                        self.eventMessage = events.message
                        self.eventTimeStamp = (events.timestamp?.doubleValue ?? 0.0) / 1000 // we are storing time in seconds format. But, "events.timestamp" format is in milli seconds. So, we are dividing "events.timestamp" by 1000
                        self.savePendingEvents()
                    }
                }
            }
            self.logPersistor.saveTempFileDataToMainFile()
            if isUploadedAllBatches == true {
                semaphore.wait() // Waiting for a signal once uploaded all the batches
            }
            self.logPersistor.saveTempFileDataToMainFile()
        }
    }
    
    // Adding Log Details
    private func saveLogEvent(tag: MTLoggingTag, phase: MTLogPhase, module: MTLogModule, message: String, onCompletion: @escaping () -> Void) {
        let logMessage = getLogMessage(tag: tag, phase: phase, module: module, message: message)
        eventMessage = logMessage
        if #available(iOS 15, *) {
            eventTimeStamp = Date.now.timeIntervalSince1970
        } else {
            // Fallback on earlier versions
            eventTimeStamp = Date().timeIntervalSince1970
        }
        savePendingEvents()
        if shouldSendLog != true {
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in // added 1 sec interval to avoid more computation from `configureLogRequest`
                self?.configureLogRequest(onCompletion: onCompletion)
            }
        }
    }
    
    // Save pending events to file
    private func savePendingEvents() {
        guard let pendingEvent = getEvent() else { return }
        if logPersistor.write(pendingEvent: pendingEvent, isTempFile: shouldSendLog ?? false) == false {
            shouldSendLog = false
        }
    }
    
    private func getEvent() -> String? {
        if let message = eventMessage, let timeStamp = eventTimeStamp {
            let event = [message, String(describing: timeStamp)]
            var eventString = event.joined(separator: " , ")
            eventString += "\n"
            return eventString
        }
        return nil
    }
    
    // When we logout, this will call
    private func postPendingEvents(shouldUpload: Bool) {
        shouldPostPendingEvents = shouldUpload
        configureLogRequest {
            // Do Nothing
        }
    }
    
    // Get Log Message
    private func getLogMessage(tag: MTLoggingTag, phase: MTLogPhase, module: MTLogModule, message: String) -> String {
        let details = [
            String(describing: UIDevice.current.identifierForVendor ?? UUID(uuidString: "")),
            tag.rawValue,
            UIDevice.current.name,
            UIDevice.current.systemVersion,
            getAppVersionNumber() ?? "nil",
            phase.rawValue,
            module.rawValue,
            message
        ]
        let logMessage = details.joined(separator: " | ")
        return logMessage
    }
    
    private func getAppVersionNumber() -> String? {
        let versionKeyName = "CFBundleShortVersionString"
        if let versionNumber = Bundle.main.object(forInfoDictionaryKey: versionKeyName) {
            return versionNumber as? String
        }
        return nil
    }
    
    func sensitiveServicesPermissionsLog() {
        var message = "🔒 Permissions => "
        
        let locationStatus = CLLocationManager.authorizationStatus()
        message.append("Location: \(locationStatus)")
        
        let photoLibraryStatus = PHPhotoLibrary.authorizationStatus()
        message.append(" | PhotoLibrary: \(photoLibraryStatus)")
        
        let cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        message.append(" | Camera: \(cameraPermission)")
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let notificationStatus = settings.authorizationStatus
            message.append(" | Notification: \(notificationStatus)")
        }
        self.postLog(tag: .info, phase: .general, module: .general, message: message)
    }
    
    func captureError(_ error: Error?, tag: MTLoggingTag, phase: MTLogPhase, module: MTLogModule) {
        if let error = error {
            var message = "🌐 API Error: "
            message += error.localizedDescription
            postLog(tag: tag, phase: phase, module: module, message: message)
        }
    }
    
    func logout() {
        let logMessage = getLogMessage(tag: .info, phase: .general, module: .general, message: "👋🏻 logging out")
        eventMessage = logMessage
        if #available(iOS 15, *) {
            eventTimeStamp = Date.now.timeIntervalSince1970
        } else {
            // Fallback on earlier versions
            eventTimeStamp = Date().timeIntervalSince1970
        }
        savePendingEvents()
        shouldPostPendingEvents = true
        configureLogRequest {
            // Delete log file
            self.logPersistor.deleteFile(isTempFile: false)
            self.shouldPostPendingEvents = false
            
            // Clear data
            MTDataStorage.shared.userID = nil
            MTDataStorage.shared.logSequenceToken = nil
        }
    }
}
