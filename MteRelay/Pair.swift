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
import Kyber
import Mte
import Core
import MKE

class Pair : MteEntropyCallback, MteNonceCallback {
    
    var pairActor: PairActor!
    let pairId: String!
    var encPersStr: String!
    var decPersStr: String!
    var encKyber: MteKyber!
    var decKyber: MteKyber!
    var encMyPublicKey: [UInt8]!
    var encPeerEncryptedSecret: [UInt8]!
    var decMyPublicKey: [UInt8]!
    var decPeerEncryptedSecret: [UInt8]!
    var encNonce: UInt64!
    var decNonce: UInt64!
    var encoder: MteMkeEnc!
    var decoder: MteMkeDec!
    var encoderState: [UInt8]!
    var decoderState: [UInt8]!
    var pairType: Int!
    
    // MARK: Initializer for no stored states
    init() throws {
        pairId = getRandomString(length: 32)
        encPersStr = getRandomString(length: 32)
        decPersStr = getRandomString(length: 32)
        
        encKyber = try MteKyber(strength: KyberStrength.K512)
        let enckeyResult = encKyber.createKeyPair()
        try checkKyberStatus(status: enckeyResult.status)
        encMyPublicKey = enckeyResult.publicKey
        
        decKyber = try MteKyber(strength: KyberStrength.K512)
        let deckeyResult = decKyber.createKeyPair()
        try checkKyberStatus(status: deckeyResult.status)
        decMyPublicKey = deckeyResult.publicKey
        
    }
    
    // MARK: Initializer for stored states
    init(pairId: String, encoderState: [UInt8], decoderState: [UInt8]) throws {
        self.pairId = pairId
        self.encoder = try MteMkeEnc()
        self.encoderState = encoderState
        self.decoder = try MteMkeDec()
        self.decoderState = decoderState
        try instantiatePairHelper()
    }
    
    func createEncoderAndDecoder() throws {
        try instantiateEncoder()
        try instantiateDecoder()
        try instantiatePairHelper()
    }
    
    func instantiateEncoder() throws {
        encoder = try MteMkeEnc()
        pairType = 0
        encoder.setEntropyCallback(self)
        encoder.setNonceCallback(self)
        let status = encoder.instantiate(encPersStr)
        try checkMteStatus(function: #function, status: status)
        // Uncomment to confirm encoder state value and and compare with Server decoder state. This is a particularly useful debugging tool.
        //        debugPrint("Pair \(pairId!) EncoderState: \(encoder.saveStateB64()!)")
        encoderState = encoder.saveState()
    }
    
    func instantiateDecoder() throws {
        decoder = try MteMkeDec()
        pairType = 1
        decoder.setEntropyCallback(self)
        decoder.setNonceCallback(self)
        let status = decoder.instantiate(decPersStr)
        try checkMteStatus(function: #function, status: status)
        // Uncomment to confirm decoder state value and and compare with Server encoder state. This is a particularly useful debugging tool.
        //        debugPrint("Pair \(pairId!) DecoderState: \(decoder.saveStateB64()!)")
        decoderState = decoder.saveState()
    }
    
    func instantiatePairHelper() throws {
        pairActor = try PairActor(enc: encoder, encState: encoderState, dec: decoder, decState: decoderState)
    }
    
    // MARK: Encode
    
    func encode(plaintext: String) async throws -> String {
        return try await pairActor.encode(plaintext: plaintext)
    }
    
    func encode(bytes: [UInt8]) async throws -> [UInt8] {
        return try await pairActor.encode(bytes: bytes)
    }
    
    // MARK: Encoder Stream Chunking
    
    func startEncrypt() async throws {
        try await pairActor.startEncrypt()
    }
    
    func encryptChunk(buffer: inout [UInt8]) async throws {
        try await pairActor.encryptChunk(buffer: &buffer)
    }
    
    func finishEncrypt() async throws -> [UInt8] {
        return try await pairActor.finishEncrypt()
    }
    
    // MARK: Decode
    
    func decode(encoded: String) async throws -> String {
        return try await pairActor.decode(encoded: encoded)
    }
    
    func decode(encoded: [UInt8]) async throws -> [UInt8] {
        return try await pairActor.decode(encoded: encoded)
    }

    // MARK: Decoder Stream Chunking
    func startDecrypt() async throws {
        _ = try await pairActor.startDecrypt()
    }
    
    func decryptChunk(buffer: [UInt8]) async throws -> [UInt8] {
        return try await pairActor.decryptChunk(buffer: buffer)
    }
    
    func finishDecrypt() async throws -> [UInt8] {
        return try await pairActor.finishDecrypt()
    }
    
    func getFinishEncryptBytes() -> Int {
        return encoder.encryptFinishBytes()
    }
    
    // MARK: State Functions
    
    func getEncoderState(state: inout [UInt8]) async {
        await pairActor.getEncoderState(state: &state)
    }
    
    func getDecoderState(state: inout [UInt8]) async {
        await pairActor.getDecoderState(state: &state)
    }
    
    // MARK: Status Functions
    
    func checkKyberStatus(status: Int32) throws {
        if KyberResultCode(status).intValue != KyberResultCode.success.intValue {
            throw KyberResultCode(status).stringValue
        }
    }
    
    func checkMteStatus(function: String, status: mte_status) throws {
        if status != mte_status_success {
            throw "Status: \(MteBase.getStatusName(status)). Description: \(MteBase.getStatusDescription(status))"
        }
    }
    
    func entropyCallback(_ minEntropy: Int,
                         _ minLength: Int,
                         _ maxLength: UInt64,
                         _ entropyInput: inout [UInt8],
                         _ eiBytes: inout UInt64,
                         _ entropyLong: inout UnsafeMutableRawPointer?) -> mte_status {
        do {
            switch pairType {
            case 1:
                var decDecryptSecretResult = decKyber.decryptSecret(encryptedSecret: &decPeerEncryptedSecret)
                try checkKyberStatus(status: decDecryptSecretResult.status)
                if decDecryptSecretResult.secret.count < minLength || decDecryptSecretResult.secret.count > maxLength {
                    throw "mte_status_drbg_catastrophic"
                }
                entropyInput = decDecryptSecretResult.secret
                decDecryptSecretResult.secret.resetBytes(in: 0..<decDecryptSecretResult.secret.count)
            default:
                var encDecryptSecretResult = encKyber.decryptSecret(encryptedSecret: &encPeerEncryptedSecret)
                try checkKyberStatus(status: encDecryptSecretResult.status)
                if encDecryptSecretResult.secret.count < minLength || encDecryptSecretResult.secret.count > maxLength {
                    throw "mte_status_drbg_catastrophic"
                }
                entropyInput = encDecryptSecretResult.secret
                encDecryptSecretResult.secret.resetBytes(in: 0..<encDecryptSecretResult.secret.count)
            }
            return mte_status_success
        } catch {
            return mte_status_drbg_catastrophic
        }
    }
    
    func nonceCallback(_ minLength: Int, _ maxLength: Int, _ nonce: inout [UInt8], _ nBytes: inout Int) {
        var nCopied: Int = 0
        switch pairType {
        case 1:
            nCopied = min(nonce.count, MemoryLayout.size(ofValue: decNonce))
            for i in 0..<nCopied {
                nonce[i] = UInt8(UInt64(decNonce >> (i * 8)) & 0xFF)
            }
            decNonce = 0
        default:
            nCopied = min(nonce.count, MemoryLayout.size(ofValue: encNonce))
            for i in 0..<nCopied {
                nonce[i] = UInt8(UInt64(encNonce >> (i * 8)) & 0xFF)
            }
            encNonce = 0
        }
        if nCopied < minLength {
            for i in nCopied..<minLength {
                nonce[i] = 0
            }
            nBytes = minLength
        }
        else {
            nBytes = nCopied
        }
    }
}
