//
//  Shared.swift
//  
//
//  Created by Karthikeyan Ramasamy on 27/06/23.
//

import Foundation

// MARK: - MTDataStorage

class MTDataStorage {
    static let shared: MTDataStorage = MTDataStorage()
    
    private init() {}
    
    var userID: String? /// To maintain the user id, whether to check the user is logged in, this is also to maintain the unique id of the user since we saved the log agains the user id
    var logSequenceToken: String? /// To maintain the log sequence token
}
