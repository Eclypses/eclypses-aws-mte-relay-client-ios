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
    
    static let keychainService = "key"
    private static let logger = PackageLogger.makeLogger(for: PairingHelper.self)
    
    static func initialPairingWithHost(hostUrl: String, mteHelper: MteHelper) throws -> Task<Bool, Error> {
        Task.init {
            try await makeHeadRequest(hostUrl: hostUrl)
            let pairDictionary = try mteHelper.createPairDictionary(count: Settings.pairPoolSize)
            try await pair(hostUrl: hostUrl, pairDictionary: pairDictionary, mteHelper: mteHelper)
            return true
        }
    }
    
    static func addPair(hostUrl: String, pair: Pair, mteHelper: MteHelper) async throws {
        let pairDictionary: [String: Pair] = [pair.pairId: pair]
        try await PairingHelper.pair(hostUrl: hostUrl, pairDictionary: pairDictionary, mteHelper: mteHelper)
    }
    
    //MARK: Make HEAD Request
    static func makeHeadRequest(hostUrl: String) async throws {
        let connectionModel = InternalConnectionModel(url: hostUrl,
                                                           method: RelayMethod.HEAD,
                                                           route: RelayRoutes.HEAD_REQUEST,
                                                           payload: Data("".utf8),
                                                           contentType: "application/json; charset=utf-8",
                                                           relayHeaders: RelayHeaders())
        
        // Make HEAD request to get ClientId from a valid Relay Server
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
            
        case .failure(let code, let message):
            let errorMessage = "HEAD Request again returned failure. Error Code: \(code). Error Message: \(message)"
            logger.error("\(errorMessage)")
            throw errorMessage

        case .success(_, let headers):
            Settings.clientId = headers.clientId
        }
    }
    
    private static func pair(hostUrl: String, pairDictionary: [String : Pair], mteHelper: MteHelper) async throws {
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
        let connectionModel = InternalConnectionModel(url: hostUrl,
                                                           method:  RelayMethod.POST,
                                                           route: RelayRoutes.PAIRING,
                                                           payload: payload,
                                                           contentType: "application/json; charset=utf-8",
                                                           relayHeaders: RelayHeaders())
        // Make pairing call
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
            
        case .failure(let code, let message):
            let errorMessage = "Pairing Request returned failure. Error Code: \(code). Error Message: \(message)"
            logger.error("\(errorMessage)")
            throw errorMessage
            
        case .success(let data, let relayHeaders):
            logger.info("Pairing request with \(hostUrl) was successful! ClientId is \(relayHeaders.clientId)")
            Settings.clientId = relayHeaders.clientId
            do {
                let response = try JSONDecoder().decode([PairingResponse].self, from: data)
                for p in response {
                    guard let pair = pairDictionary[p.pairId] else {
                        logger.error("Pair not found in Response")
                        return
                    }
                    logger.info("Server returned Pair Id \(pair.pairId!)")
                    pair.encPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.decoderSecret)
                    pair.encNonce = UInt64(p.decoderNonce)!
                    pair.decPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.encoderSecret)
                    pair.decNonce = UInt64(p.encoderNonce)!
                    try pair.createEncoderAndDecoder()
                }
            } catch {
                let errorMessage = "Pairing Request Error: \(error.localizedDescription)"
                logger.error("\(errorMessage)")
                throw errorMessage
            }
        }
    }
    
    private static func bytesToB64Str(publicKey: inout [UInt8]) -> String {
        return Data(publicKey).base64EncodedString()
    }
    
    private static func b64StrToBytes(publicKeyStr: String) -> [UInt8] {
        guard let pkData = Data(base64Encoded: publicKeyStr) else {
            let errorMessage = "Unable to convert public key to Data"
            logger.error("\(errorMessage)")
            return [UInt8]()
        }
        return [UInt8](pkData)
    }
    
    
    // MARK: Network Call
    static func call(connectionModel: InternalConnectionModel) async -> RelayApiResult<Data> {
        let pairingOptions = RelayOptions(clientId: Settings.clientId,
                                                 pairId: "",
                                                 encodeType: EncoderType.MKE.rawValue,
                                                 urlIsEncoded: true,
                                                 headersAreEncoded: true,
                                                 bodyIsEncoded: true)
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
                    if connectionModel.route != RelayRoutes.HEAD_REQUEST && connectionModel.route != RelayRoutes.PAIRING {
                        responseHeaders.pairId = relayOptions.pairId
                    }
                    continuation.resume(returning: RelayApiResult.success(data: responseData, headers: responseHeaders)); return
                } else {
                    continuation.resume(returning: RelayApiResult.failure(code: String(statusCode), message: responseMessage)); return
                }
            }.resume()
        }
    }
    
    static func checkForRePair(statusCode: String) -> Bool {
        if let statusCodeInt = Int(statusCode), statusCodeInt == 566 {
            logger.info("Server doesn't recognize this Client. Re-pairing required")
            Settings.clientId = ""
            return true
        } else if let statusCodeInt = Int(statusCode), 559...569 ~= statusCodeInt {
            logger.info("Server doesn't recognize this Pair. Re-pairing required")
            return true
        } else {
            return false
        }
    }
}
