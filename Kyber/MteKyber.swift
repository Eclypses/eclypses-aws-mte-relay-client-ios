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

// Imports when creating a Swift Package Manager package.
#if MTE_SWIFT_PACKAGE_MANAGER
import Mte
import Core
#endif

public class MteKyber {
    
    // MARK: Class properties
    private var privateKeySize = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private var myPrivateKey: UnsafeMutableRawPointer!    
    private var myEntropyInput: [UInt8]!
    private var myEntropyCb: MteKyberEntropyCallback?
    static var mteKyberStrength = KyberStrength.none
    
    
    // MARK: Class init
    public init(strength: KyberStrength) throws {
        if MteKyber.mteKyberStrength != KyberStrength.none {
            if MteKyber.mteKyberStrength != strength {
                throw KyberResultCode.invalidStrength
            }
        } 
        MteKyber.mteKyberStrength = strength
        if mte_kyber_init(strength.intValue) == KyberResultCode.success.intValue {
            privateKeySize.pointee = mte_kyber_get_privkey_size()
            myPrivateKey = UnsafeMutableRawPointer.allocate(byteCount: Int(mte_kyber_get_privkey_size()),
                                                            alignment: MemoryLayout<UInt8>.alignment)
        }
    }
    
    // MARK: Initiator Functions
    public func createKeyPair() -> (status: Int32, publicKey: [UInt8]) {
        var publicKeySize = mte_kyber_get_pubkey_size()
        var publicKey = [UInt8](repeating: 0, count: publicKeySize)
        let classPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = mte_kyber_create_keypair(myPrivateKey,
                                                  privateKeySize,
                                                  &publicKey,
                                                  &publicKeySize,
                                                  MteKyber.entropyCallback,
                                                  classPtr)
        return (status, publicKey)
    }
    
    public func decryptSecret(encryptedSecret: inout [UInt8]) -> (status: Int32, secret: [UInt8]) {
        var decryptedSecretSize = mte_kyber_get_secret_size()
        var decryptedSecret = [UInt8](repeating: 0, count: decryptedSecretSize)
        let status =  mte_kyber_decrypt_secret(myPrivateKey, privateKeySize.pointee,
                                               &encryptedSecret, encryptedSecret.count,
                                               &decryptedSecret, &decryptedSecretSize)
        return (status, decryptedSecret)
    }
    
    // MARK: Responder Functions
    public func createSecret(peerPubKey: [UInt8]) -> (status: Int32, encryptedSecret: [UInt8], secret: [UInt8]) {
        var encryptedSecretSize = mte_kyber_get_encrypted_size()
        var encryptedSecret = [UInt8](repeating: 0, count: encryptedSecretSize)
        var secretSize = mte_kyber_get_secret_size()
        var secret = [UInt8](repeating: 0, count: secretSize)
        
        let classPtr = Unmanaged.passUnretained(self).toOpaque()
        let status =  mte_kyber_create_secret(peerPubKey, peerPubKey.count,
                                              &secret, &secretSize,
                                              &encryptedSecret, &encryptedSecretSize,
                                              MteKyber.entropyCallback, classPtr)
        return (status, encryptedSecret, secret)
    }
    
    // MARK: Both Initiator and Responder Functions
    public func setEntropy(_ entropyInput: [UInt8]) -> Int {
        if entropyInput.count < mte_kyber_get_min_entropy_size() || entropyInput.count > mte_kyber_get_max_entropy_size() {
            return Int(MTE_KYBER_ENTROPY_FAIL)
        }
        myEntropyInput = entropyInput
        return Int(MTE_KYBER_SUCCESS)
    }
    
    public func setEntropyCallback(_ cb: MteKyberEntropyCallback?) {
        myEntropyCb = cb;
    }
    
    // Internal Entropy Callback
    internal func entropyCallback(_ minEntropyBytes: Int,
                                  _ maxEntropyBytes: Int) -> (status: Int32, entropy: [UInt8]?) {
        if myEntropyCb != nil {
            return myEntropyCb!.entropyCallback(minEntropyBytes,
                                                maxEntropyBytes)
        } 
        if myEntropyInput == nil {
            myEntropyInput = [UInt8](repeating: 0, count: minEntropyBytes)
            let status = MteRandom.getBytes(&myEntropyInput)
            if status != errSecSuccess {
                return (MTE_KYBER_ENTROPY_FAIL, nil)
            }
        }
        return (MTE_KYBER_SUCCESS, myEntropyInput)
    }
    
    static let entropyCallback: Optional<@convention(c)
                                            (UnsafeMutableRawPointer?,
                                             UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                             UnsafeMutablePointer<Int>?,
                                             Int,
                                             Int) -> Int32> = {
                                                (context, entropyData, entropySize, minEntropyBytes, maxEntropyBytes) ->
                                                Int32 in
                                                let c = Unmanaged<MteKyber>.fromOpaque(context!).takeUnretainedValue()
                                                let callbackResult = c.entropyCallback(minEntropyBytes, maxEntropyBytes)
                                                guard callbackResult.entropy != nil, callbackResult.status == MTE_KYBER_SUCCESS else {
                                                    return KyberResultCode.entropyFail.intValue
                                                }
                                                if callbackResult.entropy!.count < minEntropyBytes || callbackResult.entropy!.count > maxEntropyBytes {
                                                    return MTE_KYBER_ENTROPY_FAIL
                                                }
                                                entropySize?.pointee = callbackResult.entropy!.count
                                                callbackResult.entropy!.withUnsafeBufferPointer{ buff in
                                                    entropyData!.pointee!.assumingMemoryBound(to: UInt8.self).update(from: buff.baseAddress!,
                                                                                                                     count: callbackResult.entropy!.count)
                                                }
                                                return KyberResultCode.success.intValue
                                            }
    
    public static func zeroize(_ data: inout [UInt8]) {
        for i in 0...data.count - 1 {
            data[i] = 0
        }
    }
    
    public func getPubliceKeySize() -> Int {
        return mte_kyber_get_pubkey_size()
    }
    
    public func getSecretSize() -> Int {
        return mte_kyber_get_secret_size()
    }
    
    public func getEncryptedSize() -> Int {
        return mte_kyber_get_encrypted_size()
    }
    
    public func getMinimumEntropySize() -> Int {
        return mte_kyber_get_min_entropy_size()
    }
    
    public func getMaximumEntropySize() -> Int {
        return mte_kyber_get_max_entropy_size()
    }
    
    public func getAlgorithm() -> String {
        return String(cString: mte_kyber_get_algorithm()!)
    }
    
}

// MARK: Protocol for Entropy Input Callback
public protocol MteKyberEntropyCallback {
    func entropyCallback(_ minEntropyBytes: Int,
                         _ maxEntropyBytes: Int) -> (status: Int32, entropy: [UInt8]?)
}

public enum KyberStrength: UInt16 {
    case none
    case K512
    case K768
    case K1024
    
    var intValue: UInt16 {
        switch self {
        case .none:
            return 0
        case .K512:
            return 512
        case .K768:
            return 768
        case .K1024:
            return 1024
        }
    }
}

public enum KyberResultCode: Error {
    case success
    case invalidStrength
    case entropyFail
    case invalidPubKey
    case invalidPrivKey
    case memoryFail
    case invalidCiphertext
    case custom(String)
    
    public init(_ intValue: Int32) {
        switch intValue {
        case MTE_KYBER_SUCCESS:
            self = .success
        case MTE_KYBER_INVALID_STRENGTH:
            self = .invalidStrength
        case MTE_KYBER_ENTROPY_FAIL:
            self = .entropyFail
        case MTE_KYBER_INVALID_PUBKEY:
            self = .invalidPubKey
        case MTE_KYBER_INVALID_PRIVKEY:
            self = .invalidPrivKey
        case MTE_KYBER_MEMORY_FAIL:
            self = .memoryFail
        case MTE_KYBER_INVALID_CIPHERTEXT:
            self = .invalidCiphertext
        default:
            self = .custom(String(intValue))
            
        }
    }
    
    public var stringValue: String {
        switch self {
        case .success:
            return "Success"
        case .invalidStrength:
            return "InvalidStrength"
        case .entropyFail:
            return "EntropyFail"
        case .invalidPubKey:
            return "InvalidPublicKey"
        case .invalidPrivKey:
            return "InvalidPrivateKey"
        case .memoryFail:
            return "MemoryFail"
        case .invalidCiphertext:
            return "Invalid Ciphertext"
        case .custom(let customString):
            return customString
        }
    }
    
    public var intValue: Int32 {
        switch self {
        case .success:
            return MTE_KYBER_SUCCESS
        case .invalidStrength:
            return MTE_KYBER_INVALID_STRENGTH
        case .entropyFail:
            return MTE_KYBER_ENTROPY_FAIL
        case .invalidPubKey:
            return MTE_KYBER_INVALID_PUBKEY
        case .invalidPrivKey:
            return MTE_KYBER_INVALID_PRIVKEY
        case .memoryFail:
            return MTE_KYBER_MEMORY_FAIL
        case .invalidCiphertext:
            return MTE_KYBER_INVALID_CIPHERTEXT
        case .custom:
            return 9
        }
    }
}
