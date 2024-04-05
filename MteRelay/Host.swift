//// The MIT License (MIT)
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
import os

class Host: RelayStreamResponseDelegate, RelayStreamDelegate {
    
    
    func getRequestBodyStream(outputStream: OutputStream, handle eventCode: Stream.Event) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream, handle: eventCode) ?? 0
    }
    
    // Delegate Method to return upload and Download responses
    func response(success: Bool, responseStr: String, errorMessage: String) {
        do {
            try hostStorageHelper.storeStates(hostUrlB64: hostUrlB64, mteHelper: mteHelper)
        } catch {
            relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
        }
        relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
    }
    
    weak var relayResponseDelegate: RelayResponseDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    var hostUrl: String!
    var hostUrlB64: String!
    
    var hostStorageHelper: HostStorageHelper!
    var mteHelper: MteHelper!
    var hostPaired = false
    private var prevDataTask: PrevDataTask!
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Host.self)
    )
    
    private struct PrevDataTask {
        let request: URLRequest
        let headersToEncrypt: [String]?
        let completionHandler: @Sendable (Data?, URLResponse?, Error?) -> Void
    }
    
    init(hostUrl: String) throws {
        self.hostUrl = hostUrl
        self.hostUrlB64 = hostUrl.toBase64()
        setUpPairs()
    }
    
    
    fileprivate func setUpPairs() {
        self.mteHelper = MteHelper()
        Task.init(operation: {
            await self.hostStorageHelper = try HostStorageHelper(hostB64: hostUrlB64)
            if hostStorageHelper.storedHost != nil {
                RelaySettings.clientId = hostStorageHelper.storedHost.clientId
                if hostStorageHelper.storedHost.storedPairs.count > 0 {
                    try mteHelper.refillPairDictionary(storedHost: hostStorageHelper.storedHost)
                } else {
                    Self.logger.info("Stored Pairs not found so we'll re-pair with the Host.")
                    let pairingResult = try PairingHelper.pairWithHost(hostUrl: self.hostUrl, mteHelper: self.mteHelper)
                    
                    if try await pairingResult.value {
                        response(success: true, responseStr: "Successfully rePaired with Host \(self.hostUrl!)", errorMessage: "")
                        if prevDataTask != nil {
                            Self.logger.info("Retrying previous request.")
                            await dataTask(with: prevDataTask.request,
                                           headersToEncrypt: prevDataTask.headersToEncrypt,
                                           completionHandler: prevDataTask.completionHandler)
                        }
                    }
                }
            } else {
                Self.logger.info("StoredHost not found so we'll pair with the Host.")
                let pairingResult = try PairingHelper.pairWithHost(hostUrl: hostUrl, mteHelper: mteHelper)
                if try await pairingResult.value {
                    response(success: true, responseStr: "Successfully Paired with Host \(self.hostUrl!)", errorMessage: "")
                }
                
            }
        })
    }
    

    public func dataTask(with request: URLRequest, headersToEncrypt: [String]?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        
        // Limit rePair/reSend attempts to just one.
        if prevDataTask == nil {
            prevDataTask = PrevDataTask(request: request,
                                        headersToEncrypt: headersToEncrypt,
                                        completionHandler: completionHandler)
        } else {
            prevDataTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, request: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: request)
            try encryptHeaders(pairId: createRelayRequestResult.pairId, origRequest: request, relayRequest: &createRelayRequestResult.request, headersToEncrypt: headersToEncrypt!)
            setRelayHeader(pairId: createRelayRequestResult.pairId, relayRequest: &createRelayRequestResult.request)
            createRelayRequestResult.request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        } catch {
            completionHandler(nil, nil, MteRelayError.updateRequestError)
            return
        }
        
        // Encode Body
        if request.httpBody != nil && !request.httpBody!.isEmpty {
            guard let body = request.httpBody?.bytes else {
                completionHandler(nil, nil, MteRelayError.updateRequestError)
                return
            }
            do {
                let encodeBodyResult = try mteHelper.encode(pairId: createRelayRequestResult.pairId, bytes: body)
                createRelayRequestResult.request.httpBody = Data(encodeBodyResult.encodedBytes)
            } catch {
                completionHandler(nil, nil, MteRelayError.mteEncodeError)
                return
            }
        }
        
        // Make the network call to the host server
        URLSession.shared.dataTask(with: createRelayRequestResult.request) { (data, response, error) in
            if let error = error {
                completionHandler(data, response, error)
                return
            }
            guard let relayResponse = response as? HTTPURLResponse else {
                completionHandler(data, response, MteRelayError.networkError)
                return
            }
            if 200...226 ~= relayResponse.statusCode {
                
                // Retrieve Relay Header
                var responseHeaders = RelayHeaders()
                guard let mteRelayHeaderStr = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue) else {
                    completionHandler(data, response,"No '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                    return
                }
                guard let relayOptions = parseMteRelayHeader(header: mteRelayHeaderStr) else {
                    completionHandler(data, response,"Unable to parse '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                    return
                }
                responseHeaders.clientId = relayOptions.clientId
                responseHeaders.pairId = relayOptions.pairId
                
                // decrypt any encrypted headers
                var decryptedHeadersDictionary = [String:String]()
                do {
                    let decryptedHeaders = try self.decryptHeaders(pairId: relayOptions.pairId, response: response!)
                    if decryptedHeaders != "" {
                        decryptedHeadersDictionary = try JSONDecoder().decode(Dictionary<String,String>.self, from: Data(decryptedHeaders.utf8))
                    }
                    
                    // Retrieve response data and decrypt it
                    guard let data = data else {
                        let errorMessage = "Unable to convert data from server"
                        completionHandler(data, response, errorMessage)
                        return
                    }
                    let decoded = try self.mteHelper.decode(pairId: relayOptions.pairId, encoded: data.bytes)
                    try self.hostStorageHelper.storeStates(hostUrlB64: self.hostUrlB64, mteHelper: self.mteHelper)
                    
                    // Remove Relay Headers
                    var relayResponseHeaders = relayResponse.allHeaderFields as! [String:String]
                    RelayHeaderNames.allCases.forEach {
                        relayResponseHeaders.removeValue(forKey: $0.rawValue)
                    }
                    let mergedHeaders = relayResponseHeaders.merging(decryptedHeadersDictionary, uniquingKeysWith: {(_, second) in second})
                    
                    // Create a new Response to return to the app
                    let appResponse = HTTPURLResponse(url: relayResponse.url!,
                                                      statusCode: relayResponse.statusCode,
                                                      httpVersion: nil,
                                                      headerFields: mergedHeaders)
                    completionHandler(Data(decoded.decodedBytes), appResponse, error);
                    
                    // Since we have completed this call successfully, remove the data we stored in case we needed to retry the transmission
                    self.prevDataTask = nil
                    return
                } catch is MteRelayError {
                    completionHandler(data, response, MteRelayError.mteDecodeError)
                } catch {
                    completionHandler(data, response, error.localizedDescription)
                }
            } else if 500...562 ~= relayResponse.statusCode {
                // These error codes indicate an Mte Pairing issue, so we will attempt to repair and resend, one time.
                Task.init {
                    try await self.tryRePair()
                }
            } else {
                completionHandler(data, response, "httpStatus code: \(relayResponse.statusCode)")
            }
        }.resume()
    }
    
    func uploadFileStream(origRequest: inout URLRequest, headersToEncrypt: [String]?, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest)
            try encryptHeaders(pairId: createRelayRequestResult.pairId, origRequest: origRequest, relayRequest: &createRelayRequestResult.relayRequest, headersToEncrypt: headersToEncrypt!)
            setRelayHeader(pairId: createRelayRequestResult.pairId, relayRequest: &createRelayRequestResult.relayRequest)
            createRelayRequestResult.relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        } catch {
           
            return
        }
        let relayFileStreamUpload = RelayFileStreamUpload(mteHelper: mteHelper)
        relayFileStreamUpload.relayStreamDelegate = self
        relayFileStreamUpload.relayStreamResponseDelegate = self
        await relayFileStreamUpload.uploadStream(request: &createRelayRequestResult.relayRequest,
                                                 pairId: createRelayRequestResult.pairId) { (data, response, error) in
            do {
                try self.hostStorageHelper.storeStates(hostUrlB64: self.hostUrlB64, mteHelper: self.mteHelper)
            } catch {
                self.relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
            }
            await completionHandler(data, response, error)
        }
    }
    
    func download(origRequest: inout URLRequest, headersToEncrypt: [String]?, downloadUrl: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest)
            try encryptHeaders(pairId: createRelayRequestResult.pairId, origRequest: origRequest, relayRequest: &createRelayRequestResult.relayRequest, headersToEncrypt: headersToEncrypt!)
            setRelayHeader(pairId: createRelayRequestResult.pairId, relayRequest: &createRelayRequestResult.relayRequest)
        } catch {
            await completionHandler(nil, nil, MteRelayError.updateRequestError)
        }
        
        let relayFileStreamDownload = RelayFileStreamDownload(mteHelper: mteHelper)
        relayFileStreamDownload.relayStreamResponseDelegate = self
        await relayFileStreamDownload.downloadStream(request: createRelayRequestResult.relayRequest,
                                                    pairId: createRelayRequestResult.pairId,
                                                    downloadUrl: downloadUrl) { (data, response, error) in
            do {
                try self.hostStorageHelper.storeStates(hostUrlB64: self.hostUrlB64, mteHelper: self.mteHelper)
            } catch {
                self.relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
            }
            await completionHandler(data, response, error)
        }
    }
    
    fileprivate func decryptHeaders(pairId: String, response: URLResponse) throws -> String {
        var decryptedHeadersResult = DecodeResult()
        do {
            if let encodedHeaders = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: MteSettings.xMteRelayEh) {
                decryptedHeadersResult = try mteHelper.decode(pairId: pairId, encoded: encodedHeaders)
            } else {
                print("No \(MteSettings.xMteRelayEh) header in Response")
            }
        } catch {
            throw "Unable to decrypt \(MteSettings.xMteRelayEh) in Response"
        }
        return decryptedHeadersResult.decodedStr
    }
    
    fileprivate func createRelayRequest(origRequest: URLRequest) async throws -> (String, URLRequest) {
        var relayRequest: URLRequest!
        
        // create Url for Relay Server
        guard let relayUrl = URL(string: hostUrl) else {
            throw "Unable to create URL from relayPath"
        }
        
        // get original url components
        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port
        components.path = String(origRequest.url!.path)
        
        // encrypt the path component and return the pairId used to do it.
        let pairId = try encryptPath(components: &components)
        
        // construct the new relay path
        guard let newRelayPath = components.string, let relayUrl = URL(string: newRelayPath) else {
            throw "Unable to create relay URL string from path components"
        }
        
        // initialize the relay request with the relay url and set original request method as the relay request method.
        relayRequest = URLRequest(url: relayUrl)
        relayRequest.httpMethod = origRequest.httpMethod
        return (pairId, relayRequest)
    }
    
    private func encryptPath(components: inout URLComponents) throws -> String {
        
        // we don't want to encrypt the "/" preceeding the path component
        let modifiedPath = String(components.path.dropFirst())
        
        // encrypt the path component. This is the first time we encrypt so pairId will be nil
        let encryptPathResult = try mteHelper.encode(pairId: nil, plaintext: modifiedPath)
        guard let pairId = encryptPathResult.pairId else {
            throw "No pairId returned from 'encryptPath' call"
        }
        
        // UrlEncode the encrypted path component, then add the preceeding "/" back in and return the pairId.
        let urlEncodedPath = encryptPathResult.encodedStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        components.path = "/" + urlEncodedPath!
        return pairId
    }
    
    func encryptHeaders(pairId: String, origRequest: URLRequest, relayRequest: inout URLRequest, headersToEncrypt: [String]) throws {
        var origHeaders = origRequest.allHTTPHeaderFields!
        
        // Encrypt Content-Type header and other headers as requested
        let encryptedHeadersResult = try mteHelper.encryptHeaders(pairId: pairId, allHeaders: &origHeaders, headersToEncrypt: headersToEncrypt)
        relayRequest.setValue(encryptedHeadersResult.encodedStr, forHTTPHeaderField:  MteSettings.xMteRelayEh)
        
        // Set a new header for any remaining headers
        for header in origHeaders {
            relayRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }
    }
    
    func setRelayHeader(pairId: String, relayRequest: inout URLRequest) {
        let bodyIsEncoded = relayRequest.httpMethod == "GET" ? false : true
        let relayOptions = RelayOptions(clientId: RelaySettings.clientId,
                                        pairId: pairId,
                                        encodeType: EncoderType.MKE.rawValue,
                                        urlIsEncoded: true,
                                        headersAreEncoded: true,
                                        bodyIsEncoded: bodyIsEncoded)
        relayRequest.setValue(formatMteRelayHeader(options: relayOptions), forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue)
    }
    
    private func tryRePair() async throws {
        try hostStorageHelper.removeHost()
        setUpPairs()
        Self.logger.info("Attempting to rePair with \(self.hostUrlB64)")
    }
    
    public func rePairMte() throws {
        try hostStorageHelper.removeHost()
        Self.logger.info("We removed stored Pairs for \(self.hostUrlB64)")
    }
    
}
