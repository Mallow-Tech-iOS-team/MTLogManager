//
//  Extension.swift
//  
//
//  Created by Karthikeyan Ramasamy on 27/06/23.
//

import Foundation

// MARK: - String extension

extension String {
    
    /// To check the given string is empty or not
    /// - Returns: returns bool
    func isNotEmpty() -> Bool {
        return !replacingOccurrences(of: " ", with: "").isEmpty
    }
}

// MARK: - Enumerations

extension MTAWSLogManager {
    enum MTAWSLoggingError: String, Codable {
        case expectedSequenceToken = "expectedSequenceToken"
        case type = "__type"
        case dataAlreadyAcceptedException = "DataAlreadyAcceptedException"
        case invalidSequenceTokenException = "InvalidSequenceTokenException"
        case resourceNotFoundException = "ResourceNotFoundException"
    }
}

// MARK: - Enumerations

extension MTLogManager {
    
    /// We provide a tag to save along with the log to identify the log based on tag, if we need more tag we can extend the MTLogManager and update the custom tag whatever we need
    enum MTLoggingTag: String, Codable {
        case error = "ERROR"
        case warning = "WARNING"
        case info = "INFO"
        case apiInfo = "API_INFO"
    }

    /// We provide a module to save along with the log to identify the log based on module we work, if we need more module we can extend the MTLogManager and update the custom tag whatever we need, we just provide a a sample here
    enum MTLogModule: String, Codable {
        case general = "General"
        case downloadSync = "Download_Sync"
        case uploadSync = "Upload_Sync"
    }

    /// We provide a phase to save along with the log to identify the log based on kind of phase we work, if we need more phase we can extend the MTLogManager and update the custom phase whatever we need, we just provide a a sample here
    enum MTLogPhase: String, Codable {
        case phase1 = "PHASE_1"
        case phase2 = "PHASE_2"
        case general = "GENERAL"
        case appDelegate = "APP_DELEGATE"
    }
}
