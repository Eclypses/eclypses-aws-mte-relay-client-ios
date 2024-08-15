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

class RelayFileStreamUpload: NSObject, URLSessionDelegate, StreamDelegate, URLSessionStreamDelegate, URLSessionDataDelegate {
    
    init(mteHelper: MteHelper) {
        self.mteHelper = mteHelper
        self.uploadActor = UploadActor()
    }
    
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    var mteHelper: MteHelper!
    var pairId: String!
    var originalContentLength = 0
    var relayContentLength = 0
    var bytesReadFromApp = 0
    var responsePairId: String!
    var encryptedByteCount = 0
    var uploadActor: UploadActor!
    var startTime: Date!
    var endTime: Date!
    
    actor UploadActor {
        
        enum UploadState {
            case notStarted
            case getFileStarted
            case readyToEncrypt
            case encryptInProgress
            case encryptFinished
            case uploadInProgress
            case uploadComplete
        }
        
        var state: UploadState = .notStarted
        
        func updateState(to newState: UploadState) {
            state = newState
        }
    }
    
    
    lazy var session: URLSession = URLSession(configuration: .default,
                                              delegate: self,
                                              delegateQueue: .main)
    // MARK: Bound Streams
    struct FileBoundStreams {
        let input: InputStream
        let output: OutputStream
    }
    
    lazy var fileBoundStreams: FileBoundStreams = {
        var inputOrNil: InputStream? = nil
        var outputOrNil: OutputStream? = nil
        Stream.getBoundStreams(withBufferSize: RelaySettings.uploadChunkSize,
                               inputStream: &inputOrNil,
                               outputStream: &outputOrNil)
        guard let input = inputOrNil, let output = outputOrNil else {
            fatalError("On return of `getBoundStreams`, both `inputStream` and `outputStream` will contain non-nil streams.")
        }
        // configure and open output stream
        output.delegate = self
        output.schedule(in: .current, forMode: .default)
        output.open()
        return FileBoundStreams(input: input, output: output)
    }()
    
    struct NetworkBoundStreams {
        let input: InputStream
        let output: OutputStream
    }
    
    lazy var networkBoundStreams: NetworkBoundStreams = {
        var inputOrNil: InputStream? = nil
        var outputOrNil: OutputStream? = nil
        Stream.getBoundStreams(withBufferSize: RelaySettings.uploadChunkSize,
                               inputStream: &inputOrNil,
                               outputStream: &outputOrNil)
        guard let input = inputOrNil, let output = outputOrNil else {
            fatalError("On return of `getBoundStreams`, both `inputStream` and `outputStream` will contain non-nil streams.")
        }
        // configure and open output stream
        output.delegate = self
        output.schedule(in: .current, forMode: .default)
        output.open()
        return NetworkBoundStreams(input: input, output: output)
    }()
    
    var responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?
    
    func uploadStream(request: inout URLRequest, pairId: String, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
        self.responseCompletionHandler = completionHandler
        self.pairId = pairId
        
        if let origContentLengthStr = request.value(forHTTPHeaderField: "Content-Length") {
            guard let origContentLength = Int(origContentLengthStr) else {
                await completionHandler(nil, nil, MteRelayError.updateRequestError)
                return
            }
            originalContentLength = origContentLength
            relayContentLength = origContentLength + mteHelper.getFinishEncryptBytes(pairId: pairId)
        }
        request.setValue(String(relayContentLength), forHTTPHeaderField: "Content-Length")
        
        // To begin, call StartEncrypt
        do {
            _ = try await mteHelper.startEncrypt(pairId: pairId)
        } catch {
            await completionHandler(nil, nil, MteRelayError.updateRequestError)
        }
        
        
        let newRelayRequest = request // can't pass an inout parameter to an escaping closure
        getFileStream(handle: Stream.Event.hasSpaceAvailable)
        Task {
            await uploadActor.updateState(to: .readyToEncrypt)
        }
        session.uploadTask(withStreamedRequest: newRelayRequest).resume()
    }
    
    
    // MARK: EncryptBodyStream Actor
    actor EncryptBodyStream {
        
        var uploadActor: UploadActor!
        var fileBoundStreams: FileBoundStreams!
        var networkBoundStreams: NetworkBoundStreams!
        var mteHelper: MteHelper!
        var pairId: String!
        var originalContentLength: Int!
        var encryptedByteCount = 0
        
        init(_ uploadActor: UploadActor,
             _ fileBoundStreams: FileBoundStreams,
             _ networkBoundStreams: NetworkBoundStreams,
             _ mteHelper: MteHelper,
             _ pairId: String,
             _ originalContentLength: Int) {
            self.uploadActor = uploadActor
            self.fileBoundStreams = fileBoundStreams
            self.networkBoundStreams = networkBoundStreams
            self.mteHelper = mteHelper
            self.pairId = pairId
            self.originalContentLength = originalContentLength
        }
        
        func allBytesEncrypted() -> Bool {
            if encryptedByteCount == originalContentLength {
                Task {
                    await uploadActor.updateState(to: .encryptFinished)
                }
                return true
            }
            return false
        }
        
        func encryptBody() async throws {
            var index = 0
            var fileBuffer = [UInt8](repeating: 0, count: RelaySettings.uploadChunkSize)
            while  await self.uploadActor.state == .encryptInProgress {
                while self.fileBoundStreams.input.hasBytesAvailable {
                    index += 1
                    let bytesRead = self.fileBoundStreams.input.read(&fileBuffer, maxLength: RelaySettings.uploadChunkSize)
                    if bytesRead == 0 {
                        break
                    }
                    var bufferToEncrypt = Array(fileBuffer.prefix(bytesRead))
                    _ = try await self.mteHelper.encryptChunk(pairId: self.pairId, buffer: &bufferToEncrypt)
                    self.networkBoundStreams.output.write(bufferToEncrypt, maxLength: bufferToEncrypt.count)
                    self.encryptedByteCount += bufferToEncrypt.count
#if DEBUG
                    print("FileBoundStream.input bytes read: \(bytesRead)")
                    print("Bytes written to NetworkBoundStreams.output: \(bufferToEncrypt.count)")
                    print("Current encryptedByteCount: \(self.encryptedByteCount)")
#endif
                }
                if self.allBytesEncrypted() {
                    fileBoundStreams.input.close()
                    let finishEncryptResult = try await self.mteHelper.finishEncrypt(pairId: self.pairId)
                    self.networkBoundStreams.output.write(finishEncryptResult.encodedBytes, maxLength: finishEncryptResult.encodedBytes.count)
                    self.encryptedByteCount += finishEncryptResult.encodedBytes.count
                    self.networkBoundStreams.output.close()
                }
            }
        }
    }
    
    private func getFileStream(handle eventCode: Stream.Event) {
        Task {
            await uploadActor.updateState(to: .getFileStarted)
        }
        DispatchQueue.global().async {
            self.fileBoundStreams.input.open()
            self.bytesReadFromApp = self.relayStreamDelegate?.getRequestBodyStream(outputStream: self.fileBoundStreams.output, handle: eventCode) ?? 0
        }
    }
    
    // MARK: Delegate Methods
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream == networkBoundStreams.output else {
            return
        }
        if eventCode.contains(.hasSpaceAvailable) {
            Task {
                if await self.uploadActor.state == .readyToEncrypt {
                    await uploadActor.updateState(to: .encryptInProgress)
                    let encryptActor = EncryptBodyStream(uploadActor,
                                                         fileBoundStreams,
                                                         networkBoundStreams,
                                                         mteHelper,
                                                         pairId,
                                                         originalContentLength)
                    do {
                        startTime = Date()
                        try await encryptActor.encryptBody()
                    } catch {
                        self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. Error: \(error.localizedDescription)")
                    }
                }
            }
        }
        if eventCode.contains(.errorOccurred) {
            // Close the streams and alert the user that the upload failed.
            self.fileBoundStreams.output.close()
            self.fileBoundStreams.input.close()
            self.networkBoundStreams.output.close()
            self.networkBoundStreams.input.close()
            self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. NetworkBoundStream returned error.")
        }
    }
    
    // Attach networkBoundStream.input to URLSession.dataTask
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        completionHandler(networkBoundStreams.input)
    }
    
    // Useful for initial debugging
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
#if DEBUG
        print("Bytes Sent: \(bytesSent)")
        print("Total Bytes Sent: \(totalBytesSent)")
        print("Total bytes expected to be sent: \(totalBytesExpectedToSend)")
#endif
    }
    
    // Called when upload is complete to get the http response
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task.init {
            // Access the HTTP response
            if let relayResponse = response as? HTTPURLResponse {
#if DEBUG
                print("\n\tUpload of \(relayContentLength) bytes completed.")
                print("\tResponse Code: \(relayResponse.statusCode)")
#endif
                self.networkBoundStreams.input.close()
                completionHandler(.allow)
            }
        }
    }
    
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
#if DEBUG
        print("Did ReceiveResponse of: \(data.count) bytes")
        endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        print("File upload completed in \(duration) seconds")
#endif
        Task.init {
            if let relayResponse = dataTask.response as? HTTPURLResponse {
                if 200...226 ~= relayResponse.statusCode {
                    await processResponse(relayResponse, data)
                } else {
                    await responseCompletionHandler!(nil, nil, "Response Code: \(relayResponse.statusCode)")
                }
            }
        }
    }
    
    fileprivate func processResponse(_ relayResponse: HTTPURLResponse, _ data: Data) async {
        do {
            guard let mteRelayHeaderStr = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue) else {
                await responseCompletionHandler!(nil, nil, "No '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                return
            }
            guard let relayOptions = parseMteRelayHeader(header: mteRelayHeaderStr) else {
                await responseCompletionHandler!(nil, nil, "Unable to parse '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                return
            }
            
            // decrypt any encrypted headers
            responsePairId = relayOptions.pairId
            var decryptedHeadersDictionary = [String:String]()
            if relayOptions.headersAreEncoded {
                if let encryptedHeaders = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelayEh.rawValue) {
                    let responseHeadersDecryptResult = try await mteHelper.decode(pairId: relayOptions.pairId, encoded: encryptedHeaders)
                    decryptedHeadersDictionary = try JSONDecoder().decode(Dictionary<String,String>.self, from: Data(responseHeadersDecryptResult.decodedStr.utf8))
                }
            }
            
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
            
            // Decrypt body
            let decodeResult = try await mteHelper.decode(pairId: responsePairId, encoded: data.bytes)
            await responseCompletionHandler!(Data(decodeResult.decodedBytes), appResponse, nil)
        } catch {
            await responseCompletionHandler!(nil, nil, error.localizedDescription)
            return
        }
    }
    
}
