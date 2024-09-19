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
    var downloadedFilename: String = ""
    var newFileHandle: FileHandle!
    var storedFileUrl: URL!
    var appResponse: HTTPURLResponse!
    var responsePairId: String!
    var totalDownloadBytes: Int = 0
    
    var startTime: Date!
    var endTime: Date!
    
    
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
        print("\n\nStarting download of \(downloadedFilename)")
        startTime = Date()
        Task {
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
                
                appResponse = HTTPURLResponse(url: relayResponse.url!,
                                              statusCode: relayResponse.statusCode,
                                              httpVersion: nil,
                                              headerFields: mergedHeaders)
                _ = try mteHelper.startDecrypt(pairId: responsePairId)
                completionHandler(.allow)
            } catch {
                completionHandler(.cancel)
                await responseCompletionHandler!(nil, nil, error.localizedDescription)
                return
            }
        }
    }
    
    var index2 = 0
    
    // Called periodically throughout download stream
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            let decryptChunkResult = try self.mteHelper.decryptChunk(pairId: self.responsePairId, bytes: data.bytes)
            totalDownloadBytes += decryptChunkResult.decodedBytes.count
            // Write the decrypted chunk to the new file
            try self.newFileHandle.write(contentsOf: decryptChunkResult.decodedBytes)
        } catch {
            print("Unable to write encrypted bytes to file. Error: \(error.localizedDescription)")
        }
    }
    
    // Called when download is complete
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        if let error = error {
            Task {
                await self.responseCompletionHandler!(nil, nil, error.localizedDescription)
            }
        } else {
            do {
                let finishDecryptResult = try self.mteHelper.finishDecrypt(pairId: self.responsePairId)
                
                // Append whatever we got from the finishDecrypt call to the file
                try self.newFileHandle.seekToEnd()
                try self.newFileHandle.write(contentsOf: finishDecryptResult.decodedBytes)
                totalDownloadBytes += finishDecryptResult.decodedBytes.count
                try self.newFileHandle.close()
#if DEBUG
                let ending = Date()
                let duration = ending.timeIntervalSince(self.startTime)
                print("SUCCESS! \(downloadedFilename) of \(totalDownloadBytes) bytes has been has been downloaded and decrypted successfully in \(String(format: "%.3f", duration * 1000)) milliseconds!")
#endif
                Task {
                    await self.responseCompletionHandler!(nil, self.appResponse, nil)
                }
            } catch {
                Task {
                    await responseCompletionHandler!(nil, nil, error.localizedDescription)
                }
            }
        }
    }
    
#if DEBUG
    func getCurrentTimeWithMilliseconds() -> String {
        let currentDate = Date()
        
        // Create a date formatter
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS" // Set the format to include milliseconds
        
        // Convert date to string
        let currentTimeString = dateFormatter.string(from: currentDate)
        
        return currentTimeString
    }
#endif
    
}
