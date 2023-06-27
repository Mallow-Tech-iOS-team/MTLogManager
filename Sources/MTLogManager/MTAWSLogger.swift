//
//  MTAWSLogger.swift
//  
//
//  Created by Karthikeyan Ramasamy on 26/06/23.
//

import Foundation
import AWSLogs

// MARK: - AWS Log Manager Protocol

protocol MTAWSLogManagerProtocol {
    var logs: AWSLogs { get set }
    var events: [AWSLogsInputLogEvent] { get set }
    var pendingEvent: AWSLogsInputLogEvent? { get set }
    var logStreamName: String? { get set }
    
    func uploadBatches(events: [AWSLogsInputLogEvent], completion: @escaping (Bool?) -> Void)
    func send(log: AWSLogsPutLogEventsRequest, completion: @escaping (Bool?) -> Void)
    func handle(response: AWSLogsPutLogEventsResponse?, for log: AWSLogsPutLogEventsRequest, with completion: @escaping (Bool?) -> Void)
    func handle(error: Error, for log: AWSLogsPutLogEventsRequest, with completion: @escaping (Bool?) -> Void)
    func getEvent(array: [String]) -> (event: AWSLogsInputLogEvent?, shouldCreateNewBatch: Bool?)
    func uploadPendingMessages(arrayEvents: [String]) -> [[AWSLogsInputLogEvent]]
}

// MARK: - AWS Log Manager

class MTAWSLogManager: MTAWSLogManagerProtocol {
    var logs = AWSLogs.default()
    var events: [AWSLogsInputLogEvent] = []
    var pendingEvent: AWSLogsInputLogEvent?
    var logStreamName: String?
    var batchStartingTime: Double?
    let semaphore = DispatchSemaphore(value: 1)
    
    // Sending logs
    func send(log: AWSLogsPutLogEventsRequest, completion: @escaping (Bool?) -> Void) {
        let queue = DispatchQueue(label: "CloudWatchLog - \(log.logStreamName ?? "")")
        queue.async {
            if let token: String = MTDataStorage.shared.logSequenceToken {
                log.sequenceToken = token
            }
            self.logs.putLogEvents(log) { response, error in
                if let error = error {
                    self.handle(error: error, for: log, with: completion)
                    // If the user's stream is not there. We are passing the completion status as usual, what we are getting.
                    if
                        let userInfo = error._userInfo as? [String: Any],
                        let type = userInfo[MTAWSLoggingError.type.rawValue] as? String,
                        type == MTAWSLoggingError.resourceNotFoundException.rawValue
                    {
                        self.send(log: log) { status in
                            completion(status)
                        }
                    }
                    
                    // If the logs are already updated and we are getting dataAlreadyAcceptedException error means, this is just like a warning. So, We are passing the completion status as true. But, if we are getting other error means, we are passing completion status as false.
                    if
                        let userInfo = error._userInfo as? [String: Any],
                        let type = userInfo[MTAWSLoggingError.type.rawValue] as? String,
                        type == MTAWSLoggingError.dataAlreadyAcceptedException.rawValue
                    {
                        completion(true)
                    } else {
                        completion(false)
                    }
                } else {
                    self.handle(response: response, for: log, with: completion)
                    completion(true)
                }
            }
        }
    }
    
    // Update Next token When logs uploaded successfully
    func handle(response: AWSLogsPutLogEventsResponse?, for log: AWSLogsPutLogEventsRequest, with completion: @escaping (Bool?) -> Void) {
        print("✅ Successfully logged \"\(log.logEvents?.count ?? 0)\" events with token \(log.sequenceToken ?? "**")")
        
        if let token = response?.nextSequenceToken {
            MTDataStorage.shared.logSequenceToken = token
        }
    }
    
    // Sending logs When Failed to upload log
    func handle(error: Error, for log: AWSLogsPutLogEventsRequest, with completion: @escaping (Bool?) -> Void) {
        print("❌ Failed to log \"\(log.logEvents?.first?.message ?? "**")\" due to \(error)")
        
        if let userInfo = error._userInfo as? [String: Any] {
            if let token = userInfo[MTAWSLoggingError.expectedSequenceToken.rawValue] as? String {
                log.sequenceToken = token
                MTDataStorage.shared.logSequenceToken = token
                print("✏️ Sending failed due to invalid token")
            } else if
                let type = userInfo[MTAWSLoggingError.type.rawValue] as? String,
                (
                    type == MTAWSLoggingError.dataAlreadyAcceptedException.rawValue ||
                    type == MTAWSLoggingError.invalidSequenceTokenException.rawValue
                ),
                let token = userInfo[MTAWSLoggingError.expectedSequenceToken.rawValue] as? String
            {
                MTDataStorage.shared.logSequenceToken = token
                print("✏️ Sending failed due to invalid token")
            } else if
                let type = userInfo[MTAWSLoggingError.type.rawValue] as? String,
                type == MTAWSLoggingError.resourceNotFoundException.rawValue
            {
                creatingGroupAndStream()
                MTDataStorage.shared.logSequenceToken = nil
            }
        } else {
            if (error as NSError).code == -1009 && error.localizedDescription.contains("offline") {
                print("✏️ Saving events to pending events due to lost internet connection")
                completion(true)
            } else {
                completion(nil)
            }
        }
    }
    
    // Creating new group and stream
    func creatingGroupAndStream() {
        if let logStream = AWSLogsCreateLogStreamRequest() {
            guard let id: String = MTDataStorage.shared.userID else {
                return
            }
            logStream.logGroupName = kLogGroupName
            logStream.logStreamName = id
            logs.createLogStream(logStream) { _ in
                // Nothing will do
            }
        }
    }
    
    // Get Events
    func getEvents(dictionary: [String: Any]) -> AWSLogsInputLogEvent? {
        let event = AWSLogsInputLogEvent()
        event?.message = dictionary["message"] as? String
        event?.timestamp = dictionary["timestamp"] as? NSNumber
        return event
    }
    
    // Get Events
    func getEvent(array: [String]) -> (event: AWSLogsInputLogEvent?, shouldCreateNewBatch: Bool?) {
        let event = AWSLogsInputLogEvent()
        var shouldCreateNewBatch: Bool?
        event?.message = array[0]
        
        if array.count > 1, let timeStamp = Double(array[1]), let batchStartingTime = batchStartingTime {
            event?.timestamp = NSNumber(value: timeStamp * 1000) // We need to send time in milli second format to AWS. So, we need to multiply timestamp value by 1000.
            let time1 = Date(timeIntervalSince1970: timeStamp)
            let time2 = Date(timeIntervalSince1970: batchStartingTime)
            #if DEBUG
            let difference = Calendar.current.dateComponents([.minute], from: time2, to: time1).minute
            #else
            let difference = Calendar.current.dateComponents([.hour], from: time2, to: time1).hour
            #endif
            if let batchTimingDifference = difference {
                shouldCreateNewBatch = batchTimingDifference > kMaximumTimeForLogUpload
            } else {
                shouldCreateNewBatch = false
            }
        }
        return (event, shouldCreateNewBatch)
    }
    
    // Upload pending events
    func uploadPendingMessages(arrayEvents: [String]) -> [[AWSLogsInputLogEvent]] {
        var logsBatch: [AWSLogsInputLogEvent] = []
        var arrayOfLogsBatch: [[AWSLogsInputLogEvent]] = []
        if arrayEvents.count > 1 {
            let event = arrayEvents[0].components(separatedBy: " , ")
            if event.count > 1 {
                let batchStartingTimeString = Double(event[1])
                semaphore.wait()
                // FIXME: - Ensure whether can provide batchStartingTime with False time (0.0)
                batchStartingTime = batchStartingTimeString ?? 0.0
                semaphore.signal()
            }
        }
        let events = arrayEvents.filter { $0.isEmpty == false } // Removing empty events
        var lastBatchCount: Int = 0
        for eventString in events { // Converting [String] to [AWSLogsInputLogEvent]
            let eventComponents = eventString.components(separatedBy: " , ")
            let data = getEvent(array: eventComponents)
            if eventString.isNotEmpty(), let event = data.event, let shouldCreateNewBatch = data.shouldCreateNewBatch {
                
                if (logsBatch.count == kMaximumLogsCount) || (shouldCreateNewBatch == true) {
                    arrayOfLogsBatch.append(logsBatch)
                    logsBatch = []
                    
                    if eventComponents.count > 1 {
                        semaphore.wait()
                        batchStartingTime = Double(eventComponents.last ?? "")
                        semaphore.signal()
                    }
                }
                
                logsBatch.append(event)
                lastBatchCount += 1
                
                if lastBatchCount == events.count {
                    arrayOfLogsBatch.append(logsBatch)
                    return arrayOfLogsBatch
                }
            }
        }
        return arrayOfLogsBatch
    }
    
    /// Upload events on batch wise
    func uploadBatches(events: [AWSLogsInputLogEvent], completion: @escaping (Bool?) -> Void) {
        let request = AWSLogsPutLogEventsRequest()
        request?.logEvents = events
        request?.logGroupName = kLogGroupName
        request?.logStreamName = MTDataStorage.shared.userID
        
        if let token: String = MTDataStorage.shared.logSequenceToken {
            request?.sequenceToken = token
        } else {
            request?.sequenceToken = nil
        }
        
        guard let request = request else { return }
        self.send(log: request) { isUploadedEvent in
            completion(isUploadedEvent)
        }
    }
}
