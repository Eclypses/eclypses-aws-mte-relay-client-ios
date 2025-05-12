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

class FileStreamDownload: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    // MARK: init
    init(hostUrl: String, mteHelper: MteHelper, downloadId: UUID) {
        self.downloadId = downloadId
        self.hostUrl = hostUrl
        self.mteHelper = mteHelper
    }
    
    deinit {
        logger.info("Destroying RelayFileStreamDownload class\n")
    }
    
    // MARK: Class variables
    private let logger = PackageLogger.makeLogger(for: FileStreamDownload.self)
    weak var fileDownloadResultDelegate: FileDownloadResultDelegate?
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    var hostUrl: String!
    var mteHelper: MteHelper!
    var downloadedFilename: String = ""
    var newFileHandle: FileHandle!
    var storedFileUrl: URL!
    var appResponse: HTTPURLResponse!
    var responsePairId: String!
    var downloadedBytesSoFar: Int = 0
    var contentLength = Double(0)
    var downloadId: UUID!
    
    var startTime: Date!
    var endTime: Date!

    
    private var session: URLSession?
    private var didCleanup = false
    
    // MARK: Public functions
    
    func downloadStream(request: URLRequest, downloadUrl: URL) {
        self.storedFileUrl = downloadUrl
        self.downloadedFilename = storedFileUrl.lastPathComponent
        do {
            newFileHandle = try FileHandle(forWritingTo: storedFileUrl)
            
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            session = URLSession(configuration: configuration,
                                 delegate: self, delegateQueue: nil)
            
            session?.dataTask(with: request).resume()
        } catch {
            reportAndCleanup(response: nil, error: "Unable to create fileHandle for downloaded file. Error: \(error.localizedDescription)")
        }
    }
    
    
    // MARK: delegate methods
    
    // Called when download starts to confirm mime type and response code
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        startTime = Date()
        Task {
            guard let relayResponse = response as? HTTPURLResponse else {
                reportAndCleanup(response: nil, error: "Unable to retrieve download response.")
                return
            }
            if (200...299).contains(relayResponse.statusCode),
               let mimeType = response.mimeType,
               mimeType == "application/octet-stream" {
                do {
                    if let contentLengthStr = relayResponse.value(forHTTPHeaderField: "Content-Length"),
                       let contentLength = Double(contentLengthStr) {
                        self.contentLength = contentLength
                    }
                    
                    // Process Response Headers, including decrypting as necessary
                    let processResponseHeadersResult = try processResponseHeaders(relayResponse: relayResponse,
                                                                            mteHelper: mteHelper)
                    
                    // pairId from decrypting headers is needed outside this callback
                    responsePairId = processResponseHeadersResult.pairId
                    logger.info("\("Using pairId: \(responsePairId!) to decrypt download Response")")
                    
                    appResponse = HTTPURLResponse(url: relayResponse.url!,
                                                  statusCode: relayResponse.statusCode,
                                                  httpVersion: nil,
                                                  headerFields: processResponseHeadersResult.mergedHeaders)
                    _ = try mteHelper.startDecrypt(pairId: responsePairId)
                    completionHandler(.allow)
                } catch {
                    completionHandler(.cancel)
                    reportAndCleanup(response: nil, error: "Unable to download \(downloadedFilename). Error: \(error.localizedDescription)")
                    return
                }
            } else {
                // Check for rePair / reSend possibility
                completionHandler(.cancel)
                reportAndCleanup(response: relayResponse, error: "ResponseCode: \(relayResponse.statusCode)")
                return
            }
        }
    }
    
    // Called periodically throughout download stream
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            let decryptChunkResult = try self.mteHelper.decryptChunk(pairId: self.responsePairId, bytes: data.bytes)
            downloadedBytesSoFar += decryptChunkResult.decodedBytes.count
            relayStreamCompletionDelegate?.streamCompletionPercentage(from: hostUrl, bytesCompleted: Double(downloadedBytesSoFar), totalBytes: contentLength)
            try self.newFileHandle.write(contentsOf: decryptChunkResult.decodedBytes)
        } catch {
            reportAndCleanup(response: nil, error: "Unable to download \(downloadedFilename). Error: \(error.localizedDescription)")
        }
    }
    
    // Called when download is complete
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            reportAndCleanup(response: nil, error: "Download \(downloadedFilename) response error. Error: \(error.localizedDescription)")
        } else {
            do {
                let finishDecryptResult = try self.mteHelper.finishDecrypt(pairId: self.responsePairId)
                self.relayStreamCompletionDelegate = nil
                
                // Append whatever we got from the finishDecrypt call to the file
                try self.newFileHandle.seekToEnd()
                try self.newFileHandle.write(contentsOf: finishDecryptResult.decodedBytes)
                downloadedBytesSoFar += finishDecryptResult.decodedBytes.count
                try self.newFileHandle.close()

                let ending = Date()
                let duration = ending.timeIntervalSince(self.startTime)
                logger.info("\(self.downloadedFilename) of \(self.downloadedBytesSoFar) bytes has been has been downloaded and decrypted successfully in \(String(format: "%.3f", duration * 1000)) milliseconds!")

                reportAndCleanup(response: self.appResponse, error: nil)
            } catch {
                reportAndCleanup(response: nil, error: "Unable to finishDecrypt. Error: \(error.localizedDescription)")
            }
        }
        
    }
    
    func reportAndCleanup(response: URLResponse?, error: Error?) {
        guard !didCleanup else { return }
        didCleanup = true
        
        if error != nil {
            logger.error("\(error?.localizedDescription ?? "Unknown error")")
            if let fileHandle = try? FileHandle(forWritingTo: storedFileUrl) {
                try? fileHandle.truncate(atOffset: 0)
                try? fileHandle.close()
            }
        }
        
        fileDownloadResultDelegate?.fileDownloadResult(storedFileUrl: storedFileUrl, response: response, error: error, downloadId: downloadId)
        
        if responsePairId != nil {
            mteHelper?.releasePair(pairId: responsePairId)
        }

        session?.finishTasksAndInvalidate()
        session = nil
        
        try? newFileHandle?.close()
        newFileHandle = nil
        storedFileUrl = nil
        appResponse = nil
        responsePairId = nil
        relayStreamCompletionDelegate = nil
        fileDownloadResultDelegate = nil
        mteHelper = nil
    }
    
}
