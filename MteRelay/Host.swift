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

class Host: RelayStreamCompletionDelegate, RelayStreamDelegate, FileUploadResultDelegate, FileDownloadResultDelegate {
    
    
    // MARK: Delegate methods
    func getRequestBodyStream(outputStream: OutputStream) -> Int {
        return relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream) ?? 0
    }
    
    func streamCompletionPercentage(bytesCompleted: Double, totalBytes: Double) {
        relayStreamCompletionDelegate?.streamCompletionPercentage(bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    // MARK: init
    init(hostUrl: String, relay: Relay) async throws {
        self.hostUrl = hostUrl
        self.hostUrlB64 = hostUrl.toBase64()
        self.relayResponseDelegate = relay
        await setUpPairs()
    }
    
    // MARK: Class variables
    weak var relayResponseDelegate: RelayResponseDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    
    var relayFileStreamUpload: RelayFileStreamUpload!
    var relayFileStreamDownload: RelayFileStreamDownload!
    
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
        let pathnamePrefix: String?
        let completionHandler: @Sendable (Data?, URLResponse?, Error?) -> Void
    }
    
    private struct PrevUploadTask {
        let origRequest: URLRequest
        let headersToEncrypt: [String]?
        let pathnamePrefix: String?
    }
    
    private struct PrevDownloadTask {
        let origRequest: URLRequest
        let headersToEncrypt: [String]?
        let pathnamePrefix: String?
        let downloadUrl: URL
    }
    
    
    // MARK: Public functions
    func dataTask(with request: URLRequest,
                  headersToEncrypt: [String]?,
                  pathnamePrefix: String?,
                  completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        
        // Limit rePair/reSend attempts to just one.
        if prevDataTask == nil {
            prevDataTask = PrevDataTask(request: request,
                                        headersToEncrypt: headersToEncrypt,
                                        pathnamePrefix: pathnamePrefix,
                                        completionHandler: completionHandler)
        } else {
            prevDataTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, request: URLRequest)!
        var bodyBytes = [UInt8]()
        var encryptBody = false
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: request, pathnamePrefix: pathnamePrefix)
            try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                     origRequest: request,
                                     relayRequest: &createRelayRequestResult.request,
                                     headersToEncrypt: headersToEncrypt!)
            // Check for request body
            if request.httpBody != nil && !request.httpBody!.isEmpty {
                guard let body = request.httpBody?.bytes else {
                    completionHandler(nil, nil, MteRelayError.updateRequestError)
                    return
                }
                bodyBytes = body
                if bodyBytes.count > 0 {
                    encryptBody = true
                }
            }
            setRelayHeader(pairId: createRelayRequestResult.pairId,
                           bodyIsEncoded: encryptBody,
                           relayRequest: &createRelayRequestResult.request)
            createRelayRequestResult.request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        } catch {
            completionHandler(nil, nil, MteRelayError.updateRequestError)
            return
        }
        
        if encryptBody {
            do {
                let encodeBodyResult = try mteHelper.encode(pairId: createRelayRequestResult.pairId, bytes: bodyBytes)
                createRelayRequestResult.request.httpBody = Data(encodeBodyResult.encodedBytes)
            } catch {
                completionHandler(nil, nil, MteRelayError.mteEncodeError)
                return
            }
        }
        
        // Make the network call to the host server
        let task = URLSession.shared.dataTask(with: createRelayRequestResult.request) { [self] (data, response, error) in
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
                          headersToEncrypt: [String]?,
                          pathnamePrefix: String?) async throws {
        
        // Prepare for just one rePair/reSend attempt.
        if prevUploadTask == nil {
            prevUploadTask = PrevUploadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
        } else {
            prevUploadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        createRelayRequestResult = try await createRelayRequest(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
        try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                 origRequest: origRequest,
                                 relayRequest: &createRelayRequestResult.relayRequest,
                                 headersToEncrypt: headersToEncrypt!)
        setRelayHeader(pairId: createRelayRequestResult.pairId, bodyIsEncoded: true, relayRequest: &createRelayRequestResult.relayRequest)
        createRelayRequestResult.relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        relayFileStreamUpload = RelayFileStreamUpload(mteHelper: mteHelper)
        relayFileStreamUpload.relayStreamDelegate = self
        relayFileStreamUpload.relayStreamCompletionDelegate = self
        relayFileStreamUpload.fileUploadResultDelegate = self
        
        try await relayFileStreamUpload.uploadStream(request: createRelayRequestResult.relayRequest,
                                                     pairId: createRelayRequestResult.pairId)
    }
    
    // Delegate from RelayFileStreamUpload
    func fileUploadResult(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error,
           let relayResponse = response as? HTTPURLResponse,
           PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)),
           prevUploadTask != nil
        {
            Task {
#if DEBUG
                print("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
#endif
                try await rePairHost()
                do {
                    try await uploadFileStream(origRequest: prevUploadTask.origRequest,
                                               headersToEncrypt: prevUploadTask.headersToEncrypt,
                                               pathnamePrefix: prevUploadTask.pathnamePrefix)
                } catch {
                    relayStreamResponseDelegate?.relayStreamResponse(data: nil, response: nil, error: error)
                }
            }
            return
        }
        relayStreamResponseDelegate?.relayStreamResponse(data: data, response: response, error: error)
        prevUploadTask = nil
        self.conditionallyStoreStates()
        
    }
    
    func downloadFileStream(origRequest: URLRequest,
                            headersToEncrypt: [String]?,
                            pathnamePrefix: String?,
                            downloadUrl: URL) async {
        
        // Prepare for just one rePair/reSend attempt.
        if prevDownloadTask == nil {
            prevDownloadTask = PrevDownloadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix, downloadUrl: downloadUrl)
        } else {
            prevDownloadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
            try await encryptHeaders(pairId: createRelayRequestResult.pairId,
                                     origRequest: origRequest,
                                     relayRequest: &createRelayRequestResult.relayRequest,
                                     headersToEncrypt: headersToEncrypt!)
            setRelayHeader(pairId: createRelayRequestResult.pairId, bodyIsEncoded: false, relayRequest: &createRelayRequestResult.relayRequest)
        } catch {
            relayStreamResponseDelegate?.relayStreamResponse(data: nil as Data?, response: nil as URLResponse?, error: error)
        }
        relayFileStreamDownload = RelayFileStreamDownload(mteHelper: mteHelper)
        relayFileStreamDownload.fileDownloadResultDelegate = self
        relayFileStreamDownload.downloadStream(request: createRelayRequestResult.relayRequest,
                                               pairId: createRelayRequestResult.pairId,
                                               downloadUrl: downloadUrl)
    }
    
    // Delegate from RelayFileStreamDownload
    func fileDownloadResult(storedFileUrl: URL?, response: URLResponse?, error: (any Error)?) {
        if let error = error,
           let relayResponse = response as? HTTPURLResponse,
           PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)),
           prevDownloadTask != nil
        {
            Task {
#if DEBUG
                print("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
#endif
                try await rePairHost()
                do {
                    await downloadFileStream(origRequest: prevDownloadTask.origRequest,
                                             headersToEncrypt: prevDownloadTask.headersToEncrypt,
                                             pathnamePrefix: prevDownloadTask.pathnamePrefix,
                                             downloadUrl: prevDownloadTask.downloadUrl)
                } catch {
                    relayStreamResponseDelegate?.relayStreamResponse(data: nil, response: nil, error: error)
                }
            }
            return
        } else {
//        }
//        relayStreamResponseDelegate?.relayStreamResponse(data: nil, response: response, error: error)
//        prevUploadTask = nil
//        self.conditionallyStoreStates()
        
        
        
//        if let error = error {
//            guard let relayResponse = response as? HTTPURLResponse else {
//                relayStreamResponseDelegate?.relayStreamResponse(data: nil as Data?, response: nil as URLResponse?, error: error)
//                return
//            }
//            
//            // See if we can rePair and reTry
//            if PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)) {
//                if prevDownloadTask != nil {
//                    Task {
//#if DEBUG
//                        print("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
//#endif
//                        try await rePairHost()
//                        await downloadFileStream(origRequest: prevDownloadTask.origRequest,
//                                                 headersToEncrypt: prevDownloadTask.headersToEncrypt,
//                                                 pathnamePrefix: prevDownloadTask.pathnamePrefix,
//                                                 downloadUrl: prevDownloadTask.downloadUrl)
//                    }
//                    return
//                }
//            }
//        } else {
            
            // Create Response Data to signal that download was successful
            let storedFilePath = storedFileUrl?.path() ?? ""
            let jsonObject: [String: Any] = [
                "success": true,
                "downloadLocation": "\(storedFilePath)"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                relayStreamResponseDelegate?.relayStreamResponse(data: jsonData, response: response, error: error)
            }
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
                            relayResponseDelegate?.relayResponse(success: true, responseStr: "Successfully rePaired with \(self.hostUrl!)", errorMessage: "")
                            conditionallyStoreClientIdOnly()
                            if prevDataTask != nil {
#if DEBUG
                                print("Retrying previous request.")
#endif
                                await dataTask(with: prevDataTask.request,
                                               headersToEncrypt: prevDataTask.headersToEncrypt,
                                               pathnamePrefix: prevDataTask.pathnamePrefix,
                                               completionHandler: prevDataTask.completionHandler)
                            }
                        }
                    }
                } catch {
                    relayResponseDelegate?.relayResponse(success: false, responseStr: "Unable to restore previous Pairing with \(self.hostUrl!)", errorMessage: error.localizedDescription)
                }
            } else {
                do {
                    let pairingResult = try PairingHelper.pairWithHost(hostUrl: hostUrl, mteHelper: mteHelper)
                    if try await pairingResult.value {
                        relayResponseDelegate?.relayResponse(success: true, responseStr: "Successfully Paired with \(self.hostUrl!)", errorMessage: "")
                        conditionallyStoreClientIdOnly()
                    }
                } catch {
                    relayResponseDelegate?.relayResponse(success: false, responseStr: "Unable to Pair with \(self.hostUrl!)", errorMessage: error.localizedDescription)
                }
            }
        } catch {
            relayResponseDelegate?.relayResponse(success: false, responseStr: "\(self.hostUrl!) pairing failed! Error: ", errorMessage: error.localizedDescription)
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
    
    fileprivate func createRelayRequest(origRequest: URLRequest, pathnamePrefix: String?) async throws -> (String, URLRequest) {
        var relayRequest: URLRequest!
        
        // retrieve Url from origRequest
        guard let relayUrl = origRequest.url else {
            throw "Unable to create URL from request"
        }
        
        // get original url components
        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port
        components.path = String(origRequest.url!.path)
        
        // prepare the pathnamePrefix if it exists
        var unencryptedPrefix = ""
        if var prefix = pathnamePrefix, pathnamePrefix?.first != "/" {
            prefix = "/" + prefix
            unencryptedPrefix = prefix
        }
        
        // encrypt the path component and return the pairId used to do it.
        let pairId = try await encryptPath(components: &components)
        
        
        // prepend the unencryptedPrefix to the path component if pathnamePrefix exists
        if pathnamePrefix != nil {
            components.path = unencryptedPrefix + components.path
        }
        
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
    
    private func setRelayHeader(pairId: String, bodyIsEncoded: Bool, relayRequest: inout URLRequest) {
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
                    print("Persistant MTE State Storage not enabled. Storing ClientId Only")
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
