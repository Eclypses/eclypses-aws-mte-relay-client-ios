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
        relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
    }
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Relay.self)
    )
    
    @Published var relayError: MteRelayError = .none
    
    var relayStatus: RelayStatus = .noAttempt
    var relayApiPath: String!
    public weak var relayResponseDelegate: RelayResponseDelegate?
    public var relayStreamDelegate: RelayStreamDelegate?
    
    var host: Host!
    
    public init(relayPath: String) async throws {
        
        
        
        // Print MTE Version
        Self.logger.info("Using MTE Version \(MteBase.getVersion())")
        
        // Check MTE licensing
        if !MteBase.initLicense(RelaySettings.licCompanyName, RelaySettings.licCompanyKey) {
            throw "License Check failed."
        }
        
        self.relayApiPath = relayPath
        
        host = try Host(hostUrl: relayApiPath)
        host.relayResponseDelegate = self
        host.relayStreamDelegate = self
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
            Self.logger.info("MteRelay Error. Message: \(message)")
        }
    }
    
}




