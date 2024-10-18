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

public class Relay: ObservableObject, RelayResponseDelegate, RelayStreamDelegate, RelayStreamResponseDelegate {
    
    public func response(success: Bool, responseStr: String, errorMessage: String) {
        if !success {
            relayError = .networkError
            relayStatus = .error
            notifyMteRelayError(message: errorMessage)
        } else {
            relayError = .none
            relayStatus = .transmissionSuccessful
        }
        DispatchQueue.global().async {
            self.relayStreamResponseDelegate?.response(success: success, responseStr: responseStr, errorMessage: errorMessage)
        }
    }
    
    public func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        self.relayStreamResponseDelegate?.streamCompletionPercentage(bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    
    public func getRequestBodyStream(outputStream: OutputStream) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream) ?? 0
    }
    
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
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Relay.self)
    )
    
    @Published var relayError: MteRelayError = .none
    
    var relayStatus: RelayStatus = .noAttempt
    public weak var _relayResponseDelegate: RelayResponseDelegate?
    public var relayStreamDelegate: RelayStreamDelegate?
    public weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    var relayResponseDelegateQueue = DispatchQueue(label: "com.Relay.relayResponseDelegateQueue")
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
    
    // MARK: Delegates
    public var relayResponseDelegate: RelayResponseDelegate? {
        get {
            return relayResponseDelegateQueue.sync {
                _relayResponseDelegate
            }
        }
        set {
            relayResponseDelegateQueue.async(flags: .barrier) {
                self._relayResponseDelegate = newValue
            }
        }
    }
    
    // MARK: Public Functions
    public func dataTask(with origRequest: URLRequest,
                         headersToEncrypt: [String]?,
                         completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        do {
            guard let host = try await retrieveHost(origRequest: origRequest) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            await host.dataTask(with: origRequest,
                                headersToEncrypt: headersToEncrypt,
                                completionHandler: completionHandler)
        } catch {
            self._relayResponseDelegate?.relayResponse(success: false,
                                                       responseStr: "error",
                                                       errorMessage: error.localizedDescription)
        }
    }
    
    public func uploadFileStream(request: URLRequest,
                                 headersToEncrypt: [String]?) throws {
        Task {
            guard let host = try await retrieveHost(origRequest: request) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            host.relayStreamResponseDelegate = self
            try await host.uploadFileStream(origRequest: request,
                                            headersToEncrypt: headersToEncrypt)
        }
    }
    
    public func download(request: URLRequest, downloadUrl: URL, headersToEncrypt: [String]?) throws {
        Task {
            guard let host = try await retrieveHost(origRequest: request) else {
                throw "Unable to retrieve Relay Server URL from request"
            }
            await host.downloadFileStream(origRequest: request,
                                headersToEncrypt: headersToEncrypt,
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
    
    public func setUploadChunkSize(_ size: Int) throws {
        if size < 4096 || size > 1024 * 1024 * 10 {
            throw "Upload chunk size must be between 4096 (4 KB) and 10485760 (1024 * 1024 * 10) (10 MB)"
        }
        RelaySettings.uploadChunkSize = size
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
            throw "Unable to create URL from relayPath"
        }
        
        hostStr.append("/")
        
        if let host = hostDictionary[hostStr] {
            return host
        } else {
            return try await instantiateHost(hostStr: hostStr)
        }
    }
    
    private func instantiateHost(hostStr: String) async throws -> Host {
        let host = try await Host(hostUrl: hostStr)
        host.relayResponseDelegate = self
        host.relayStreamDelegate = self
        host.relayStreamResponseDelegate = self
        hostDictionary[hostStr] = host
        return host
    }
    
    // Method to call the delegate method safely
    private func notifyDelegate(success: Bool, responseStr: String, errorMessage: String) {
        relayResponseDelegateQueue.async {
            self._relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
        }
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




