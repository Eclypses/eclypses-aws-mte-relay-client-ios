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

class Host: RelayStreamResponseDelegate, RelayStreamDelegate, FileUploadResultDelegate, FileDownloadResultDelegate {
    
    
    // MARK: Delegate methods
    func getRequestBodyStream(outputStream: OutputStream) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream) ?? 0
    }
    
    func response(success: Bool, responseStr: String, errorMessage: String) {
        if success {
            self.conditionallyStoreStates()
        }
        relayResponseDelegate?.relayResponse(success: success, responseStr: responseStr, errorMessage: errorMessage)
    }
    
    func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        relayStreamResponseDelegate?.streamCompletionPercentage(bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    // MARK: init
    init(hostUrl: String) async throws {
        self.hostUrl = hostUrl
        self.hostUrlB64 = hostUrl.toBase64()
        await setUpPairs()
    }
    
    // MARK: Class variables
    weak var relayResponseDelegate: RelayResponseDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    weak var fileUploadResultDelegate: FileUploadResultDelegate?
    var hostUrl: String!
    var hostUrlB64: String!
    
    var hostStorageHelper: HostStorageHelper!
    var mteHelper: MteHelper!
    var hostPaired = false
    private var prevDataTask: PrevDataTask!
    private var prevUploadTask: PrevUploadTask!
    private var prevDownloadTask: PrevDownloadTask!
    
    private struct PrevDataTask {
        let request: URLRequest
        let headersToEncrypt: [String]?
        let completionHandler: @Sendable (Data?, URLResponse?, Error?) -> Void
    }
    
    private struct PrevUploadTask {
        let origRequest: URLRequest
        let headersToEncrypt: [String]?
    }
    
    private struct PrevDownloadTask {
        let origRequest: URLRequest
        let headersToEncrypt: [String]?
        let downloadUrl: URL
    }
    
    
    // MARK: Public functions
    public func dataTask(with request: URLRequest,
                         headersToEncrypt: [String]?,
                         completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        
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
            try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                     origRequest: request,
                                     relayRequest: &createRelayRequestResult.request,
                                     headersToEncrypt: headersToEncrypt!)
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
        let task = URLSession.shared.dataTask(with: createRelayRequestResult.request) { (data, response, error) in
            Task {
                if let error = error {
                    completionHandler(data, response, error)
                    return
                }
                guard let relayResponse = response as? HTTPURLResponse else {
                    completionHandler(data, response, MteRelayError.networkError)
                    return
                }
                if PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)) {
                    Task.init {
                        try await self.rePairHost()
                    }
                    return
                }
                
                // Retrieve Relay Header
                var responseHeaders = RelayHeaders()
                guard let mteRelayHeaderStr = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue) else {
                    completionHandler(data, response,"No '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                    return
                }
                guard let relayOptions = parseMteRelayHeader(header: mteRelayHeaderStr) else {
                    completionHandler(data, response,"Unable to parse '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response. ")
                    return
                }
                responseHeaders.clientId = relayOptions.clientId
                responseHeaders.pairId = relayOptions.pairId
                
                // decrypt any encrypted headers
                var decryptedHeadersDictionary = [String:String]()
                do {
                    let decryptedHeaders = try await self.decryptHeaders(pairId: relayOptions.pairId, response: response!)
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
                    self.conditionallyStoreStates()
                    
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
                    completionHandler(Data(decoded.decodedBytes), appResponse, error)
                    
                    // Since we have completed this call successfully, remove the data we stored in case we needed to retry the transmission
                    self.prevDataTask = nil
                    return
                } catch is MteRelayError {
                    completionHandler(data, response, MteRelayError.mteDecodeError)
                } catch {
                    completionHandler(data, response, error.localizedDescription)
                }
            }
        }
        task.resume()
    }
    
    func uploadFileStream(origRequest: URLRequest,
                          headersToEncrypt: [String]?) async throws {
        
        // Prepare for just one rePair/reSend attempt.
        if prevUploadTask == nil {
            prevUploadTask = PrevUploadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt)
        } else {
            prevUploadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        createRelayRequestResult = try await createRelayRequest(origRequest: origRequest)
        try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                 origRequest: origRequest,
                                 relayRequest: &createRelayRequestResult.relayRequest,
                                 headersToEncrypt: headersToEncrypt!)
        setRelayHeader(pairId: createRelayRequestResult.pairId, relayRequest: &createRelayRequestResult.relayRequest)
        createRelayRequestResult.relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let relayFileStreamUpload = RelayFileStreamUpload(mteHelper: mteHelper)
        relayFileStreamUpload.relayStreamDelegate = self
        relayFileStreamUpload.relayStreamResponseDelegate = self
        relayFileStreamUpload.fileUploadResultDelegate = self
        
        try await relayFileStreamUpload.uploadStream(request: createRelayRequestResult.relayRequest,
                                                     pairId: createRelayRequestResult.pairId)
    }
    
    // Delegate from RelayFileStreamUpload
    func fileUploadResult(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            
            guard let relayResponse = response as? HTTPURLResponse else {
                relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
                return
            }
            if PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)) {
                if prevUploadTask != nil {
                    Task {
                        try await rePairHost()
                        do {
                            try await uploadFileStream(origRequest: prevUploadTask.origRequest, headersToEncrypt: prevUploadTask.headersToEncrypt)
                        } catch {
                            relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error as? String)
                        }
                    }
                    return
                }
            }
        } else {
            if let data = data, let string = String(data: data, encoding: .utf8) {
                relayResponseDelegate?.relayResponse(success: true, responseStr: string, errorMessage: nil)
            } else {
                relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: "Unable to convert response Data to String")
            }
            prevUploadTask = nil
            self.conditionallyStoreStates()
        }
    }
    
    func downloadFileStream(origRequest: URLRequest,
                  headersToEncrypt: [String]?,
                  downloadUrl: URL) async {
        
        // Prepare for just one rePair/reSend attempt.
        if prevDownloadTask == nil {
            prevDownloadTask = PrevDownloadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt, downloadUrl: downloadUrl)
        } else {
            prevDownloadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest)
            try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                     origRequest: origRequest,
                                     relayRequest: &createRelayRequestResult.relayRequest,
                                     headersToEncrypt: headersToEncrypt!)
            setRelayHeader(pairId: createRelayRequestResult.pairId, relayRequest: &createRelayRequestResult.relayRequest)
        } catch {
            relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: "Unable to create RelayRequest. Error: \(error.localizedDescription)")
        }
        let relayFileStreamDownload = RelayFileStreamDownload(mteHelper: mteHelper)
        relayFileStreamDownload.fileDownloadResultDelegate = self
        relayFileStreamDownload.downloadStream(request: createRelayRequestResult.relayRequest,
                                               pairId: createRelayRequestResult.pairId,
                                               downloadUrl: downloadUrl)
    }
    
    // Delegate from RelayFileStreamDownload
    func fileDownloadResult(storedFileUrl: URL?, response: URLResponse?, error: (any Error)?) {
        if let error = error {
            guard let relayResponse = response as? HTTPURLResponse else {
                relayResponseDelegate?.relayResponse(success: false, responseStr: "Network Error", errorMessage: error.localizedDescription)
                return
            }
            if PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)) {
                if prevDownloadTask != nil {
                    Task {
#if DEBUG
                        print("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
#endif
                        try await rePairHost()
//                        do {
                            await downloadFileStream(origRequest: prevDownloadTask.origRequest, headersToEncrypt: prevDownloadTask.headersToEncrypt, downloadUrl: prevDownloadTask.downloadUrl)
//                        } catch {
//                            relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error as! String)
//                        }
                    }
                    return
                }
            }
        } else {
            relayResponseDelegate?.relayResponse(success: true, responseStr: "Successfully downloaded file to \(storedFileUrl?.path() ?? "")", errorMessage: nil)
            prevDownloadTask = nil
            self.conditionallyStoreStates()
        }
    }
    
    func rePairHost() async throws {
        try hostStorageHelper.removeHostStoredPairs()
        await setUpPairs()
    }
    
    
    //MARK: Private functions
    fileprivate func setUpPairs() async {
        self.mteHelper = MteHelper()
        do {
            await self.hostStorageHelper = try HostStorageHelper(hostB64: hostUrlB64)
            if hostStorageHelper.storedHost != nil {
                RelaySettings.clientId = hostStorageHelper.storedHost.clientId
                do {
                    if hostStorageHelper.storedHost.storedPairs.count > 0 {
                        try mteHelper.refillPairDictionary(storedHost: hostStorageHelper.storedHost)
                    } else {
#if DEBUG
                        if !RelaySettings.persistPairs {
                            print("Persistant MTE State Storage not enabled. Pairing with \(String(describing: hostUrl)).")
                        } else {
                            print("Stored Pairs not found so we'll re-pair with \(String(describing: hostUrl)).")
                        }
#endif
                        let pairingResult = try PairingHelper.pairWithHost(hostUrl: self.hostUrl, mteHelper: self.mteHelper)
                        
                        if try await pairingResult.value {
                            response(success: true, responseStr: "Successfully rePaired with \(self.hostUrl!)", errorMessage: "")
                            conditionallyStoreClientIdOnly()
                            if prevDataTask != nil {
#if DEBUG
                                print("Retrying previous request.")
#endif
                                await dataTask(with: prevDataTask.request,
                                               headersToEncrypt: prevDataTask.headersToEncrypt,
                                               completionHandler: prevDataTask.completionHandler)
                            }
                        }
                    }
                } catch {
                    response(success: false, responseStr: "Unable to restore previous Pairing with \(self.hostUrl!)", errorMessage: error.localizedDescription)
                }
            } else {
                do {
                    let pairingResult = try PairingHelper.pairWithHost(hostUrl: hostUrl, mteHelper: mteHelper)
                    if try await pairingResult.value {
                        response(success: true, responseStr: "Successfully Paired with \(self.hostUrl!)", errorMessage: "")
                        conditionallyStoreClientIdOnly()
                    }
                } catch {
                    response(success: false, responseStr: "Unable to Pair with \(self.hostUrl!)", errorMessage: error.localizedDescription)
                }
            }
        } catch {
            response(success: false, responseStr: "\(self.hostUrl!) pairing failed! Error: ", errorMessage: error.localizedDescription)
        }
    }
    
    fileprivate func decryptHeaders(pairId: String, response: URLResponse) async throws -> String {
        var decryptedHeadersResult = DecodeResult()
        do {
            if let encodedHeaders = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: MteSettings.xMteRelayEh) {
                decryptedHeadersResult = try mteHelper.decode(pairId: pairId, encoded: encodedHeaders)
            } else {
#if DEBUG
                print("No \(MteSettings.xMteRelayEh) header in Response")
#endif
            }
        } catch {
            throw "Unable to decrypt \(MteSettings.xMteRelayEh) in Response. Error: \(error.localizedDescription)"
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
        let pairId = try await encryptPath(components: &components)
        
        // construct the new relay path
        guard let newRelayPath = components.string, let relayUrl = URL(string: newRelayPath) else {
            throw "Unable to create relay URL string from path components"
        }
        
        // initialize the relay request with the relay url and set original request method as the relay request method.
        relayRequest = URLRequest(url: relayUrl)
        relayRequest.httpMethod = origRequest.httpMethod
        return (pairId, relayRequest)
    }
    
    private func encryptPath(components: inout URLComponents) async throws -> String {
        
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
    
    private func encryptHeaders(pairId: String, origRequest: URLRequest, relayRequest: inout URLRequest, headersToEncrypt: [String]) async throws {
        var origHeaders = origRequest.allHTTPHeaderFields!
        
        // Encrypt Content-Type header and other headers as requested
        let encryptedHeadersResult = try await mteHelper.encryptHeaders(pairId: pairId,
                                                                        allHeaders: &origHeaders,
                                                                        headersToEncrypt: headersToEncrypt)
        relayRequest.setValue(encryptedHeadersResult.encodedStr, forHTTPHeaderField:  MteSettings.xMteRelayEh)
        
        // Set a new header for any remaining headers
        for header in origHeaders {
            relayRequest.setValue(header.value, forHTTPHeaderField: header.key)
        }
    }
    
    private func setRelayHeader(pairId: String, relayRequest: inout URLRequest) {
        let bodyIsEncoded = relayRequest.httpMethod == "GET" ? false : true
        let relayOptions = RelayOptions(clientId: RelaySettings.clientId,
                                        pairId: pairId,
                                        encodeType: EncoderType.MKE.rawValue,
                                        urlIsEncoded: true,
                                        headersAreEncoded: true,
                                        bodyIsEncoded: bodyIsEncoded)
        relayRequest.setValue(formatMteRelayHeader(options: relayOptions), forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue)
    }
    
    private func conditionallyStoreStates() {
        if RelaySettings.persistPairs {
            Task {
                do {
                    try await self.hostStorageHelper.storeStates(hostUrlB64: self.hostUrlB64, mteHelper: self.mteHelper)
                } catch {
#if DEBUG
                    print("Unable to persist Mte State: \(error.localizedDescription)")
#endif
                    self.relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
                }
            }
        }
    }
    
    private func conditionallyStoreClientIdOnly() {
        if !RelaySettings.persistPairs {
            Task {
                do {
#if DEBUG
                    print("Storing ClientId Only")
#endif
                    try await self.hostStorageHelper.storeClientIdOnly(hostUrlB64: self.hostUrlB64)
                } catch {
#if DEBUG
                    print("Unable to store ClientId only: \(error.localizedDescription)")
#endif
                    self.relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
                }
            }
        }
    }
    
}
