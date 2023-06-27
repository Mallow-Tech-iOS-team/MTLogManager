//
//  MTLogPersisterProtocol.swift
//  
//
//  Created by Karthikeyan Ramasamy on 26/06/23.
//

import Foundation

// MARK: - MTLogPersisterProtocol

protocol MTLogPersisterProtocol {
    func write(pendingEvent: String, isTempFile: Bool) -> Bool?
    func readData(isTempFile: Bool) -> Data?
    func removeLogsFromFile(isTempFile: Bool)
    func saveTempFileDataToMainFile()
    func deleteFile(isTempFile: Bool)
}

// MARK: - MTLogPersister

class MTLogPersister: MTLogPersisterProtocol {
    private var filePath: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("log")
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    private let fileName = "log"
    private var tempFilePath: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("log_temp")
    private let tempFileName = "log_temp"
    
    // Write logs into files
    func write(pendingEvent: String, isTempFile: Bool) -> Bool? {
        guard let tempFilePath, let filePath else { return nil }
        var finalFilePath: String
        var finalFileName: String
        
        finalFilePath = (isTempFile == true) ? tempFilePath.path : filePath.path
        finalFileName = (isTempFile == true) ? tempFileName : fileName
        let pendingData = Data(pendingEvent.utf8)
        let fileHandle = FileHandle(forWritingAtPath: finalFilePath)
        guard let fileUrl = docs?.appendingPathComponent(finalFileName) else { return false }
        if(!FileManager.default.fileExists(atPath: fileUrl.path)) {
            UserDefaults.standard.set(Date(), forKey: kLastLogUpdatedTime)
            FileManager.default.createFile(atPath: fileUrl.path, contents: pendingData, attributes: [:])
            fileHandle?.write(pendingData)
        } else { // If the file is existing, it will write the logs on it
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(pendingData)
            return false
        }
        return nil
    }
    
    // Read logs from files
    func readData(isTempFile: Bool) -> Data? {
        var finalFileName: String
        finalFileName = (isTempFile == true) ? tempFileName : fileName
        guard let fileUrl = docs?.appendingPathComponent(finalFileName) else { return nil }
        do {
            let data = try Data(contentsOf: fileUrl)
            return data
        } catch {
            print("error")
            return nil
        }
    }
    
    // Deleting Data from file
    func removeLogsFromFile(isTempFile: Bool) {
        guard let tempFilePath, let filePath else { return }
        var finalFilePath: URL
        finalFilePath = (isTempFile == true) ? tempFilePath : filePath
        let text = ""
        do {
            try text.write(to: finalFilePath, atomically: false, encoding: .utf8) // Writing empty text in file
        } catch {
            print(error)
        }
    }
    
    // Deleting file
    func deleteFile(isTempFile: Bool) {
        guard let tempFilePath, let filePath else { return }
        let finalFilePath = (isTempFile == true) ? tempFilePath.path : filePath.path
        do {
            // Check if file exists
            if FileManager.default.fileExists(atPath: finalFilePath) {
                try FileManager.default.removeItem(atPath: finalFilePath) // Delete file
                print("file deleted...!")
            } else {
                print("File does not exist")
            }
        } catch {
            print(error)
        }
    }
    
    // Converting Data type
    private func data(from object: [Any]) -> Data? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return data
    }
    
    // Moving Temporary file logs to Permanent file
    func saveTempFileDataToMainFile() {
        guard let data = readData(isTempFile: true) else { return } // Getting logs from file
        let stringData = String(decoding: data, as: UTF8.self)
        let eventArray = stringData.components(separatedBy: .newlines)
        let events = eventArray.filter { $0.isEmpty == false } // removing empty events
        for event in events {
            let batchEvent = event + "\n"
            _ = write(pendingEvent: batchEvent, isTempFile: false)
        }
        deleteFile(isTempFile: true)
    }
}
