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

class PairingHelper {
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PairingHelper.self)
    )
    
    static let keychainService = "key"
    
    static func pairWithHost(hostUrl: String, mteHelper: MteHelper) throws -> Task<Bool, Error> {
        Task.init {
            try await makeHeadRequest(hostUrl: hostUrl)
            try await pair(hostUrl: hostUrl, mteHelper: mteHelper)
            return true
        }
    }
    
    //MARK: Make HEAD Request
    static func makeHeadRequest(hostUrl: String) async throws {
        let connectionModel = RelayInternalConnectionModel(url: hostUrl,
                                                   method: "HEAD",
                                                   route: "api/mte-relay",
                                                   payload: Data("".utf8),
                                                   contentType: "application/json; charset=utf-8",
                                                   relayHeaders: RelayHeaders())
        
        // Make HEAD request to get ClientId from a valid Relay Server
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
        case .failure(let code, let message):
            throw "HEAD Request returned failure. Error Code: \(code). Error Message: \(message)"
        case .success(_, let headers):
            RelaySettings.clientId = headers.clientId
        }
    }
    
    private static func pair(hostUrl: String, mteHelper: MteHelper) async throws {
        let pairDictionary = try mteHelper.createPairDictionary(count: RelaySettings.pairPoolSize)
        var pairingRequestArray = [PairingRequest]()
        for pair in pairDictionary {
            let pairKeys = PairingRequest(
                pairId: pair.key,
                encoderPublicKey: bytesToB64Str(publicKey: &pair.value.encMyPublicKey),
                encoderPersonalizationStr: pair.value.encPersStr,
                decoderPublicKey: bytesToB64Str(publicKey: &pair.value.decMyPublicKey),
                decoderPersonalizationStr: pair.value.decPersStr)
            pairingRequestArray.append(pairKeys)
        }
        let payload = try JSONEncoder().encode(pairingRequestArray)
        let connectionModel = RelayInternalConnectionModel(url: hostUrl,
                                                   method: "POST",
                                                   route: "api/mte-pair",
                                                   payload: payload,
                                                   contentType: "application/json; charset=utf-8",
                                                   relayHeaders: RelayHeaders())
        // Make pairing call
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
        case .failure(let code, let message):
            throw "Pairing Request returned failure. Error Code: \(code). Error Message: \(message)"
        case .success(let data, let relayHeaders):
            RelaySettings.clientId = relayHeaders.clientId
            do {
                let response = try JSONDecoder().decode([PairingResponse].self, from: data)
                for p in response {
                    guard let pair = pairDictionary[p.pairId] else {
                        print("Pair not found")
                        return
                    }
                    pair.encPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.decoderSecret)
                    pair.encNonce = UInt64(p.decoderNonce)!
                    pair.decPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.encoderSecret)
                    pair.decNonce = UInt64(p.encoderNonce)!
                    try pair.createEncoderAndDecoder()
                }
            } catch {
                throw "Pairing Request Error: \(error.localizedDescription)"
            }
        }
    }
    
    private static func bytesToB64Str(publicKey: inout [UInt8]) -> String {
        return Data(publicKey).base64EncodedString()
    }
    
    private static func b64StrToBytes(publicKeyStr: String) -> [UInt8] {
        guard let pkData = Data(base64Encoded: publicKeyStr) else {
            print("Unable to convert public key to Data")
            return [UInt8]()
        }
        return [UInt8](pkData)
    }
    
    static let pairingOptions = RelayOptions(clientId: RelaySettings.clientId,
                                   pairId: "",
                                   encodeType: EncoderType.MKE.rawValue,
                                   urlIsEncoded: true,
                                   headersAreEncoded: true,
                                   bodyIsEncoded: true)
    
    // MARK: Network Call
    static func call(connectionModel: RelayInternalConnectionModel) async -> RelayApiResult<Data> {
        let url = URL(string: String(format: "%@%@", connectionModel.url, connectionModel.route))
        var request = URLRequest(url: url!)
        request.httpMethod = connectionModel.method
        request.httpBody = connectionModel.payload
        request.setValue(connectionModel.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue(formatMteRelayHeader(options: pairingOptions), forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue)
        return await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    continuation.resume(returning: RelayApiResult.failure(code: MteConstants.RC_ERROR_ESTABLISHING_CONNECTION_WITH_SERVER, message: error.localizedDescription))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(returning: RelayApiResult.failure(code: MteConstants.RC_ERROR_ESTABLISHING_CONNECTION_WITH_SERVER, message: "No Response"))
                    return
                }
                let responseMessage = String(data: data!, encoding: String.Encoding.utf8) ?? "No Response Message from the Server"
                let statusCode = httpResponse.statusCode
                if 200...226 ~= statusCode {
                    guard let responseData = data else {
                        continuation.resume(returning: RelayApiResult.failure(code: MteConstants.RC_ERROR_RECEIVED_NO_DATA_FROM_SERVER, message: responseMessage)); return
                    }
                    var responseHeaders = RelayHeaders()
                    guard let mteRelayHeaderStr = httpResponse.value(forHTTPHeaderField: RelayHeaderNames.xMteRelay.rawValue) else {
                        continuation.resume(returning: RelayApiResult.failure(code: String(httpResponse.statusCode), message: "No '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response"))
                        return
                    }
                    guard let relayOptions = parseMteRelayHeader(header: mteRelayHeaderStr) else {
                        continuation.resume(returning: RelayApiResult.failure(code: String(httpResponse.statusCode), message: "Unable to parse '\(RelayHeaderNames.xMteRelay.rawValue)' header in Response"))
                        return
                    }
                    responseHeaders.clientId = relayOptions.clientId
                    if connectionModel.route != "api/mte-relay" && connectionModel.route != "api/mte-pair" {
                        responseHeaders.pairId = relayOptions.pairId
                    }
                    continuation.resume(returning: RelayApiResult.success(data: responseData, headers: responseHeaders)); return
                } else {
                    continuation.resume(returning: RelayApiResult.failure(code: String(statusCode), message: responseMessage)); return
                }
            }.resume()
        }
    }
}
