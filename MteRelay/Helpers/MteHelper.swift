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
import Mte
import Core
import MKE
import os

class MteHelper {

    private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!,
            category: String(describing: MteHelper.self)
        )
    
    var pairDictionary: [String: Pair]!
    var nextPair: Int = 0
    
    func refillPairDictionary(storedHost: StoredHost) throws {
        pairDictionary = [:]
        for storedPair in storedHost.storedPairs {
            let encState = storedPair.encState
            let decState = storedPair.decState
            let pair = try Pair(
                pairId: storedPair.pairId,
                encoderState: encState,
                decoderState: decState)
            pairDictionary[pair.pairId] = pair
        }
    }
    
    func createPairDictionary(count: Int) throws -> [String: Pair] {
        pairDictionary = [:]
        for _ in (0..<count) {
            let pair = try Pair()
            pairDictionary[pair.pairId] = pair
        }
        return pairDictionary
    }

    // MARK: Encode
    func encode(pairId: String?, plaintext: String) throws -> EncodeResult {
        let (pair, encodeResult) = try resolveEncodePair(pairId: pairId)
        encodeResult.encodedStr = try pair.encode(plaintext: plaintext)
        return encodeResult
    }
    
    func encode(pairId: String?, bytes: [UInt8]) throws -> EncodeResult {
        let (pair, encodeResult) = try resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try pair.encode(bytes: bytes)
        return encodeResult
    }
    
    // MARK: Encode Stream Chunking
    func startEncrypt(pairId: String?) throws -> EncodeResult {
        let (pair, encodeResult) = try resolveEncodePair(pairId: pairId)
        try pair.startEncrypt()
        return encodeResult
    }
    
    func encryptChunk(pairId: String, buffer: inout [UInt8]) throws -> EncodeResult {
        let (pair, encodeResult) = try resolveEncodePair(pairId: pairId)
        try pair.encryptChunk(buffer: &buffer)
        return encodeResult
    }
    
    func finishEncrypt(pairId: String) throws -> EncodeResult {
        let (pair, encodeResult) = try resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try pair.finishEncrypt()
        return encodeResult
    }
    
    
   // MARK: Decode
    func decode(pairId: String, encoded: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedStr = try pair.decode(encoded: encoded)
        return decodeResult
    }
    
    func decode(pairId: String, encoded: [UInt8]) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try pair.decode(encoded: encoded)
        return decodeResult
    }
    
    
    // MARK: Decode Stream Chunking
    func startDecrypt(pairId: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        try pair.startDecrypt()
        return decodeResult
    }
    
    func decryptChunk(pairId: String, bytes: [UInt8]) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try pair.decryptChunk(buffer: bytes)
        return decodeResult
    }
    
    func finishDecrypt(pairId: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try pair.finishDecrypt()
        return decodeResult
    }
    
    private func getNextPair() -> Pair {
        // TODO: Deal better with empty pair dictionary
        if pairDictionary == nil {
            print("Unable to select Next Pair")
        }
        let pairIdArray = [String](pairDictionary.keys)
        let nextPairId = pairIdArray[nextPair]
        // Advance nextPair
        if nextPair == pairIdArray.count - 1 {
            nextPair = 0
        } else {
            nextPair += 1
        }
        return pairDictionary[nextPairId]!
    }
    
    private func resolveEncodePair(pairId: String?) throws -> (Pair, EncodeResult) {
        let encodeResult = EncodeResult()
        var pair: Pair!
        if pairId != nil {
            pair = pairDictionary[pairId!]
            if pair == nil {
                throw "Pair \(pairId!) not found. Unable to continue."
            }
        } else {
            pair = getNextPair()
        }
        encodeResult.pairId = pair.pairId
        return (pair, encodeResult)
    }
    
    private func resolveDecodePair(pairId: String) throws -> (Pair, DecodeResult) {
        let decodeResult = DecodeResult()
        guard let pair = pairDictionary[pairId] else {
            throw "Pair \(pairId) not found. Unable to continue."
        }
        decodeResult.pairId = pair.pairId
        return (pair, decodeResult)
    }
    
    func getPairDictionaryStates() throws -> [StoredPair] {
        var pairsToStore = [StoredPair]()
        for pair in pairDictionary {
            var pairToStore = StoredPair()
            pairToStore.pairId = pair.value.pairId
            pair.value.getEncoderState(state: &pairToStore.encState)
            pair.value.getDecoderState(state: &pairToStore.decState)
            pairsToStore.append(pairToStore)
        }
        return pairsToStore
    }
    
    func encryptHeaders(pairId: String, allHeaders: inout Dictionary<String, String>, headersToEncrypt: [String]?) throws -> EncodeResult {
        var headers = [String:String]()
        // Transfer original headers to new request unless they need to be encrypted
        // The Content-Type header always gets encrypted
        for header in allHeaders {
            if header.key == "Content-Type" {
                headers[header.key] = header.value
                allHeaders.removeValue(forKey: header.key)
                continue
            }
            // Encrypt any headers named in the "headersToEncrypt" parameter
            if headersToEncrypt != nil {
                if headersToEncrypt!.contains(header.key) {
                    headers[header.key] = header.value
                    allHeaders.removeValue(forKey: header.key)
                    continue
                }
            }
        }

        // Then, create a json string of header key/value pairs to encrypt ...
        let headersJsonData = try JSONEncoder().encode(headers)
       
        // Encode the headersJson
        return try encode(pairId: pairId, plaintext: String(decoding: headersJsonData, as: UTF8.self))

    }
    
    func getFinishEncryptBytes(pairId: String) -> Int {
        let pair = pairDictionary[pairId]
        return pair!.getFinishEncryptBytes()
    }

}


