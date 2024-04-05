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
    }
    
    func createEncoderAndDecoder() throws {
        try instantiateEncoder()
        try instantiateDecoder()
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
    
    // MARK: Encode
    func encode(plaintext: String) throws -> String {
        try restoreEncoderState()
        let encodeResult = encoder.encodeB64(plaintext)
        encoderState = encoder.saveState()
        try checkMteStatus(function: #function, status: encodeResult.status)
        return encodeResult.encoded
    }
    
    func encode(bytes: [UInt8]) throws -> [UInt8] {
        try restoreEncoderState()
        let encodeResult = encoder.encode(bytes)
        encoderState = encoder.saveState()
        try checkMteStatus(function: #function, status: encodeResult.status)
        return Array(encodeResult.encoded)
    }
    
    // MARK: Encoder Stream Chunking
    func startEncrypt() throws {
        try restoreEncoderState()
        let status = encoder.startEncrypt()
        try checkMteStatus(function: #function, status: status)
        // Do not save state until chunking operation is complete!
    }
    
    func encryptChunk(buffer: inout [UInt8]) throws {
        let status = encoder.encryptChunk(&buffer)
        try checkMteStatus(function: #function, status: status)
    }
    
    func finishEncrypt() throws -> [UInt8] {
        let encryptFinishResult = encoder.finishEncrypt()
        try checkMteStatus(function: #function, status: encryptFinishResult.status)
        encoderState = encoder.saveState()
        return Array(encryptFinishResult.encoded)
    }
    
    // MARK: Decode
    func decode(encoded: String) throws -> String {
        try restoreDecoderState()
        let decodeResult = decoder.decodeStrB64(encoded)
        decoderState = decoder.saveState()
        try checkMteStatus(function: #function, status: decodeResult.status)
        return decodeResult.str
    }
    
    func decode(encoded: [UInt8]) throws -> [UInt8] {
        try restoreDecoderState()
        let decodeResult = decoder.decode(encoded)
        decoderState = decoder.saveState()
        try checkMteStatus(function: #function, status: decodeResult.status)
        return Array(decodeResult.decoded)
    }
    
    // MARK: Decoder Stream Chunking
    func startDecrypt() throws {
        try restoreDecoderState()
        let status = decoder.startDecrypt()
        try checkMteStatus(function: #function, status: status)
        // Do not save state until chunking operation is complete!
    }
    
    func decryptChunk(buffer: [UInt8]) throws -> [UInt8] {
        let decodeResult: (data: ArraySlice<UInt8>, status: mte_status) = decoder.decryptChunk(buffer)
        try checkMteStatus(function: #function, status: decodeResult.status)
        return Array(decodeResult.data)
    }
    
    func finishDecrypt() throws -> [UInt8] {
        let decryptFinishResult: (data: ArraySlice<UInt8>, status: mte_status) = decoder.finishDecrypt()
        try checkMteStatus(function: #function, status: decryptFinishResult.status)
        decoderState = decoder.saveState()
        return Array(decryptFinishResult.data)
    }
    
    func getFinishEncryptBytes() -> Int {
        return encoder.encryptFinishBytes()
    }
    
    // MARK: State Functions
    func restoreEncoderState() throws {
        let status = encoder.restoreState(encoderState)
        try checkMteStatus(function: #function, status: status)
    }
    
    func restoreDecoderState() throws {
        let status = decoder.restoreState(decoderState)
        try checkMteStatus(function: #function, status: status)
    }
    
    func getEncoderState(state: inout [UInt8]) {
        state = encoderState
    }
    
    func getDecoderState(state: inout [UInt8]) {
        state = decoderState
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
