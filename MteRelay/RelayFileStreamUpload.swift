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
    var fileBuffer = [UInt8](repeating: 0, count: RelaySettings.uploadChunkSize)
    var uploadState: UploadState = .notStarted
    
    lazy var session: URLSession = URLSession(configuration: .default,
                                              delegate: self,
                                              delegateQueue: .main)
    var responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?
    var startTime: Date!
    var endTime: Date!
    
    enum UploadState {
        case notStarted
        case getFileStarted
        case allBytesUploading
        case encryptInProgress
        case encryptFinished
        case uploadInProgress
        case uploadComplete
    }
    
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
            _ = try mteHelper.startEncrypt(pairId: pairId)
        } catch {
            await completionHandler(nil, nil, MteRelayError.updateRequestError)
        }
        
        let newRelayRequest = request // can't pass an inout parameter to an escaping closure
        
        uploadState = .encryptInProgress
#if DEBUG
        print("\n\nStarting upload")
        startTime = Date()
#endif
        getFileStream()
        session.uploadTask(withStreamedRequest: newRelayRequest).resume()
    }
    
    
    
    // MARK: Stream Delegate Methods
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard aStream == networkBoundStreams.output else {
            return
        }
        switch eventCode {
        case .openCompleted:
            print("networkBoundStreams.output is open")
        case .hasSpaceAvailable:
            if uploadState == .encryptInProgress {
                do {
                    if uploadState == .encryptInProgress {
                        try encryptChunk()
                    }
                } catch {
                    self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. Error: \(error.localizedDescription)")
                }
            }
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
    
    func encryptChunk() throws {
        if uploadState == .encryptInProgress {
            if fileBoundStreams.input.hasBytesAvailable {
                let bytesRead = fileBoundStreams.input.read(&fileBuffer, maxLength: RelaySettings.uploadChunkSize)
                if bytesRead > 0 {
                    var bufferToEncrypt = Array(fileBuffer.prefix(bytesRead))
                    _ = try self.mteHelper.encryptChunk(pairId: self.pairId, buffer: &bufferToEncrypt)
                    let bytesWritten = writeToOutputStream(outputStream: networkBoundStreams.output, buffer: Data(bufferToEncrypt))
                    encryptedByteCount += bytesWritten
                    if allBytesEncrypted() {
                        try finishEncrypt()
                    }
                }
            }
        }
    }
    
    func finishEncrypt() throws {
        if networkBoundStreams.output.hasSpaceAvailable {
            uploadState = .encryptFinished
            let finishEncryptResult = try self.mteHelper.finishEncrypt(pairId: self.pairId)
            let bytesWritten = writeToOutputStream(outputStream: networkBoundStreams.output, buffer: Data(finishEncryptResult.encodedBytes))
            self.encryptedByteCount += bytesWritten
            uploadState = .uploadComplete
#if DEBUG
            let ending = Date()
            let duration = ending.timeIntervalSince(self.startTime)
            print("Finished reading and encrypting \(self.encryptedByteCount) bytes in \(String(format: "%.3f", duration * 1000)) milliseconds")
#endif
            self.networkBoundStreams.output.close()
        }
    }
    
    func allBytesEncrypted() -> Bool {
        self.relayStreamResponseDelegate?.streamCompletionPercentage(bytesCompleted: Double(encryptedByteCount),
                                                                     totalBytes: Double(originalContentLength))
        if encryptedByteCount == originalContentLength {
            fileBoundStreams.output.close()
            fileBoundStreams.input.close()
            return true
        }
        return false
    }
    
    func writeToOutputStream(outputStream: OutputStream, buffer: Data) -> Int {
        var bytesLeft = buffer.count
        var totalBytesWritten = 0
        
        while bytesLeft > 0 {
            // Calculate the range of data to write
            let range = totalBytesWritten..<totalBytesWritten + bytesLeft
            let chunk = buffer.subdata(in: range)
            
            // Write data to the output stream
            let bytesWritten = chunk.withUnsafeBytes { outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytesLeft) }
            
            // Check for errors
            if bytesWritten < 0 {
                if let streamError = outputStream.streamError {
                    self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. Error: \(streamError.localizedDescription)")
                }
                break
            }
            
            // Update counters
            totalBytesWritten += bytesWritten
            bytesLeft -= bytesWritten
        }
        return totalBytesWritten
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
        print("Received response of: \(data.count) bytes")
        endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        print("File upload and response received in \(String(format: "%.3f", duration * 1000)) milliseconds")
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
    private func getFileStream() {
        DispatchQueue.global().async {
            self.fileBoundStreams.input.open()
            self.bytesReadFromApp = self.relayStreamDelegate?.getRequestBodyStream(outputStream: self.fileBoundStreams.output) ?? 0
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
                    let responseHeadersDecryptResult = try mteHelper.decode(pairId: relayOptions.pairId, encoded: encryptedHeaders)
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
            let decodeResult = try mteHelper.decode(pairId: responsePairId, encoded: data.bytes)
            await responseCompletionHandler!(Data(decodeResult.decodedBytes), appResponse, nil)
        } catch {
            await responseCompletionHandler!(nil, nil, error.localizedDescription)
            return
        }
    }
    
    
}
