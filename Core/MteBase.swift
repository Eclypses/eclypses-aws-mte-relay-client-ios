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

// Imports when creating a Swift Package Manager package.
#if MTE_SWIFT_PACKAGE_MANAGER
import Foundation
import Mte
#endif

// Interface of an entropy input callback.
public protocol MteEntropyCallback {
  func entropyCallback(_ minEntropy: Int,
                    _ minLength: Int,
                    _ maxLength: UInt64,
                    _ entropyInput: inout [UInt8],
                    _ eiBytes: inout UInt64,
                    _ entropyLong: inout UnsafeMutableRawPointer?) -> mte_status
}

// Interface of a nonce callback.
public protocol MteNonceCallback {
  func nonceCallback(_ minLength: Int,
                     _ maxLength: Int,
                     _ nonce: inout [UInt8],
                     _ nBytes: inout Int)
}

// Interface of a timestamp callback.
public protocol MteTimestampCallback {
  func timestampCallback() -> UInt64
}

// Class MteBase
//
// This is the base for all MTE classes.
//
// To use, call any of the static helper functions and/or derive from this
// class.
open class MteBase {
  // Returns the MTE version number as a string or individual integer parts.
  public class func getVersion() -> String {
    return String(cString: mte_base_version())
  }
  public class func getVersionMajor() -> Int {
    return Int(mte_wrap_base_version_major())
  }
  public class func getVersionMinor() -> Int {
    return Int(mte_wrap_base_version_minor())
  }
  public class func getVersionPatch() -> Int {
    return Int(mte_wrap_base_version_patch())
  }

  // Initialize with the company name and license code. Returns true if
  // successful or false if not. If true is returned, MTE functions are usable;
  // otherwise functions that return a status will return an error status.
  public class func initLicense(_ company: String, _ license: String) -> Bool {
    return mte_license_init(company, license) != MTE_FALSE
  }

  // Returns the count of status codes.
  public class func getStatusCount() -> Int {
    return Int(mte_wrap_base_status_count())
  }

  // Returns the enumeration name for the given status.
  public class func getStatusName(_ status: mte_status) -> String {
    if let str = mte_wrap_base_status_name(status) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the description for the given status.
  public class func getStatusDescription(_ status: mte_status) -> String {
    if let str = mte_wrap_base_status_description(status) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the status code for the given enumeration name.
  public class func getStatusCode(_ name: String) -> mte_status {
    return mte_wrap_base_status_code(name)
  }

  // Returns true if the given status is an error, false if it is success or a
  // warning.
  public class func statusIsError(_ status: mte_status) -> Bool {
    return mte_base_status_is_error(status) != MTE_FALSE
  }

  // Returns true if runtime options are available or false if not.
  public class func hasRuntimeOpts() -> Bool {
    return mte_wrap_base_has_runtime_opts() != MTE_FALSE
  }

  // Returns the default DRBG. If runtime options are not available, this is
  // the only option available; otherwise it is a suitable default.
  public class func getDefaultDrbg() -> mte_drbgs {
    return mte_wrap_base_default_drbg()
  }

  // Returns the default token size. If runtime options are not available, this
  // is the only option available; otherwise it is a suitable default.
  public class func getDefaultTokBytes() -> Int {
    return Int(mte_wrap_base_default_tok_bytes())
  }

  // Returns the default verifiers. If runtime options are not available, this
  // is the only option available; otherwise it is a suitable default.
  public class func getDefaultVerifiers() -> mte_verifiers {
    return mte_wrap_base_default_verifiers()
  }

  // Returns the default cipher. If runtime options are not available, this is
  // the only option available; otherwise it is a suitable default.
  public class func getDefaultCipher() -> mte_ciphers {
    return mte_wrap_base_default_cipher()
  }

  // Returns the default hash. If runtime options are not available, this is
  // the only option available; otherwise it is a suitable default.
  public class func getDefaultHash() -> mte_hashes {
    return mte_wrap_base_default_hash()
  }

  // Returns the count of DRBG algorithms.
  public class func getDrbgsCount() -> Int {
    return Int(mte_wrap_base_drbgs_count())
  }

  // Returns the enumeration name for the given algorithm.
  public class func getDrbgsName(_ algo: mte_drbgs) -> String {
    if let str = mte_wrap_base_drbgs_name(algo) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the algorithm for the given enumeration name.
  public class func getDrbgsAlgo(_ name: String) -> mte_drbgs {
    return mte_wrap_base_drbgs_algo(name)
  }

  // Returns the security strength for the given algorithm.
  public class func getDrbgsSecStrengthBytes(_ algo: mte_drbgs) -> Int {
    return Int(mte_wrap_base_drbgs_sec_strength_bytes(algo))
  }

  // Returns the minimum/maximum personalization string size for the given
  // algorithm.
  public class func getDrbgsPersonalMinBytes(_ algo: mte_drbgs) -> Int {
    return Int(mte_wrap_base_drbgs_personal_min_bytes(algo))
  }
  public class func getDrbgsPersonalMaxBytes(_ algo: mte_drbgs) -> UInt64 {
    return mte_wrap_base_drbgs_personal_max_bytes(algo)
  }

  // Returns the minimum/maximum entropy size for the given algorithm.
  public class func getDrbgsEntropyMinBytes(_ algo: mte_drbgs) -> Int {
    return Int(mte_wrap_base_drbgs_entropy_min_bytes(algo))
  }
  public class func getDrbgsEntropyMaxBytes(_ algo: mte_drbgs) -> UInt64 {
    return mte_wrap_base_drbgs_entropy_max_bytes(algo)
  }

  // Returns the minimum/maximum nonce size for the given algorithm.
  public class func getDrbgsNonceMinBytes(_ algo: mte_drbgs) -> Int {
    return Int(mte_wrap_base_drbgs_nonce_min_bytes(algo))
  }
  public class func getDrbgsNonceMaxBytes(_ algo: mte_drbgs) -> Int {
    return Int(mte_wrap_base_drbgs_nonce_max_bytes(algo))
  }

  // Returns the reseed interval for the given algorithm.
  public class func getDrbgsReseedInterval(_ algo: mte_drbgs) -> UInt64 {
    return mte_wrap_base_drbgs_reseed_interval(algo)
  }

  // Set the increment DRBG to return an error during instantiation and
  // uninstantiation (if true) or not (if false). This is useful for testing
  // error handling. The flag is false until set with this.
  public class func setIncrInstError(_ flag: Bool) {
    mte_wrap_base_drbgs_incr_inst_error(flag ? MTE_TRUE : MTE_FALSE)
  }

  // Set the increment DRBG to produce an error after the given number of values
  // have been generated (if flag is true) or turn off errors (if flag is false)
  // other than the reseed error, which is always produced when the seed
  // interval is reached. The flag is false until set with this.
  public class func setIncrGenError(_ flag: Bool, _ after: Int) {
    mte_wrap_base_drbgs_incr_gen_error(flag ? MTE_TRUE : MTE_FALSE,
                                       UInt32(after))
  }

  // Returns the count of verifier algorithms.
  public class func getVerifiersCount() -> Int {
    return Int(mte_wrap_base_verifiers_count())
  }

  // Returns the enumeration name for the given algorithm.
  public class func getVerifiersName(_ algo: mte_verifiers) -> String {
    if let str = mte_wrap_base_verifiers_name(algo) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the algorithm for the given enumeration name.
  public class func getVerifiersAlgo(_ name: String) -> mte_verifiers {
    return mte_wrap_base_verifiers_algo(name)
  }

  // Returns the count of cipher algorithms.
  public class func getCiphersCount() -> Int {
    return Int(mte_wrap_base_ciphers_count())
  }

  // Returns the enumeration name for the given algorithm.
  public class func getCiphersName(_ algo: mte_ciphers) -> String {
    if let str = mte_wrap_base_ciphers_name(algo) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the algorithm for the given enumeration name.
  public class func getCiphersAlgo(_ name: String) -> mte_ciphers {
    return mte_wrap_base_ciphers_algo(name)
  }

  // Returns the block size for the given algorithm.
  public class func getCiphersBlockBytes(_ algo: mte_ciphers) -> Int {
    return Int(mte_wrap_base_ciphers_block_bytes(algo))
  }

  // Returns the count of hash algorithms.
  public class func getHashesCount() -> Int {
    return Int(mte_wrap_base_hashes_count())
  }

  // Returns the enumeration name for the given algorithm.
  public class func getHashesName(_ algo: mte_hashes) -> String {
    if let str = mte_wrap_base_hashes_name(algo) {
      return String(cString: str)
    }
    return String()
  }

  // Returns the algorithm for the given enumeration name.
  public class func getHashesAlgo(_ name: String) -> mte_hashes {
    return mte_wrap_base_hashes_algo(name)
  }

  // Initialize. Derived classes must call initBase() from their initializer.
  public init() throws {
    // Initialize MTE.
    if !MteBase.ourMteInitialized {
      // Do global init.
      if mte_init(nil, nil) == 0 {
        throw MteError.logicError("MteBase.init: MTE init error.")
      }
      MteBase.ourMteInitialized = true

      // Check version.
      if mte_wrap_base_version_major() != MTE_VERSION_MAJOR ||
         mte_wrap_base_version_minor() != MTE_VERSION_MINOR ||
         mte_wrap_base_version_patch() != MTE_VERSION_PATCH {
        throw MteError.logicError("MteBase.init: MTE version mismatch.")
      }
    }

    // Allocate the initial entropy buffer.
    myEntropyRaw = UnsafeMutableRawPointer.allocate(byteCount: myEntropyAlloc,
                                                    alignment: 16)
  }

  // Deinitialize.
  deinit {
    myEntropyRaw.deallocate()
  }

  // Return the options in use.
  public func getDrbg() -> mte_drbgs { return myDrbg }
  public func getTokBytes() -> Int { return myTokBytes }
  public func getVerifiers() -> mte_verifiers { return myVerifiers }
  public func getCipher() -> mte_ciphers { return myCipher }
  public func getHash() -> mte_hashes { return myHash }

  // Set the entropy callback. If not nil, it is called to get entropy. If
  // nil, the entropy set with setEntropy() is used.
  public func setEntropyCallback(_ cb: MteEntropyCallback?) {
    myEntropyCb = cb;
  }

  // Set the entropy value. This must be done before calling an instantiation
  // method that will trigger the entropy callback.
  //
  // The entropy is zeroized immediately after copying to unsafe memory. The
  // unsafe version is zeroized when used by an instantiation call.
  //
  // If the entropy callback is nil, entropyInput is used as the entropy.
  public func setEntropy(_ entropyInput: inout [UInt8]) {
    // Reallocate if necessary.
    if entropyInput.count > myEntropyAlloc {
      myEntropyAlloc = entropyInput.count
      myEntropyRaw.deallocate()
      myEntropyRaw = UnsafeMutableRawPointer.allocate(byteCount: myEntropyAlloc,
                                                      alignment: 16)
    }

    // Copy to the unsafe memory.
    myEntropyBytes = entropyInput.count
    entropyInput.withUnsafeBytes { buff in
      let ei = buff.bindMemory(to: UInt8.self)
      let raw = myEntropyRaw.assumingMemoryBound(to: UInt8.self)
      raw.update(from: ei.baseAddress!, count: myEntropyBytes)
    }

    // Zeroize the provided array.
    entropyInput.resetBytes(in: Range(uncheckedBounds:
                                      (lower: 0, upper: entropyInput.count)))
  }

  // Set the nonce callback. If not nil, it is used to get the nonce. If nil,
  // the nonce set with setNonce() is used.
  public func setNonceCallback(_ cb: MteNonceCallback?) {
    myNonceCb = cb
  }

  // Set the nonce. This must be done before calling an instantiation method
  // that will trigger the nonce callback.
  //
  // If the nonce callback is nil, nonce is used as the nonce.
  public func setNonce(_ nonce: [UInt8]) {
    myNonce = nonce
  }

  // Calls setNonce() with the nonce value as an array of bytes in little
  // endian format.
  public func setNonce(_ nonce: UInt64) {
    if myNonce == nil || myNonce!.count != myNonceIntBytes {
      myNonce = [UInt8](repeating: 0, count: myNonceIntBytes)
    }
    for i in 0..<min(MemoryLayout<UInt64>.size, myNonceIntBytes) {
      myNonce![i] = UInt8(UInt64(nonce >> (i * 8)) & 0xFF)
    }
    if myNonceIntBytes > MemoryLayout<UInt64>.size {
      for i in MemoryLayout<UInt64>.size..<myNonceIntBytes {
        myNonce![i] = 0
      }
    }
  }

  // Set the timestamp callback. If not nil, it is called to get the timestamp.
  // If nil, 0 is used.
  public func setTimestampCallback(_ cb: MteTimestampCallback?) {
    myTimestampCb = cb
  }

  // The entropy callback.
  internal func entropyCallback(_ minEntropy: Int,
                  _ minLength: Int,
                  _ maxLength: UInt64,
                  _ entropyInput: inout [UInt8],
                  _ eiBytes: inout UInt64,
                  _ entropyLong: inout UnsafeMutableRawPointer?) -> mte_status {
    // Call the callback if set.
    if myEntropyCb != nil {
      return myEntropyCb!.entropyCallback(minEntropy,
                                          minLength,
                                          maxLength,
                                          &entropyInput,
                                          &eiBytes,
                                          &entropyLong)
    }

    // Check the length.
    if myEntropyBytes < minLength || myEntropyBytes > maxLength {
      return mte_status_drbg_catastrophic
    }

    // Set the raw pointer to point at the unsafe memory.
    entropyLong = myEntropyRaw

    // Success.
    eiBytes = UInt64(myEntropyBytes)
    return mte_status_success
  }

  // The nonce callback.
  internal func nonceCallback(_ minLength: Int,
                              _ maxLength: Int,
                              _ nonce: inout [UInt8],
                              _ nBytes: inout Int) {
    // Call the callback if set.
    if myNonceCb != nil {
      myNonceCb!.nonceCallback(minLength, maxLength, &nonce, &nBytes)
      return
    }

    // Copy to the provided buffer.
    nBytes = myNonce!.count
    nonce.replaceSubrange(Range(uncheckedBounds: (0, myNonce!.count)),
                          with: myNonce!)
  }

  // The timestamp callback.
  internal func timestampCallback() -> UInt64 {
    // Call the callback if set.
    if myTimestampCb != nil {
      return myTimestampCb!.timestampCallback();
    }

    // Default to 0 otherwise.
    return 0
  }

  // Initialize.
  public func initBase(_ drbg: mte_drbgs,
                       _ tokBytes: Int,
                       _ verifiers: mte_verifiers,
                       _ cipher: mte_ciphers,
                       _ hash: mte_hashes) {
    // Set the options.
    myDrbg = drbg
    myTokBytes = tokBytes
    myVerifiers = verifiers
    myCipher = cipher
    myHash = hash

    // The ideal nonce length is the size of the nonce integer, but it must be
    // at least the minimum for the DRBG and no more than the maximum for the
    // DRBG.
    myNonceIntBytes = max(MteBase.getDrbgsNonceMinBytes(drbg),
                          min(MemoryLayout<UInt64>.size,
                              MteBase.getDrbgsNonceMaxBytes(drbg)))
  }

  // Helpers to resize arrays.
  public class func resizeArray(_ arr: inout [UInt8], _ newSize: Int) {
    if newSize > arr.count {
      arr.append(contentsOf: [UInt8](repeating: 0, count: newSize - arr.count))
    }
  }
  public class func resizeArray(_ arr: inout [UInt8], _ newSize: UInt32) {
    resizeArray(&arr, Int(newSize))
  }

  // Internal callbacks.
  public static let ourEntropyCallback: Optional<@convention(c)
    (UnsafeMutableRawPointer?,
     UInt32,
     UInt32,
     UInt64,
     UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
     UnsafeMutablePointer<UInt64>?) -> mte_status> = {
      (context, minEntropy, minLength, maxLength, entropyInput, eiBytes) ->
        mte_status in
      let c = Unmanaged<MteBase>.fromOpaque(context!).takeUnretainedValue()
      var eib = eiBytes!.pointee
      var ei = [UInt8](repeating: 0, count: Int(eib))
      var eiLong: UnsafeMutableRawPointer? = nil
      let status = c.entropyCallback(Int(minEntropy),
                                     Int(minLength),
                                     maxLength,
                                     &ei,
                                     &eib,
                                     &eiLong)
      if eiLong != nil {
        entropyInput![0] = eiLong!.assumingMemoryBound(to: UInt8.self)
      }
      else if eib != 0 && eib <= Int(eiBytes!.pointee) {
        ei.withUnsafeBufferPointer { eiBuff in
          entropyInput![0]!.update(from: eiBuff.baseAddress!, count: Int(eib))
        }
        ei.resetBytes(in: Range(uncheckedBounds: (0, ei.count)))
      }
      eiBytes!.pointee = eib
      return status
    }
  public static let ourNonceCallback: Optional<@convention(c)
    (UnsafeMutableRawPointer?,
     UInt32,
     UInt32,
     UnsafeMutableRawPointer?,
     UnsafeMutablePointer<UInt32>?) -> Void> = {
      (context, minLength, maxLength, nonce, nBytes) in
      let c = Unmanaged<MteBase>.fromOpaque(context!).takeUnretainedValue()
      var nb = Int(maxLength)
      var n = [UInt8](repeating: 0, count: nb)
      c.nonceCallback(Int(minLength),
                      Int(maxLength),
                      &n,
                      &nb)
      n.withUnsafeBufferPointer { nBuff in
        nonce!.assumingMemoryBound(to: UInt8.self).update(from:
          nBuff.baseAddress!, count: nb)
      }
      nBytes!.pointee = UInt32(nb)
    }
  public static let ourTimestampCallback: Optional<@convention(c)
    (UnsafeMutableRawPointer?) -> UInt64> = {
      (context) -> UInt64 in
      let c = Unmanaged<MteBase>.fromOpaque(context!).takeUnretainedValue()
      return c.timestampCallback()
    }

  // Options.
  private var myDrbg = mte_drbgs_none
  private var myTokBytes = 0
  private var myVerifiers = mte_verifiers_none
  private var myCipher = mte_ciphers_none
  private var myHash = mte_hashes_none

  // Callbacks.
  private var myEntropyCb: MteEntropyCallback? = nil
  private var myNonceCb: MteNonceCallback? = nil
  private var myTimestampCb: MteTimestampCallback? = nil

  // Instantiation inputs.
  private var myEntropyBytes = 0
  private var myEntropyAlloc = 0
  private var myEntropyRaw: UnsafeMutableRawPointer
  private var myNonce: [UInt8]? = nil

  // Nonce length when set as an integer.
  private var myNonceIntBytes = 0

  // True if MTE initialized, false if not.
  private static var ourMteInitialized = false
}

public enum MteError: Error {
  case logicError(String)
  case runtimeError(String)
}

