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

public class Relay: ObservableObject, RelayResponseDelegate, RelayStreamDelegate {
    
    public func getRequestBodyStream(outputStream: OutputStream, handle eventCode: Stream.Event) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream, handle: eventCode) ?? 0
    }
    
    public func relayResponse(success: Bool, responseStr: String, errorMessage: String) {
        if !success {
            relayError = .networkError
            relayStatus = .error
            notifyMteRelayError(message: errorMessage)
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
    var relayApiPath: String!
    public weak var _relayResponseDelegate: RelayResponseDelegate?
    public var relayStreamDelegate: RelayStreamDelegate?
    var relayResponseDelegateQueue = DispatchQueue(label: "com.Relay.relayResponseDelegateQueue")
    
    var host: Host!
    
    public init(relayPath: String) async throws {
        
        // Print MTE Version
#if DEBUG
        print("Using MTE Version \(MteBase.getVersion())")
#endif
        
        // Check MTE licensing
        if !MteBase.initLicense(RelaySettings.licCompanyName, RelaySettings.licCompanyKey) {
            throw "License Check failed."
        }
        
        if relayPath.last != "/" {
            self.relayApiPath = relayPath + "/"
        } else {
            self.relayApiPath = relayPath
        }
        
        host = try Host(hostUrl: relayApiPath)
        host.relayResponseDelegate = self
        host.relayStreamDelegate = self
    }
    
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

    // Method to call the delegate method safely
    func notifyDelegate(success: Bool, responseStr: String, errorMessage: String) {
        relayResponseDelegateQueue.async {
            self._relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
        }
    }
    
    public func dataTask(with origRequest: URLRequest, headersToEncrypt: [String]?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        await host.dataTask(with: origRequest, headersToEncrypt: headersToEncrypt, completionHandler: completionHandler)
    }
    
    public func uploadFileStream(request: inout URLRequest, headersToEncrypt: [String]?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
        await host.uploadFileStream(origRequest: &request, headersToEncrypt: headersToEncrypt, completionHandler: completionHandler)
    }
    
    public func download(request: inout URLRequest, downloadUrl: URL, headersToEncrypt: [String]?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
        await host.download(origRequest: &request, headersToEncrypt: headersToEncrypt, downloadUrl: downloadUrl, completionHandler: completionHandler)
    }
    
    public func rePairMte() throws {
        try host.rePairMte()
        relayStatus = .noAttempt
    }
    
    func notifyMteRelayError(message: String) {
        DispatchQueue.main.async {
            self.relayStatus = .error
#if DEBUG
            print("MteRelay Error. Message: \(message)")
#endif
        }
    }
    
    public func setUploadChunkSize(_ size: Int) throws {
        if size < 4096 || size > 1024 * 1024 {
            throw "Upload chunk size must be between 4096 and 1048576 (1024 * 1024) bytes"
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
    
}




