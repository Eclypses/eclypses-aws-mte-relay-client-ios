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
    var tempFilename: String!
    var uploadState: UploadState = .notStarted
    
    
    lazy var session: URLSession = URLSession(configuration: .default,
                                              delegate: self,
                                              delegateQueue: .main)
    
    struct Streams {
        let input: InputStream
        let output: OutputStream
    }
    
    lazy var fileBoundStreams: Streams = {
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
        return Streams(input: input, output: output)
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
            _ = try mteHelper.startEncrypt(pairId: pairId)
        } catch {
            await completionHandler(nil, nil, MteRelayError.updateRequestError)
        }
        
        
        let newRelayRequest = request // can't pass an inout parameter to an escaping closure
        tempFilename = getRandomString(length: 20)
        getFileStream(handle: Stream.Event.hasSpaceAvailable)
        
        encryptFileToLocalStorage(filename: tempFilename) { [weak self] in
            guard let self = self else {return}
            uploadEncryptedFile(request: newRelayRequest, filename: tempFilename)
        }
    }
    
    func uploadStream(request: inout URLRequest, pairId: String) async throws {
        self.pairId = pairId
        
        if let origContentLengthStr = request.value(forHTTPHeaderField: "Content-Length") {
            guard let origContentLength = Int(origContentLengthStr) else {
                throw "Unable to parse Original Content Length"
            }
            originalContentLength = origContentLength
            relayContentLength = origContentLength + mteHelper.getFinishEncryptBytes(pairId: pairId)
        }
        request.setValue(String(relayContentLength), forHTTPHeaderField: "Content-Length")
        
        // To begin, call StartEncrypt
        _ = try mteHelper.startEncrypt(pairId: pairId)
        
        let newRelayRequest = request // can't pass an inout parameter to an escaping closure
        tempFilename = getRandomString(length: 20)
        getFileStream(handle: Stream.Event.hasSpaceAvailable)
        
        encryptFileToLocalStorage(filename: tempFilename) { [weak self] in
            guard let self = self else {return}
            uploadEncryptedFile(request: newRelayRequest, filename: tempFilename)
        }
    }
    
    func allBytesEncrypted() -> Bool {
        if encryptedByteCount == originalContentLength {
            uploadState = .encryptFinished
            return true
        }
        return false
    }
    
    func encryptFileToLocalStorage(filename: String, completion: @escaping () -> Void) {
        uploadState = .encryptInProgress
        DispatchQueue.global().async {
            guard let tempFileHandle = FileHandle(forWritingAtPath: self.getTempFilePath(filename: filename)) else {
                self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "Unable to create temp fileHandle")
                return
            }
            defer {
                tempFileHandle.closeFile()
                self.fileBoundStreams.input.close()
            }
            var fileBuffer = [UInt8](repeating: 0, count: RelaySettings.uploadChunkSize)
            while self.uploadState == .encryptInProgress {
                do {
                    while self.fileBoundStreams.input.hasBytesAvailable {
                        let bytesRead = self.fileBoundStreams.input.read(&fileBuffer, maxLength: RelaySettings.uploadChunkSize)
                        if bytesRead == 0 {
                            print("No bytes to read")
                            break
                        }
                        var bufferToEncrypt = Array(fileBuffer.prefix(bytesRead))
                        _ = try self.mteHelper.encryptChunk(pairId: self.pairId, buffer: &bufferToEncrypt)
                        
                        try tempFileHandle.write(contentsOf: bufferToEncrypt)
                        self.encryptedByteCount += bufferToEncrypt.count
                        //                        print("\(self.encryptedByteCount) total bytes encrypted")
                    }
                    if self.allBytesEncrypted() {
                        print("We have encrypted everything")
                        self.uploadState = .encryptFinished
                        let finishEncryptResult = try self.mteHelper.finishEncrypt(pairId: self.pairId)
                        try tempFileHandle.write(contentsOf: finishEncryptResult.encodedBytes)
                    }
                } catch {
                    self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "\(#function) failed. Error: \(error.localizedDescription)")
                }
            }
            completion()
        }
    }
    
    func uploadEncryptedFile(request: URLRequest, filename: String) {
        uploadState = .uploadInProgress
        DispatchQueue.global().async {
            let fileUrl = self.getTempFileUrl(filename: filename)
            self.session.uploadTask(with: request, fromFile: fileUrl).resume()
        }
    }
    
    func getFileStream(handle eventCode: Stream.Event) {
        uploadState = .getFileStarted
        DispatchQueue.global().async {
            self.fileBoundStreams.input.open()
            self.bytesReadFromApp = self.relayStreamDelegate?.getRequestBodyStream(outputStream: self.fileBoundStreams.output, handle: eventCode) ?? 0
            print("GFS - We have put \(self.bytesReadFromApp) total bytes in MultipartFile OutputStream to encrypt")
        }
    }
    
    // MARK: Delegate Methods
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        //        print("Bytes Sent: \(bytesSent)")
        //        print("Total Bytes Sent: \(totalBytesSent)")
        //        print("Total bytes expected to be sent: \(totalBytesExpectedToSend)")
    }
    
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task.init {
            // Access the HTTP response
            if let relayResponse = response as? HTTPURLResponse {
                print("\n\tUpload of \(relayContentLength) bytes completed.")
                print("\tResponse Code: \(relayResponse.statusCode)")
                completionHandler(.allow)
            }
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task.init {            
            if let relayResponse = dataTask.response as? HTTPURLResponse {
                if 200...226 ~= relayResponse.statusCode {
                    removeTempFile(filename: tempFilename)
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
            let decodeResult = try mteHelper.decode(pairId: responsePairId, encoded: data.bytes)
            await responseCompletionHandler!(Data(decodeResult.decodedBytes), appResponse, nil)
            
        } catch {
            await responseCompletionHandler!(nil, nil, error.localizedDescription)
            return
        }
    }
    
    enum UploadState {
        case notStarted
        case getFileStarted
        case encryptInProgress
        case encryptFinished
        case uploadInProgress
        case uploadComplete
    }
    
    func removeTempFile(filename: String) {
        let tempUrl = getTempFileUrl(filename: filename)
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: tempUrl.path)
            print("File deleted successfully")
        } catch {
            print("Error deleting file: \(error.localizedDescription)")
        }
    }
    
    func getTempFileUrl(filename: String) -> URL {
        var tempFileUrl: URL!
        do {
            guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw "Unable to get tempFileHandle"
            }
            let tempDir = "EncryptedTempFiles"
            tempFileUrl = docDir.appendingPathComponent(tempDir).appendingPathComponent(filename)
        } catch {
            relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: error.localizedDescription)
        }
        return tempFileUrl
    }
    
    func getTempFilePath(filename: String) -> String {
        var tempFilePath = ""
        do {
            guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw "Unable to get tempFileHandle"
            }
            let tempDir = "EncryptedTempFiles"
            let tempFileUrl = docDir.appendingPathComponent(tempDir).appendingPathComponent(filename)
            tempFilePath = tempFileUrl.path
            
            // Create Download DIrectory if it doesn't exist
            try FileManager.default.createDirectory(at: docDir.appending(path: tempDir), withIntermediateDirectories: true, attributes: nil)
            
            // This will create the file if it doesn't exist and overwrite it empty if it does exist
            FileManager.default.createFile(atPath: tempFileUrl.path, contents: nil)
        } catch {
            relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: error.localizedDescription)
        }
        return tempFilePath
    }
    
}
