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


class Host: RelayStreamCompletionDelegate, RelayStreamDelegate, FileUploadResultDelegate, FileDownloadResultDelegate, MteHelperDelegate, @unchecked Sendable {
    
    // MARK: Delegate methods
    func getRequestBodyStream(outputStream: OutputStream) {
        relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream)
    }
    
    func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        relayStreamCompletionDelegate?.streamCompletionPercentage(from: hostUrl, bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    func pairingNeeded(for newPair: Pair) async throws {
        try await PairingHelper.addPair(hostUrl: hostUrl, pair: newPair, mteHelper: mteHelper)
        mteHelper.registerNewPairedPair(newPair)
    }
    
    // MARK: init
    init(hostUrl: String, relay: Relay) async throws {
        self.hostUrl = hostUrl
        self.hostUrlB64 = hostUrl.toBase64()
        self.relayResponseDelegate = relay
        self.relayStreamResponseDelegate = relay
        self.relayStreamCompletionDelegate = relay
        self.relayStreamDelegate = relay
        self.mteHelper = MteHelper()
        self.mteHelper.delegate = self
        await setUpPairs()
    }
    
    deinit {
        print(">>> deinit Host")
        mteHelper.cleanup()
    }
    
    // MARK: Class variables
    private let logger = PackageLogger.makeLogger(for: Host.self)
    weak var relayResponseDelegate: RelayResponseDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    
    var hostUrl: String!
    var hostUrlB64: String!
    
    var hostStorageHelper: HostStorageHelper!
    var mteHelper: MteHelper!
    var hostPaired = false
    private var prevDataTask: PrevDataTask!
    private var prevUploadTask: PrevUploadTask!
    private var prevDownloadTask: PrevDownloadTask!
    private var activeUploads: [UUID: FileStreamUpload] = [:]
    private var activeDownloads: [UUID: FileStreamDownload] = [:]
    
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
    func dataTask(with origRequest: URLRequest,
                  headersToEncrypt: [String]?,
                  pathnamePrefix: String?,
                  completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) async -> Void {
        
        // Limit rePair/reSend attempts to just one.
        if prevDataTask == nil {
            prevDataTask = PrevDataTask(request: origRequest,
                                        headersToEncrypt: headersToEncrypt,
                                        pathnamePrefix: pathnamePrefix,
                                        completionHandler: completionHandler)
        } else {
            prevDataTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        var bodyBytes = [UInt8]()
        var encryptBody = false
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
            
            // Process Request Headers
            var origHeaders = origRequest.allHTTPHeaderFields!
            try await processRequestHeaders(relayRequest: &createRelayRequestResult.relayRequest,
                                            mteHelper: mteHelper,
                                            pairId: createRelayRequestResult.pairId,
                                            origHeaders: &origHeaders,
                                            headersToEncrypt: headersToEncrypt)
            
            // Check for request body
            if origRequest.httpBody != nil && !origRequest.httpBody!.isEmpty {
                guard let body = origRequest.httpBody?.bytes else {
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
                           relayRequest: &createRelayRequestResult.relayRequest)
            createRelayRequestResult.relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        } catch {
            completionHandler(nil, nil, MteRelayError.updateRequestError)
            return
        }
        
        if encryptBody {
            do {
                let encodeBodyResult = try await mteHelper.encode(pairId: createRelayRequestResult.pairId, bytes: bodyBytes)
                createRelayRequestResult.relayRequest.httpBody = Data(encodeBodyResult.encodedBytes)
            } catch {
                completionHandler(nil, nil, MteRelayError.mteEncodeError)
                return
            }
        }
        
        mteHelper.releasePair(pairId: createRelayRequestResult.pairId)
        
        // Make the network call to the host server
        let task = URLSession.shared.dataTask(with: createRelayRequestResult.relayRequest) { [self] (data, response, error) in
            
            Task {
                if let error = error {
                    logger.error("\(error.localizedDescription)")
                    completionHandler(data, response, error)
                    return
                }
                guard let relayResponse = response as? HTTPURLResponse else {
                    completionHandler(data, response, MteRelayError.networkError)
                    return
                }
                logger.info("DataTask status code: \(relayResponse.statusCode)")
                if PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)) {
                    Task {
                        try await rePairHost()
                    }
                    return
                }
                
                do {
                    
                    // Process Response Headers, including decrypting as necessary
                    let processResponseHeadersResult = try processResponseHeaders(relayResponse: relayResponse,
                                                                                  mteHelper: self.mteHelper)
                    // Retrieve response data and decrypt it
                    guard let data = data else {
                        completionHandler(data, response, "Unable to convert data from server")
                        return
                    }
                    let decoded = try self.mteHelper.decode(pairId: processResponseHeadersResult.pairId, encoded: data.bytes)
                    self.conditionallyStoreStates()
                    
                    
                    
                    // Create a new Response to return to the app
                    let appResponse = HTTPURLResponse(url: relayResponse.url!,
                                                      statusCode: relayResponse.statusCode,
                                                      httpVersion: nil,
                                                      headerFields: processResponseHeadersResult.mergedHeaders)
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
        logger.info("\n\nStarting FileStream Upload")
        
        // Prepare for just one rePair/reSend attempt.
        if prevUploadTask == nil {
            prevUploadTask = PrevUploadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
        } else {
            prevUploadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        createRelayRequestResult = try await createRelayRequest(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
        logger.info("\("Using pairId: \(createRelayRequestResult.pairId) to encrypt Upload Request")")
        
        // Process Request Headers
        var origHeaders = origRequest.allHTTPHeaderFields!
        try await processRequestHeaders(relayRequest: &createRelayRequestResult.relayRequest,
                                        mteHelper: mteHelper,
                                        pairId: createRelayRequestResult.pairId,
                                        origHeaders: &origHeaders,
                                        headersToEncrypt: headersToEncrypt)
        
        setRelayHeader(pairId: createRelayRequestResult.pairId, bodyIsEncoded: true, relayRequest: &createRelayRequestResult.relayRequest)
        createRelayRequestResult.relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let uploadId = UUID()
        let upload = FileStreamUpload(hostUrl: hostUrl, mteHelper: mteHelper, uploadId: uploadId)
        upload.relayStreamDelegate = self
        upload.relayStreamCompletionDelegate = self
        upload.fileUploadResultDelegate = self
        
        try await upload.uploadStream(request: createRelayRequestResult.relayRequest,
                                      pairId: createRelayRequestResult.pairId)
    }
    
    // Delegate from RelayFileStreamUpload
    func fileUploadResult(data: Data?, response: URLResponse?, error: Error?, uploadId: UUID) {
        activeUploads[uploadId] = nil
        if error != nil,
           let relayResponse = response as? HTTPURLResponse,
           PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)),
           prevUploadTask != nil {
            
            Task {
                logger.info("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
                try await rePairHost()
                do {
                    try await uploadFileStream(origRequest: prevUploadTask.origRequest,
                                               headersToEncrypt: prevUploadTask.headersToEncrypt,
                                               pathnamePrefix: prevUploadTask.pathnamePrefix)
                } catch {
                    relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl, data: nil, response: nil, error: error)
                }
            }
            return
        }
        relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl, data: data, response: response, error: error)
        prevUploadTask = nil
        self.conditionallyStoreStates()
        
    }
    
    func downloadFileStream(origRequest: URLRequest,
                            headersToEncrypt: [String]?,
                            pathnamePrefix: String?,
                            downloadUrl: URL) async {
        logger.info("\n\nStarting FileStream download")
        
        // Prepare for just one rePair/reSend attempt.
        if prevDownloadTask == nil {
            prevDownloadTask = PrevDownloadTask(origRequest: origRequest, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix, downloadUrl: downloadUrl)
        } else {
            prevDownloadTask = nil
        }
        
        var createRelayRequestResult: (pairId: String, relayRequest: URLRequest)!
        do {
            createRelayRequestResult = try await createRelayRequest(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
            logger.info("\("Using pairId: \(createRelayRequestResult.pairId) to encrypt download Request")")
            
            // Process Request Headers
            var origHeaders = origRequest.allHTTPHeaderFields!
            try await processRequestHeaders(relayRequest: &createRelayRequestResult.relayRequest,
                                            mteHelper: mteHelper,
                                            pairId: createRelayRequestResult.pairId,
                                            origHeaders: &origHeaders,
                                            headersToEncrypt: headersToEncrypt)
            setRelayHeader(pairId: createRelayRequestResult.pairId, bodyIsEncoded: false, relayRequest: &createRelayRequestResult.relayRequest)
        } catch {
            relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl, data: nil as Data?, response: nil as URLResponse?, error: error)
        }
        let downloadId = UUID()
        let download = FileStreamDownload(hostUrl: hostUrl, mteHelper: mteHelper, downloadId: downloadId)
        download.fileDownloadResultDelegate = self
        download.relayStreamCompletionDelegate = self
        activeDownloads[downloadId] = download
        download.downloadStream(request: createRelayRequestResult.relayRequest,
                                downloadUrl: downloadUrl)
    }
    
    // Delegate from RelayFileStreamDownload
    func fileDownloadResult(storedFileUrl: URL?, response: URLResponse?, error: (any Error)?, downloadId: UUID) {
        activeDownloads[downloadId] = nil
        if error != nil,
           let relayResponse = response as? HTTPURLResponse,
           PairingHelper.checkForRePair(statusCode: String(relayResponse.statusCode)),
           prevDownloadTask != nil
        {
            Task {
                logger.info("Returned Status Code \(relayResponse.statusCode) so we'll rePair, then resend the request")
                try await rePairHost()
                await downloadFileStream(origRequest: prevDownloadTask.origRequest,
                                         headersToEncrypt: prevDownloadTask.headersToEncrypt,
                                         pathnamePrefix: prevDownloadTask.pathnamePrefix,
                                         downloadUrl: prevDownloadTask.downloadUrl)
            }
            return
        } else {
            
            // Create Response Data to signal that download was successful
            let storedFilePath = storedFileUrl?.path ?? ""
            let jsonObject: [String: Any] = [
                "success": true,
                "downloadLocation": "\(storedFilePath)"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted) {
                relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl, data: jsonData, response: response, error: error)
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
        do {
            await self.hostStorageHelper = try HostStorageHelper(hostB64: hostUrlB64)
            if hostStorageHelper.storedHost != nil {
                Settings.clientId = hostStorageHelper.storedHost.clientId
                do {
                    if hostStorageHelper.storedHost.storedPairs.count > 0 {
                        try mteHelper.refillPairDictionary(storedHost: hostStorageHelper.storedHost)
                    } else {
                        if !Settings.persistPairs {
                            logger.info("Persistent MTE State Storage not enabled. Pairing with \(self.hostUrl ?? "Unknown host").")
                        } else {
                            logger.info("Stored Pairs not found so we'll re-pair with \(self.hostUrl ?? "Unknown host").")
                        }
                        let pairingResult = try PairingHelper.initialPairingWithHost(hostUrl: self.hostUrl, mteHelper: self.mteHelper)
                        
                        if try await pairingResult.value {
                            relayResponseDelegate?.relayResponse(success: true, responseStr: "Successfully rePaired with \(self.hostUrl!)", errorMessage: "")
                            conditionallyStoreStates()
                            if prevDataTask != nil {
                                logger.info("Retrying previous request.")
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
                    let pairingResult = try PairingHelper.initialPairingWithHost(hostUrl: hostUrl, mteHelper: mteHelper)
                    if try await pairingResult.value {
                        relayResponseDelegate?.relayResponse(success: true, responseStr: "Successfully Paired with \(self.hostUrl!)", errorMessage: "")
                        conditionallyStoreStates()
                    }
                } catch {
                    relayResponseDelegate?.relayResponse(success: false, responseStr: "Unable to Pair with \(self.hostUrl!)", errorMessage: error.localizedDescription)
                }
            }
        } catch {
            relayResponseDelegate?.relayResponse(success: false, responseStr: "\(self.hostUrl!) pairing failed! Error: ", errorMessage: error.localizedDescription)
        }
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
        let encryptPathResult = try await mteHelper.encode(pairId: nil, plaintext: modifiedPath)
        guard let pairId = encryptPathResult.pairId else {
            throw "No pairId returned from 'encryptPath' call"
        }
        
        // UrlEncode the encrypted path component, then add the preceeding "/" back in and return the pairId.
        let urlEncodedPath = encryptPathResult.encodedStr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        components.path = "/" + urlEncodedPath!
        return pairId
    }
    
    private func setRelayHeader(pairId: String, bodyIsEncoded: Bool, relayRequest: inout URLRequest) {
        let relayOptions = RelayOptions(clientId: Settings.clientId,
                                        pairId: pairId,
                                        encodeType: EncoderType.MKE.rawValue,
                                        urlIsEncoded: true,
                                        headersAreEncoded: true,
                                        bodyIsEncoded: bodyIsEncoded)
        relayRequest.setValue(formatMteRelayHeader(options: relayOptions), forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue)
    }
    
    private func conditionallyStoreStates() {
        Task {
            var statesToStore = [StoredPair]()
            if Settings.persistPairs {
                statesToStore = try await mteHelper.getPairDictionaryStates()
                do {
                    try await self.hostStorageHelper.storeStates(storedPairs: statesToStore)
                } catch {
                    logger.error("Unable to persist Mte State: \(error.localizedDescription)")
                    self.relayResponseDelegate?.relayResponse(success: false, responseStr: "", errorMessage: error.localizedDescription)
                }
            }
        }
    }
    
}
