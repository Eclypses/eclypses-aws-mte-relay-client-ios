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
import MKE

class RelayFileStreamDownload: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    // MARK: init
    init(mteHelper: MteHelper) {
        self.mteHelper = mteHelper
    }
    
    // MARK: Class variables
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    var mteHelper: MteHelper!
//    var pairId: String!
    var downloadedFilename: String = ""
    var newFileHandle: FileHandle!
    var storedFileUrl: URL!
    var appResponse: HTTPURLResponse!
    var responsePairId: String!
    var totalDownloadBytes: Double = 0
    var decryptActor: DecryptActor!
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration,
                          delegate: self, delegateQueue: nil)
    }()
    
    var responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?
    
    // MARK: Public functions
    func downloadStream(request: URLRequest, pairId: String, downloadUrl: URL, completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) async -> Void) async -> Void {
       
        self.responseCompletionHandler = completionHandler
        self.storedFileUrl = downloadUrl
        self.downloadedFilename = storedFileUrl.lastPathComponent
        print("\n\nStarting download of \(downloadedFilename) at \(getCurrentTimeWithMilliseconds())")
        do {
            newFileHandle = try FileHandle(forWritingTo: storedFileUrl)
            session.dataTask(with: request).resume()
        } catch {
            await responseCompletionHandler!(nil, nil, MteRelayError.fileSystemError)
        }
        
    }
    
    
    
    // MARK: delegate methods

    // Called when download starts to confirm mime type and response code
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task.init {
            guard let relayResponse = response as? HTTPURLResponse,
                  (200...299).contains(relayResponse.statusCode),
                  let mimeType = response.mimeType,
                  mimeType == "application/octet-stream" else {
                completionHandler(.cancel)
                await responseCompletionHandler!(nil, nil, MteRelayError.networkError)
                return
            }
            do {
                guard let mteRelayHeaderStr = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue) else {
                    await responseCompletionHandler!(nil, nil, "No '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                    return
                }
                guard let relayOptions = parseMteRelayHeader(header: mteRelayHeaderStr) else {
                    await responseCompletionHandler!(nil, nil, "Unable to parse '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response")
                    return
                }
                print("Completed parsing relay header at \(getCurrentTimeWithMilliseconds())")
                
                // decrypt any encrypted headers
                responsePairId = relayOptions.pairId
                var decryptedHeadersDictionary = [String:String]()
                if relayOptions.headersAreEncoded {
                    if let encryptedHeaders = relayResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelayEh.rawValue) {
                        let responseHeadersDecryptResult = try await mteHelper.decode(pairId: relayOptions.pairId, encoded: encryptedHeaders)
                        print("Completed decrypting headers at \(getCurrentTimeWithMilliseconds())")
                        decryptedHeadersDictionary = try JSONDecoder().decode(Dictionary<String,String>.self, from: Data(responseHeadersDecryptResult.decodedStr.utf8))
                    }
                }
                
                // Remove Relay Headers
                var relayResponseHeaders = relayResponse.allHeaderFields as! [String:String]
                RelayHeaderNames.allCases.forEach {
                    relayResponseHeaders.removeValue(forKey: $0.rawValue)
                }
                let mergedHeaders = relayResponseHeaders.merging(decryptedHeadersDictionary, uniquingKeysWith: {(_, second) in second})
                
                appResponse = HTTPURLResponse(url: relayResponse.url!,
                                              statusCode: relayResponse.statusCode,
                                              httpVersion: nil,
                                              headerFields: mergedHeaders)
                _ = try await mteHelper.startDecrypt(pairId: responsePairId)
                print("StartDecrypt at \(getCurrentTimeWithMilliseconds())")
                decryptActor = DecryptActor(mteHelper: mteHelper,
                                            pairId: responsePairId,
                                            fileHandle: newFileHandle,
                                            totalDownloadBytes: totalDownloadBytes,
                                            appResponse: appResponse,
                                            responseCompletionHandler: responseCompletionHandler)
                completionHandler(.allow)
            } catch {
                completionHandler(.cancel)
                await responseCompletionHandler!(nil, nil, error.localizedDescription)
                return
            }
        }
    }
    
    // Called periodically throughout download stream
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        Task {
            await decryptActor.decryptChunk(data: data)
        }
    }
    
    // Called when download is complete
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task.init {
            if let error = error {
                await responseCompletionHandler!(nil, nil, error.localizedDescription)
            } else {
                await decryptActor.finishDecrypt()
            }
        }
    }
    
    func getCurrentTimeWithMilliseconds() -> String {
        let currentDate = Date()
        
        // Create a date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS" // Set the format to include milliseconds
        
        // Convert date to string
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        return currentTimeString
    }
    
    //MARK: Private methods

    actor DecryptActor {
        
        var index = 0
        var mteHelper: MteHelper!
        var pairId: String
        var fileHandle: FileHandle!
        var totalDownloadBytes: Double!
        var appResponse: HTTPURLResponse!
        weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
        var responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?
        
        init(mteHelper: MteHelper,
             pairId: String,
             fileHandle: FileHandle,
             totalDownloadBytes: Double,
             appResponse: HTTPURLResponse,
             responseCompletionHandler: (@Sendable (Data?, URLResponse?, Error?) async -> Void)?) {
            self.mteHelper = mteHelper
            self.pairId = pairId
            self.fileHandle = fileHandle
            self.totalDownloadBytes = totalDownloadBytes
            self.appResponse = appResponse
            self.responseCompletionHandler = responseCompletionHandler
        }
        
        func decryptChunk(data: Data) async {
            do {
                index += 1
                let decryptChunkResult = try await mteHelper.decryptChunk(pairId: pairId, bytes: data.bytes)
                print("Decrypted chunk \(index) of \(data.count) bytes at \(getCurrentTimeWithMilliseconds())")
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: decryptChunkResult.decodedBytes)
                relayStreamResponseDelegate?.streamCompletionPercentage(bytesCompleted: Double(data.bytes.count), totalBytes: totalDownloadBytes)
            } catch {
                await responseCompletionHandler!(nil, nil, error.localizedDescription)
            }
        }
        
        func finishDecrypt() async {
            do {
                print("Finished download and ready for finishDecrypt at \(getCurrentTimeWithMilliseconds())")
                let finishDecryptResult = try await self.mteHelper.finishDecrypt(pairId: self.pairId)
                
                // Append whatever we got from the finishDecrypt call to the file
                try self.fileHandle.seekToEnd()
                try self.fileHandle.write(contentsOf: finishDecryptResult.decodedBytes)
                try self.fileHandle.close()
                await responseCompletionHandler!(nil, appResponse, nil)
            } catch {
                self.relayStreamResponseDelegate?.response(success: false, responseStr: "", errorMessage: "Download File Exception. Error \(error.localizedDescription)")
            }
        }
        
        
        func getCurrentTimeWithMilliseconds() -> String {
            let currentDate = Date()
            
            // Create a date formatter
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS" // Set the format to include milliseconds
            
            // Convert date to string
            let currentTimeString = dateFormatter.string(from: currentDate)
            
            return currentTimeString
        }
    }
}
