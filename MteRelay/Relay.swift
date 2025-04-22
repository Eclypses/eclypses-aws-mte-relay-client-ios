// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation
import Mte
import MKE
import Core
import os

public class Relay: ObservableObject, RelayResponseDelegate, RelayStreamDelegate, RelayStreamCompletionDelegate, RelayStreamResponseDelegate {
    
    // MARK: Class Variables
    public weak var relayResponseDelegate: RelayResponseDelegate?
    public var relayStreamDelegate: RelayStreamDelegate? // This delegate variable cannot be 'weak' or we lose the reference before we are finished with it.
    public weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    public weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    var hostDictionary = [String:Host]()
    
    // MARK: Callbacks
    // Receives fileStream Responses
    public func relayStreamResponse(from relayServerUrl: String, data: Data?, response: URLResponse?, error: (any Error)?) {
        relayStreamResponseDelegate?.relayStreamResponse(from: relayServerUrl, data: data, response: response, error: error)
    }
    
    // Called periodically to return stream upload/download completion percentage values
    public func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        self.relayStreamCompletionDelegate?.streamCompletionPercentage(from: relayServerUrl, bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    // Used to call back into app to retrieve file for upload
    public func getRequestBodyStream(outputStream: OutputStream) {
        relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream)
    }
    
    // Used to return pairing responses
    public func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        DispatchQueue.global().async {
            self.relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
        }
    }
    
    // MARK: init
    public init() async throws {
        
        // Check MTE licensing
        if !MteBase.initLicense(Settings.licCompanyName, Settings.licCompanyKey) {
            throw "License Check failed."
        }
        
#if DEBUG
        // Print MTE Version
        print("Using MTE Version \(MteBase.getVersion())")
#endif
        
    }
    
    // MARK: Public Functions
    public func dataTask(with origRequest: URLRequest,
                         headersToEncrypt: [String]?,
                         completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        await dataTask(with: origRequest, headersToEncrypt: headersToEncrypt, pathnamePrefix: nil, completionHandler: completionHandler)
    }
    
    public func dataTask(with origRequest: URLRequest,
                         headersToEncrypt: [String]?,
                         pathnamePrefix: String?,
                         completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        do {
            guard let host = try await retrieveHost(origRequest: origRequest, pathnamePrefix: pathnamePrefix) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            await host.dataTask(with: origRequest,
                                headersToEncrypt: headersToEncrypt,
                                pathnamePrefix: pathnamePrefix,
                                completionHandler: completionHandler)
        } catch {
            completionHandler(nil, nil, "Error: \(error.localizedDescription)")
            return
        }
    }
    
    public func uploadFileStream(request: URLRequest,
                                 headersToEncrypt: [String]?) throws {
        try uploadFileStream(request: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: nil)
    }
    
    public func uploadFileStream(request: URLRequest,
                                 headersToEncrypt: [String]?,
                                 pathnamePrefix: String?) throws {
        Task {
            guard let host = try await retrieveHost(origRequest: request, pathnamePrefix: pathnamePrefix) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            try await host.uploadFileStream(origRequest: request,
                                            headersToEncrypt: headersToEncrypt,
                                            pathnamePrefix: pathnamePrefix)
        }
    }
    
    public func downloadFileStream(request: URLRequest,
                                   downloadUrl: URL,
                                   headersToEncrypt: [String]?) throws {
        try downloadFileStream(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt, pathnamePrefix: nil)
    }
    
    public func downloadFileStream(request: URLRequest,
                                   downloadUrl: URL,
                                   headersToEncrypt: [String]?,
                                   pathnamePrefix: String?) throws {
        Task {
            guard let host = try await retrieveHost(origRequest: request, pathnamePrefix: pathnamePrefix) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            await host.downloadFileStream(origRequest: request,
                                          headersToEncrypt: headersToEncrypt,
                                          pathnamePrefix: pathnamePrefix,
                                          downloadUrl: downloadUrl)
        }
    }
    
    public func rePairwithRelayServer(relayServerUrlString: String) async throws {
        try await rePairwithRelayServer(relayServerUrlString: relayServerUrlString, pathnamePrefix: nil)
    }
    
    public func rePairwithRelayServer(relayServerUrlString: String, pathnamePrefix: String?) async throws {
        
        let serverUrlPath = try buildHostUrl(serverUrl: relayServerUrlString, pathnamePrefix: pathnamePrefix)
        if let host = hostDictionary[serverUrlPath] {
            try await host.rePairHost()
        } else {
            _ = try await instantiateHost(hostStr: serverUrlPath)
        }
    }
    
    public func adjustRelaySettings(serverUrl: String, newStreamChunkSize: Int, newPairPoolSize: Int, persistPairs: Bool) async throws {
        try await adjustRelaySettings(serverUrl: serverUrl,
                                      pathnamePrefix: nil as String?,
                                      newStreamChunkSize: newStreamChunkSize,
                                      newPairPoolSize: newPairPoolSize,
                                      persistPairs: persistPairs)
    }
    
    public func adjustRelaySettings(serverUrl: String,
                                    pathnamePrefix: String?,
                                    newStreamChunkSize: Int,
                                    newPairPoolSize: Int,
                                    persistPairs: Bool) async throws {
        
        var responseMessage = ""
        var updatedServerUrl = serverUrl
        
        do {
            updatedServerUrl = try buildHostUrl(serverUrl: serverUrl, pathnamePrefix: pathnamePrefix)
            
            
            if newStreamChunkSize != 0, newStreamChunkSize != getStreamChunkSizeSetting() {
                try setStreamChunkSize(newStreamChunkSize)
                responseMessage += "\nRelaySetting.streamChunkSize adjusted to \(newStreamChunkSize)"
            }
            
            if newPairPoolSize != 0, newPairPoolSize != getPairPoolSizeSetting() {
                try setPairPoolSize(newPairPoolSize)
                responseMessage += "\nRelaySetting.pairPoolSize adjusted to \(newPairPoolSize)"
            }
            
            if persistPairs != getPersistPairsSetting() {
                try setPersistPairs(persistPairs)
                responseMessage += "\nRelaySetting.persistPairs adjusted to \(persistPairs)"
            }
            
            if responseMessage.isEmpty {
                responseMessage = "\nNo Relay Settings were changed based on arguments and existing RelaySettings"
            } else {
                try await rePairwithRelayServer(relayServerUrlString: updatedServerUrl, pathnamePrefix: pathnamePrefix)
                responseMessage += "\nAlso, Relay was Re-Paired with \(updatedServerUrl)"
            }
        } catch {
            relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
            
        }
        relayResponse(success: true, responseStr: responseMessage, errorMessage: nil)
    }
    
    // MARK: Private functions
    private func buildHostUrl(serverUrl: String, pathnamePrefix: String?) throws -> String {
        if serverUrl.isEmpty {
            throw "Server Url is required"
        }
        var modifiedUrl = serverUrl
        if modifiedUrl.hasSuffix("/") {
            modifiedUrl.removeLast()
        }
        
        if let pathnamePrefix = pathnamePrefix, !pathnamePrefix.isEmpty {
            let normalizedPath = pathnamePrefix.hasPrefix("/") ? pathnamePrefix : "/" + pathnamePrefix
            if !modifiedUrl.hasSuffix(normalizedPath) {
                return modifiedUrl + normalizedPath
            }
        }
        return modifiedUrl
    }
    
    private func retrieveHost(origRequest: URLRequest, pathnamePrefix: String?) async throws -> Host? {
        guard let relayUrl = origRequest.url else {
            throw "Unable to create URL from relayPath"
        }

        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port

        guard let hostStr = components.string else {
            throw "Unable to create String from URL components"
        }
        
        let updatedHostStr = try buildHostUrl(serverUrl: hostStr, pathnamePrefix: pathnamePrefix)

        guard let host = hostDictionary[updatedHostStr] else {
            return try await instantiateHost(hostStr: updatedHostStr)
        }
        return host
    }
    
    private func instantiateHost(hostStr: String) async throws -> Host {
        let host = try await Host(hostUrl: hostStr, relay: self)
        hostDictionary[hostStr] = host
        return host
    }
    
    private func setStreamChunkSize(_ size: Int) throws {
        if size < 4096 || size > 1024 * 1024 * 10 {
            throw "Stream chunk size must be between 4096 (4 KB) and 10485760 (1024 * 1024 * 10) (10 MB)"
        }
        Settings.streamChunkSize = size
    }
    
    private func setPersistPairs(_ bool: Bool) throws {
        Settings.persistPairs = bool
    }
    
    private func setPairPoolSize(_ size: Int) throws {
        if size < 1 || size > 10 {
            throw "PairPoolSize must be between 1 and 10 pairs"
        }
        Settings.pairPoolSize = size
    }
    
    private func getStreamChunkSizeSetting() -> Int {
        return Settings.streamChunkSize
    }
    
    private func getPersistPairsSetting() -> Bool {
        return Settings.persistPairs
    }
    
    private func getPairPoolSizeSetting() -> Int {
        return Settings.pairPoolSize
    }
    
    // Method to call the delegate method safely
    private func notifyDelegate(success: Bool, responseStr: String, errorMessage: String) {
        relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
        
    }

    
}




