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
    
    var currentHost: Host!
    
    // Receives fileStream Responses
    
    public func relayStreamResponse(data: Data?, response: URLResponse?, error: (any Error)?) {
        guard let relayResponse = response as? HTTPURLResponse else {
            relayStreamResponseDelegate?.relayStreamResponse(data: nil, response: nil, error: "Unable to retrieve HTTPUrlResponse")
            return
        }
        if (relayResponse.statusCode >= 200 && relayResponse.statusCode < 300) {
            relayError = .networkError
            relayStatus = .error
            if let error = error {
                notifyMteRelayError(message: error.localizedDescription)
            }
        } else {
            relayError = .none
            relayStatus = .transmissionSuccessful
        }

        currentHost.relayFileStreamUpload = nil
        currentHost.relayFileStreamDownload = nil

        currentHost = nil
        relayStreamResponseDelegate?.relayStreamResponse(data: data, response: response, error: error)
    }
    
    // Called periodically to return stream upload/download completion percentage values
    public func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        self.relayStreamCompletionDelegate?.streamCompletionPercentage(bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    // Used to call back into app to retrieve file for upload
    public func getRequestBodyStream(outputStream: OutputStream) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream) ?? 0
    }
    
    // Used to return pairing responses
    public func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        if !success {
            relayError = .networkError
            relayStatus = .error
            if let errorMessage = errorMessage {
                notifyMteRelayError(message: errorMessage)
            }
        } else {
            relayError = .none
            relayStatus = .transmissionSuccessful
        }
        DispatchQueue.global().async {
            self.relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
        }
    }
    
    var relayError: MteRelayError = .none
    
    var relayStatus: RelayStatus = .noAttempt
    public weak var relayResponseDelegate: RelayResponseDelegate?
    public var relayStreamDelegate: RelayStreamDelegate? // This delegate variable cannot be 'weak' or we lose the reference before we are finished with it.
    public weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    public weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?    

    var hostDictionary = [String:Host]()
    
    
    // MARK: init
    public init() async throws {
        
        // Check MTE licensing
        if !MteBase.initLicense(RelaySettings.licCompanyName, RelaySettings.licCompanyKey) {
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
            guard let host = try await retrieveHost(origRequest: origRequest) else {
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
            guard let host = try await retrieveHost(origRequest: request) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            currentHost = host
            host.relayStreamResponseDelegate = self
            host.relayStreamDelegate = self
            host.relayStreamCompletionDelegate = self
            
            try await host.uploadFileStream(origRequest: request,
                                            headersToEncrypt: headersToEncrypt,
                                            pathnamePrefix: pathnamePrefix)
        }
    }
    
    public func downloadFileStream(request: URLRequest,
                                   downloadUrl: URL,
                                   headersToEncrypt: [String]?) throws {
        try downloadFileStream(request: request, downloadUrl: downloadUrl, headersToEncrypt: headersToEncrypt, pathnamePPrefix: nil)
    }
    
    public func downloadFileStream(request: URLRequest,
                                   downloadUrl: URL,
                                   headersToEncrypt: [String]?,
                                   pathnamePPrefix: String?) throws {
        Task {
            guard let host = try await retrieveHost(origRequest: request) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            currentHost = host
            host.relayStreamResponseDelegate = self
            await host.downloadFileStream(origRequest: request,
                                          headersToEncrypt: headersToEncrypt,
                                          pathnamePrefix: pathnamePPrefix,
                                          downloadUrl: downloadUrl)
        }
    }
    
    
    public func rePairMte(relayServerUrlString: String, success: (Bool) -> Void ) async throws {
        var serverUrlPath = relayServerUrlString
        if serverUrlPath.last != "/" {
            serverUrlPath.append("/")
        }
        
        if let host = hostDictionary[serverUrlPath] {
            try await host.rePairHost()
            relayStatus = .noAttempt
            success(true)
        } else {
            _ = try await instantiateHost(hostStr: serverUrlPath)
            success(true)
        }
    }
    
    // MARK: Public RelaySettings functions
    public func setStreamChunkSize(_ size: Int) throws {
        if size < 4096 || size > 1024 * 1024 * 10 {
            throw "Stream chunk size must be between 4096 (4 KB) and 10485760 (1024 * 1024 * 10) (10 MB)"
        }
        RelaySettings.streamChunkSize = size
    }
    
    public func setPersistPairs(_ bool: Bool) throws {
        RelaySettings.persistPairs = bool
    }
    
    public func setPairPoolSize(_ size: Int) throws {
        if size < 1 || size > 10 {
            throw "PairPoolSize must be between 1 and 10 pairs"
        }
        RelaySettings.pairPoolSize = size
    }
    
    public func getStreamChunkSizeSetting() -> Int {
         return RelaySettings.streamChunkSize
    }
    
    public func getPersistPairsSetting() -> Bool {
        return RelaySettings.persistPairs
    }
    
    public func getPairPoolSizeSetting() -> Int {
        return RelaySettings.pairPoolSize
    }
    
    // MARK: Private functions
    private func retrieveHost(origRequest: URLRequest) async throws -> Host? {
        
        guard let relayUrl = origRequest.url else {
            throw "Unable to create URL from relayPath"
        }
        
        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port
        
        guard var hostStr = components.string else {
            throw "Unable to create String from URL components"
        }
        
        hostStr.append("/")
        
        if let host = hostDictionary[hostStr] {
            return host
        } else {
            return try await instantiateHost(hostStr: hostStr)
        }
    }
    
    private func instantiateHost(hostStr: String) async throws -> Host {
        let host = try await Host(hostUrl: hostStr, relay: self)
        hostDictionary[hostStr] = host
        return host
    }
    
    // Method to call the delegate method safely
    private func notifyDelegate(success: Bool, responseStr: String, errorMessage: String) {
        relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)

    }
    
    func notifyMteRelayError(message: String) {
        DispatchQueue.main.async {
            self.relayStatus = .error
#if DEBUG
            print("MteRelay Error. Message: \(message)")
#endif
        }
    }
    
}




