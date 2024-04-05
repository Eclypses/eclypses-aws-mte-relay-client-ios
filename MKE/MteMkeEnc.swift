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
import Mte
import Core
#endif

// Class MteEnc
//
// This is the MTE Managed-Key Encryption encoder/encryptor.
//
// To use, create an object of this type, call instantiate(), call encode() zero
// or more times to encode each piece of data, then optionally call
// uninstantiate() to clear the random state.
//
// Alternatively, the state can be saved any time after instantiate() and
// restored instead of instantiate() to pick up at a known point.
//
// To use as a chunk-based encryptor, call startEncrypt(), call encryptChunk()
// zero or more times to encrypt each chunk of data, then finishEncrypt().
public class MteMkeEnc : MteBase {
  // Initialize using default options.
  public override convenience init() throws {
    try self.init(MteBase.getDefaultDrbg(),
                  MteBase.getDefaultTokBytes(),
                  MteBase.getDefaultVerifiers(),
                  MteBase.getDefaultCipher(),
                  MteBase.getDefaultHash())
  }

  // Initialize taking the DRBG, token size in bytes, verifiers algorithm,
  // cipher algorithm, and hash algorithm.
  public init(_ drbg: mte_drbgs,
              _ tokBytes: Int,
              _ verifiers: mte_verifiers,
              _ cipher: mte_ciphers,
              _ hash: mte_hashes) throws {
    // Get the encoder size.
    let bytes = Int(mte_wrap_mke_enc_state_bytes(drbg,
                                                 UInt32(tokBytes),
                                                 verifiers,
                                                 cipher,
                                                 hash))
    if bytes == 0 {
      throw MteError.logicError("MteMkeEnc.init: Invalid options.")
    }

    // Allocate the encoder.
    myEncoder =
      UnsafeMutableRawPointer.allocate(byteCount: bytes,
                                       alignment: MemoryLayout<Int64>.alignment)

    // Super.
    try super.init()

    // Initialize the base.
    super.initBase(drbg, tokBytes, verifiers, cipher, hash)

    // Initialize the encoder state.
    let status = mte_wrap_mke_enc_state_init(myEncoder,
                                             drbg,
                                             UInt32(tokBytes),
                                             verifiers,
                                             cipher,
                                             hash)
    if status != mte_status_success {
      throw MteError.logicError("MteMkeEnc.init: Invalid options.")
    }

    // Allocate the save buffers.
    mySaveBuff = [UInt8](repeating: 0,
                         count: Int(mte_wrap_mke_enc_save_bytes(myEncoder)))
    mySaveBuff64 = [UInt8](repeating: 0,
                         count: Int(mte_wrap_mke_enc_save_bytes_b64(myEncoder)))
  }

  // Deallocate. The uninstantiate() method is called.
  deinit {
    // Uninstantiate.
    _ = uninstantiate()

    // Deallocate buffers.
    myEncoder.deallocate()
  }

  // Instantiate the encoder/encryptor with the personalization string. The
  // entropy and nonce callbacks will be called to get the rest of the seeding
  // material. Returns the status.
  public func instantiate(_ ps: [UInt8]) -> mte_status {
    let uc = Unmanaged.passUnretained(self).toOpaque()
    return mte_wrap_mke_enc_instantiate(myEncoder,
                                        MteBase.ourEntropyCallback, uc,
                                        MteBase.ourNonceCallback, uc,
                                        ps, UInt32(ps.count))
  }
  public func instantiate(_ ps: String) -> mte_status {
    let uc = Unmanaged.passUnretained(self).toOpaque()
    return mte_wrap_mke_enc_instantiate(myEncoder,
                                        MteBase.ourEntropyCallback, uc,
                                        MteBase.ourNonceCallback, uc,
                                        ps, UInt32(ps.utf8.count))
  }

  // Returns the reseed counter.
  public func getReseedCounter() -> UInt64 {
    return mte_mke_enc_reseed_counter(myEncoder)
  }

  // Returns the saved state. The Base64 version returns a Base64-encoded
  // saved state instead. On error, nil is returned.
  public func saveState() -> [UInt8]? {
    let status = mySaveBuff.withUnsafeMutableBytes { buff in
      mte_mke_enc_state_save(myEncoder, buff.baseAddress)
    }
    return status == mte_status_success ? mySaveBuff : nil
  }
  public func saveStateB64() -> String? {
    let status = mySaveBuff64.withUnsafeMutableBytes { buff in
      mte_wrap_mke_enc_state_save_b64(myEncoder, buff.baseAddress)
    }
    return status == mte_status_success ? String(cString: mySaveBuff64) : nil
  }

  // Restore a saved state, which must be the same length as was returned from
  // the saveState() call. The Base64 version takes a Base64-encoded saved
  // state as produced by saveStateB64(). Returns the status.
  public func restoreState(_ saved: [UInt8]) -> mte_status {
    return mte_mke_enc_state_restore(myEncoder, saved)
  }
  public func restoreStateB64(_ saved: String) -> mte_status {
    return mte_wrap_mke_enc_state_restore_b64(myEncoder, saved)
  }

  // Returns the encode buffer size in bytes given the data length in bytes.
  public func getBuffBytes(_ dataBytes: Int) -> Int {
    return Int(mte_wrap_mke_enc_buff_bytes(myEncoder, UInt32(dataBytes)))
  }
  public func getBuffBytesB64(_ dataBytes: Int) -> Int {
    return Int(mte_wrap_mke_enc_buff_bytes_b64(myEncoder, UInt32(dataBytes)))
  }

  // Encode/encrypt the given data. Returns the encoded/encrypted version and
  // the status.
  public func encode(_ data: [UInt8]) ->
  (encoded: ArraySlice<UInt8>, status: mte_status) {
    // Get the encode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_mke_enc_buff_bytes(myEncoder, UInt32(data.count))
    MteBase.resizeArray(&myEncBuff, buffBytes)

    // Encode.
    var eOff: UInt32 = 0
    var eBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = myEncBuff.withUnsafeMutableBytes { buff in
      mte_wrap_mke_enc_encode(myEncoder,
                              MteBase.ourTimestampCallback, uc,
                              data, UInt32(data.count),
                              buff.baseAddress, &eOff, &eBytes)
    }
    if status != mte_status_success {
      return (ArraySlice<UInt8>(), status)
    }

    // Return the encoded part.
    return (myEncBuff[Int(eOff)..<Int(eOff + eBytes)], status)
  }
  public func encodeB64(_ data: [UInt8]) ->
  (encoded: String, status: mte_status) {
    // Get the encode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_mke_enc_buff_bytes_b64(myEncoder,
                                                    UInt32(data.count))
    MteBase.resizeArray(&myEncBuff, buffBytes)

    // Encode.
    var status = mte_status_success
    let b64 = myEncBuff.withUnsafeMutableBytes { (buff) -> String in
      var eOff: UInt32 = 0
      var eBytes: UInt32 = 0
      let uc = Unmanaged.passUnretained(self).toOpaque()
      status = mte_wrap_mke_enc_encode_b64(myEncoder,
                                           MteBase.ourTimestampCallback, uc,
                                           data, UInt32(data.count),
                                           buff.baseAddress, &eOff, &eBytes)
      if status != mte_status_success {
        return String()
      }
      let buffOff = buff.baseAddress!.advanced(by: Int(eOff))
      let buffOffC = buffOff.assumingMemoryBound(to: CChar.self)
      return String(cString: buffOffC)
    }
    return (b64, status)
  }

  // Encode/encrypt the given string. Returns the encoded/encrypted version and
  // the status.
  public func encode(_ str: String) ->
  (encoded: ArraySlice<UInt8>, status: mte_status) {
    // Get the encode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_mke_enc_buff_bytes(myEncoder,
                                                UInt32(str.utf8.count))
    MteBase.resizeArray(&myEncBuff, buffBytes)

    // Encode.
    var eOff: UInt32 = 0
    var eBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = myEncBuff.withUnsafeMutableBytes { buff in
      mte_wrap_mke_enc_encode(myEncoder,
                              MteBase.ourTimestampCallback, uc,
                              str, UInt32(str.utf8.count),
                              buff.baseAddress, &eOff, &eBytes)
    }
    if status != mte_status_success {
      return (ArraySlice<UInt8>(), status)
    }

    // Return the encoded part.
    return (myEncBuff[Int(eOff)..<Int(eOff + eBytes)], status)
  }
  public func encodeB64(_ str: String) ->
  (encoded: String, status: mte_status) {
    // Get the encode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_mke_enc_buff_bytes_b64(myEncoder,
                                                    UInt32(str.utf8.count))
    MteBase.resizeArray(&myEncBuff, buffBytes)

    // Encode.
    var status = mte_status_success
    let b64 = myEncBuff.withUnsafeMutableBytes { (buff) -> String in
      var eOff: UInt32 = 0
      var eBytes: UInt32 = 0
      let uc = Unmanaged.passUnretained(self).toOpaque()
      status = mte_wrap_mke_enc_encode_b64(myEncoder,
                                           MteBase.ourTimestampCallback, uc,
                                           str, UInt32(str.utf8.count),
                                           buff.baseAddress, &eOff, &eBytes)
      if status != mte_status_success {
        return String()
      }
      let buffOff = buff.baseAddress!.advanced(by: Int(eOff))
      let buffOffC = buffOff.assumingMemoryBound(to: CChar.self)
      return String(cString: buffOffC)
    }
    return (b64, status)
  }

  // Encode the given data of the given length at the given offset to the
  // given buffer at the given offset. Returns the offset to the encoded
  // version, length of the encoded version in bytes, and status. The encoded
  // buffer must have sufficient length remaining after the offset. Use
  // getBuffBytes() or getBuffBytes64() to determine the buffer requirement for
  // raw or Base64 respectively.
  public func encode(_ data: [UInt8], _ dataOff: Int, _ dataBytes: Int,
                     _ encoded: inout [UInt8], _ encOff: Int) ->
  (encOff: Int, encBytes: Int, status: mte_status) {
    // Encode.
    var eOff: UInt32 = 0
    var eBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = encoded.withUnsafeMutableBytes { encbuff in
      data.withUnsafeBytes { databuff in
        mte_wrap_mke_enc_encode(myEncoder,
                                MteBase.ourTimestampCallback, uc,
                                databuff.baseAddress!.advanced(by: dataOff),
                                UInt32(dataBytes),
                                encbuff.baseAddress!.advanced(by: encOff),
                                &eOff, &eBytes)
      }
    }

    // Return the information.
    return (encOff + Int(eOff), Int(eBytes), status)
  }
  public func encodeB64(_ data: [UInt8], _ dataOff: Int, _ dataBytes: Int,
                        _ encoded: inout [UInt8], _ encOff: Int) ->
  (encOff: Int, encBytes: Int, status: mte_status) {
    // Encode.
    var eOff: UInt32 = 0
    var eBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = encoded.withUnsafeMutableBytes { encbuff in
      data.withUnsafeBytes { databuff in
        mte_wrap_mke_enc_encode_b64(myEncoder,
                                    MteBase.ourTimestampCallback, uc,
                                    databuff.baseAddress!.advanced(by: dataOff),
                                    UInt32(dataBytes),
                                    encbuff.baseAddress!.advanced(by: encOff),
                                    &eOff, &eBytes)
      }
    }

    // Return the information.
    return (encOff + Int(eOff), Int(eBytes), status)
  }

  // Returns the length of the result finishEncrypt() will produce. Use this if
  // you need to know that size before you can call it.
  public func encryptFinishBytes() -> Int {
    return Int(mte_wrap_mke_enc_encrypt_finish_bytes(myEncoder))
  }

  // Start a chunk-based encryption session. Returns the status.
  public func startEncrypt() -> mte_status {
    // Get the chunk-based encryption state requirement and resize if
    // necessary.
    let buffBytes = mte_wrap_mke_enc_encrypt_state_bytes(myEncoder)
    MteBase.resizeArray(&myEncBuff, buffBytes)

    // Start the session.
    return myEncBuff.withUnsafeMutableBytes { cbuff in
      mte_mke_enc_encrypt_start(myEncoder, cbuff.baseAddress)
    }
  }

  // Encrypt a chunk of data in a chunk-based encryption session. The data is
  // encrypted in place. The data length must be a multiple of the chosen
  // cipher's block size. Returns the status.
  public func encryptChunk(_ data: inout [UInt8]) -> mte_status {
    let bytes = UInt32(data.count)
    return data.withUnsafeMutableBytes { dbuff in
      myEncBuff.withUnsafeMutableBytes { cbuff in
        mte_wrap_mke_enc_encrypt_chunk(myEncoder, cbuff.baseAddress,
                                       dbuff.baseAddress, bytes,
                                       dbuff.baseAddress)
      }
    }
  }

  // Encrypt a chunk of data at the given offset of the given length in a chunk-
  // based encryption session. The data is encrypted in place. The data length
  // must be a multiple of the chosen cipher's block size. Returns the status.
  public func encryptChunk(_ data: inout [UInt8],
                           _ off: Int,
                           _ bytes: Int) -> mte_status {
    return data.withUnsafeMutableBytes { dbuff in
      myEncBuff.withUnsafeMutableBytes { cbuff in
        mte_wrap_mke_enc_encrypt_chunk(myEncoder, cbuff.baseAddress,
                                       dbuff.baseAddress!.advanced(by: off),
                                       UInt32(bytes),
                                       dbuff.baseAddress!.advanced(by: off))
      }
    }
  }

  // Finish a chunk-based encryption session. Returns the final part of the
  // result and status.
  public func finishEncrypt() ->
  (encoded: ArraySlice<UInt8>, status: mte_status) {
    // Finish the encrypt session.
    var rOff: UInt32 = 0
    var rBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = myEncBuff.withUnsafeMutableBytes { cbuff in
      mte_wrap_mke_enc_encrypt_finish(myEncoder, cbuff.baseAddress,
                                      MteBase.ourTimestampCallback, uc,
                                      &rOff, &rBytes)
    }
    if status != mte_status_success {
      return (ArraySlice<UInt8>(), status)
    }

    // Return the tokenized hash.
    return (myEncBuff[Int(rOff)..<Int(rOff + rBytes)], status)
  }

  // Uninstantiate the encoder. It is no longer usable after this call. Returns
  // the MTE status.
  public func uninstantiate() -> mte_status {
    return mte_mke_enc_uninstantiate(myEncoder)
  }

  // The encoder state.
  private let myEncoder: UnsafeMutableRawPointer

  // Encoder buffer.
  private var myEncBuff = [UInt8]()

  // State save buffer.
  private var mySaveBuff = [UInt8]()
  private var mySaveBuff64 = [UInt8]()
}

