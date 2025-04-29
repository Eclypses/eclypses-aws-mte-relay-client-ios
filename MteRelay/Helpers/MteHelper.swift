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
    
    private let logger = PackageLogger.makeLogger(for: MteHelper.self)
    
    private var pairPool = PairPool(maxCount: Settings.pairPoolSize)
    
    weak var delegate: MteHelperDelegate?
    
    func refillPairDictionary(storedHost: StoredHost) throws {
        logger.info("Refilling pair dictionary from stored states")
        var pairs = [String: Pair]()
        for storedPair in storedHost.storedPairs {
            let encState = storedPair.encState
            let decState = storedPair.decState
            let pair = try Pair(
                pairId: storedPair.pairId,
                encoderState: encState,
                decoderState: decState)
            pairs[pair.pairId] = pair
        }
        pairPool.refill(with: pairs)
    }
    
    func createPairDictionary(count: Int) throws -> [String: Pair] {
        logger.info("Creating new pair dictionary")
        try pairPool.createNew(count: count)
        return pairPool.allPairs()
    }
    
    func registerNewPairedPair(_ pair: Pair) {
        pairPool.insertIntoInUse(pair)
    }
    
    // MARK: Encode Functions
    
    func encode(pairId: String?, plaintext: String) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedStr = try pair.encode(plaintext: plaintext)
        return encodeResult
    }
    
    func encode(pairId: String?, bytes: [UInt8]) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try pair.encode(bytes: bytes)
        return encodeResult
    }
    
    // MARK: Encode Stream Chunking Functions
    
    func startEncrypt(pairId: String?) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        try pair.startEncrypt()
        return encodeResult
    }
    
    func encryptChunk(pairId: String, buffer: inout [UInt8]) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        try pair.encryptChunk(buffer: &buffer)
        return encodeResult
    }
    
    func finishEncrypt(pairId: String) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try pair.finishEncrypt()
        return encodeResult
    }
    
    
    // MARK: Decode Functions
    
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
    
    
    // MARK: Decode Stream Chunking Functions
    
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
    
    // MARK: Public Cleanup Function
    
    func releasePair(pairId: String) {
        pairPool.moveToAvailable(pairId: pairId)
    }
    
    // MARK: private Functions
    
    private func getNextPair() async throws -> Pair {
        let (pair, isNew) = try pairPool.getNextAvailablePair()
        if isNew {
            logger.info("Requesting pairing for new pair \(String(describing: pair.pairId))")
            try await delegate?.pairingNeeded(for: pair)
        }
        return pair
    }
    
    private func resolveEncodePair(pairId: String?) async throws -> (Pair, EncodeResult) {
        let encodeResult = EncodeResult()
        var pair: Pair!
        if let id = pairId {
            guard let resolved = pairPool.pair(for: id) else {
                let errorMessage = "Pair \(id) not found. Unable to continue."
                logger.fault("\(errorMessage)")
                throw errorMessage
            }
            pair = resolved
        } else {
            pair = try await getNextPair()
        }
        encodeResult.pairId = pair.pairId
        return (pair, encodeResult)
    }
    
    private func resolveDecodePair(pairId: String) throws -> (Pair, DecodeResult) {
        let decodeResult = DecodeResult()
        guard let pair = pairPool.pair(for: pairId) else {
            let errorMessage = "Pair \(pairId) not found. Unable to continue."
            logger.fault("\(errorMessage)")
            throw errorMessage
        }
        decodeResult.pairId = pair.pairId
        return (pair, decodeResult)
    }
    
    // MARK: Utility Functions
    
    func getPairDictionaryStates() async throws -> [StoredPair] {
        var pairsToStore = [StoredPair]()
        for pair in pairPool.allPairs() {
            var pairToStore = StoredPair()
            pairToStore.pairId = pair.value.pairId
            pair.value.getEncoderState(state: &pairToStore.encState)
            pair.value.getDecoderState(state: &pairToStore.decState)
            pairsToStore.append(pairToStore)
        }
        return pairsToStore
    }
    
    func getFinishEncryptBytes(pairId: String) -> Int {
        let pair = pairPool.pair(for: pairId)
        return pair?.getFinishEncryptBytes() ?? 0
    }
    
    // MARK: Cleanup Function
    func cleanup() {
        delegate = nil
        pairPool = PairPool(maxCount: Settings.pairPoolSize)
    }

}

