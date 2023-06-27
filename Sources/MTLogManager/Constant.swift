//
//  Constant.swift
//  
//
//  Created by Karthikeyan Ramasamy on 27/06/23.
//

import Foundation

// MARK: - Constants

// Log Manager
let kPendingEvents = "pendingEvents"
let kNextGroupToken = "nextGroupToken"
let kNextStreamToken = "nextStreamToken"
let kLastLogUpdatedTime = "LastLogUpdatedTime"

#if DEBUG
let kMaximumLogsCount = 10
let kMaximumTimeForLogUpload = 5
#else
let kMaximumLogsCount = 5000
let kMaximumTimeForLogUpload = 24
#endif

#if DEBUG
let kLogGroupName = "Development_iOS"

#elseif RELEASE
let kLogGroupName = "Staging_iOS"

#else
let kLogGroupName = "Production_iOS"
#endif

