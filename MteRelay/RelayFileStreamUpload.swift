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
    
    // MARK: init
    init(mteHelper: MteHelper) {
        self.mteHelper = mteHelper
        self.uploadActor = UploadActor()
    }
    
    // MARK: Class variables
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
    var encryptActor: EncryptActor!
    
    lazy var session: URLSession = URLSession(configuration: .default,
                                              delegate: self,
                                              delegateQueue: .main)
    var responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?
    var startTime: Date!
    var endTime: Date!
    
    actor UploadActor {
        
        enum UploadState {
            case notStarted
            case getFileStarted
            case allBytesUploading
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
    
    
    // MARK: Bound Streams
    struct FileBoundStreams {
        let input: InputStream
        let output: OutputStream
    }
    
    lazy var fileBoundStreams: FileBoundStreams = {
//        print("Initializing FileBoundStreams")
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
//        print("Initializing NetworkBoundStreams")
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
    
    // MARK: Public Functions
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
            await uploadActor.updateState(to: .encryptInProgress)
        }
        startTime = Date()
        session.uploadTask(withStreamedRequest: newRelayRequest).resume()
    }
    
    
    // MARK: EncryptBodyStream Actor
    actor EncryptActor {
        
        var uploadActor: UploadActor!
        var fileBoundStreams: FileBoundStreams!
        var networkBoundStreams: NetworkBoundStreams!
        var mteHelper: MteHelper!
        var pairId: String!
        var originalContentLength: Int!
        var encryptedByteCount = 0
        var fileBuffer = [UInt8](repeating: 0, count: RelaySettings.uploadChunkSize)
        weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
        
        init(_ uploadActor: UploadActor,
             _ fileBoundStreams: FileBoundStreams,
             _ networkBoundStreams: NetworkBoundStreams,
             _ relayStreamResponseDelegate: RelayStreamResponseDelegate,
             _ mteHelper: MteHelper,
             _ pairId: String,
             _ originalContentLength: Int) {
            self.uploadActor = uploadActor
            self.fileBoundStreams = fileBoundStreams
            self.networkBoundStreams = networkBoundStreams
            self.relayStreamResponseDelegate = relayStreamResponseDelegate
            self.mteHelper = mteHelper
            self.pairId = pairId
            self.originalContentLength = originalContentLength
        }
        
        var index = 1
        
        func encryptChunk() async throws {
            var writeIndex = 0
            print("\nBeginning Chunk \(index)")
            if await uploadActor.state == .encryptInProgress {
//                print("networkBoundStreams state: \(networkBoundStreams.output.streamStatus)")
                if fileBoundStreams.input.hasBytesAvailable && networkBoundStreams.output.hasSpaceAvailable {
                    let bytesRead = fileBoundStreams.input.read(&fileBuffer, maxLength: RelaySettings.uploadChunkSize)
                                        print("\nChunk \(index) - \(bytesRead) file bytes read")
                    if bytesRead > 0 {
                        var bufferToEncrypt = Array(fileBuffer.prefix(bytesRead))
                        
                        _ = try await self.mteHelper.encryptChunk(pairId: self.pairId, buffer: &bufferToEncrypt)
                                                print("Encrypted \(bufferToEncrypt.count) bytes")
                        let result = networkBoundStreams.output.write(bufferToEncrypt, maxLength: bufferToEncrypt.count)
                    print("Chunk \(index) - Wrote \(bufferToEncrypt.count) bytes to network output stream")
                        encryptedByteCount += bufferToEncrypt.count
                        networkBoundStreams.output
                        if allBytesEncrypted() {
                            try await finishEncrypt()
                        }
                    }
                    index += 1
                
                } else {
                    print("\n *********** NO SPACE TO WRITE CHUNK SO WE WON'T READ ONE! ***************" )
                    print("networkBoundStreams state:")
                    checkStreamStatus(stream: fileBoundStreams.output)
                    checkStreamStatus(stream: fileBoundStreams.input)
                    checkStreamStatus(stream: networkBoundStreams.output)
                    checkStreamStatus(stream: networkBoundStreams.input)
                }
            }
        }
        
        func finishEncrypt() async throws {
            if networkBoundStreams.output.hasSpaceAvailable {
                Task {
                    await uploadActor.updateState(to: .encryptFinished)
                    print("Ready for finishEncrypt bytes.")
                    let finishEncryptResult = try await self.mteHelper.finishEncrypt(pairId: self.pairId)
                    print("Retrieved \(finishEncryptResult.encodedBytes.count) finishEncryptBytes")
                    self.networkBoundStreams.output.write(finishEncryptResult.encodedBytes, maxLength: finishEncryptResult.encodedBytes.count)
                    print("Wrote \(finishEncryptResult.encodedBytes.count) bytes to networkBoundStreams.output")
                    self.encryptedByteCount += finishEncryptResult.encodedBytes.count
                    self.networkBoundStreams.output.close()
                    await uploadActor.updateState(to: .uploadInProgress)
                }
            }
        }
        
        func allBytesEncrypted() -> Bool {
            self.relayStreamResponseDelegate?.streamCompletionPercentage(bytesCompleted: Double(encryptedByteCount),
                                                                                    totalBytes: Double(originalContentLength))
//            print("Upload \((Double(encryptedByteCount) / Double(originalContentLength)) * 100) percent complete")
            if encryptedByteCount == originalContentLength {
                fileBoundStreams.output.close()
                fileBoundStreams.input.close()
                print("\nAll bytes have been read from fileBoundStream.input")
                return true
            }
            return false
        }
        
        // MARK: Test Methods
        func checkStreamStatus(stream: Stream) {
            if stream == networkBoundStreams.output {
                print("\nChecking status of NetworkBoundStream output")
            } else {
                print("\nChecking status of NetworkBoundStream input")
            }
            switch stream.streamStatus {
            case .notOpen:
                print("Stream is not open.")
            case .opening:
                print("Stream is in the process of opening.")
            case .open:
                print("Stream is open.")
            case .writing:
                print("Stream is writing.")
            case .atEnd:
                print("Stream is at the end.")
            case .closed:
                print("Stream is closed.")
            case .error:
                print("Stream encountered an error.")
            @unknown default:
                print("Unknown stream status.")
            }
            
            // Check if the stream can accept more data
            if networkBoundStreams.output.hasSpaceAvailable {
                print("OutputStream has space available.")
            } else {
                print("OutputStream does not have space available.")
            }
            
            if networkBoundStreams.input.hasBytesAvailable {
                print("InputStream has bytes available.")
            } else {
                print("InputStream does not have bytes available.")
            }
        }
    }
    
    
    
    // MARK: Delegate Methods
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream == networkBoundStreams.output else {
            return
        }
        switch eventCode {
        case .openCompleted:
            print("Stream opened successfully.")
        case .hasSpaceAvailable:
            Task {
                if encryptActor == nil {
                    encryptActor = EncryptActor(uploadActor,
                                                fileBoundStreams,
                                                networkBoundStreams,
                                                relayStreamResponseDelegate!,
                                                mteHelper,
                                                pairId,
                                                originalContentLength)
                }
                do {
                    if await self.uploadActor.state == .encryptInProgress {
                        try await encryptActor.encryptChunk()
                    } 
                } catch {
                    self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. Error: \(error.localizedDescription)")
                }
            }
        case .hasBytesAvailable:
            print("EventCode is hasBytesAvailable!")
        case .endEncountered:
            print("EventCode is endEncountered!")
        case .errorOccurred:
            print("Error occurred. Closing Streams")
            
            // Close the streams and alert the user that the upload failed.
            self.fileBoundStreams.output.close()
            self.fileBoundStreams.input.close()
            self.networkBoundStreams.output.close()
            self.networkBoundStreams.input.close()
            self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. NetworkBoundStream returned error.")
        default:
            print("EventCode is \(eventCode)")
        }
    }
    
    // Attach networkBoundStream.input to URLSession.dataTask
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        completionHandler(networkBoundStreams.input)
    }
    
    // Useful for initial debugging
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
//        #if DEBUG
//                print("Bytes Sent: \(bytesSent)")
//                print("Total Bytes Sent: \(totalBytesSent)")
//                print("Total bytes expected to be sent: \(totalBytesExpectedToSend)")
//        #endif
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
                print("File upload and response received in \(duration) seconds")
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
    
    //MARK: Private functions
    private func getFileStream(handle eventCode: Stream.Event) {
        Task {
            await uploadActor.updateState(to: .getFileStarted)
        }
        DispatchQueue.global().async {
            self.fileBoundStreams.input.open()
            self.bytesReadFromApp = self.relayStreamDelegate?.getRequestBodyStream(outputStream: self.fileBoundStreams.output, handle: eventCode) ?? 0
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
