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
import Mte
import Core
import MKE

actor PairActor {
    
    var encoder: MteMkeEnc!
    var decoder: MteMkeDec!
    var encoderState: [UInt8]!
    var decoderState: [UInt8]!
    
    
    // Initializer for Stored States
    init(enc: MteMkeEnc, encState: [UInt8], dec: MteMkeDec, decState: [UInt8]) throws {
        self.encoder = enc
        encoderState = encState
        self.decoder = dec
        decoderState = decState
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
        let finishEncryptResult = encoder.finishEncrypt()
        try checkMteStatus(function: #function, status: finishEncryptResult.status)
        encoderState = encoder.saveState()
        return Array(finishEncryptResult.encoded)
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
    
    func checkMteStatus(function: String, status: mte_status) throws {
        if status != mte_status_success {
            throw "Status: \(MteBase.getStatusName(status)). Description: \(MteBase.getStatusDescription(status))"
        }
    }
}
