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
#endif

// Class MteDec
//
// This is the MTE decoder.
//
// To use, create an object of this type, call instantiate(), call decode() zero
// or more times to decode each encoded data, then optionally call
// uninstantiate() to clear the random state.
//
// Alternatively, the state can be saved any time after instantiate() and
// restored instead of instantiate() to pick up at a known point.
public class MteDec : MteBase {
  // Initialize using default options.
  //
  // The timestamp window and sequence window are optionally settable.
  public convenience init(_ tWindow: UInt64 = 0, _ sWindow: Int = 0) throws {
    try self.init(MteBase.getDefaultDrbg(),
                  MteBase.getDefaultTokBytes(),
                  MteBase.getDefaultVerifiers(),
                  tWindow,
                  sWindow)
  }

  // Initialize taking the DRBG, token size in bytes, verifiers algorithm,
  // timestamp window, and sequence window.
  public init(_ drbg: mte_drbgs,
              _ tokBytes: Int,
              _ verifiers: mte_verifiers,
              _ tWindow: UInt64,
              _ sWindow: Int) throws {
    // Get the decoder size.
    let bytes = Int(mte_wrap_dec_state_bytes(drbg, UInt32(tokBytes), verifiers))
    if bytes == 0 {
      throw MteError.logicError("MteDec.init: Invalid options.")
    }

    // Allocate the decoder.
    myDecoder =
      UnsafeMutableRawPointer.allocate(byteCount: bytes,
                                       alignment: MemoryLayout<Int64>.alignment)

    // Super.
    try super.init()

    // Initialize the base.
    super.initBase(drbg,
                   tokBytes,
                   verifiers,
                   mte_ciphers_none,
                   mte_hashes_none)

    // Initialize the decoder state.
    let status = mte_wrap_dec_state_init(myDecoder,
                                         drbg,
                                         UInt32(tokBytes),
                                         verifiers,
                                         tWindow,
                                         Int32(sWindow))
    if status != mte_status_success {
      throw MteError.logicError("MteDec.init: Invalid options.")
    }

    // Allocate the save buffers.
    mySaveBuff = [UInt8](repeating: 0,
                         count: Int(mte_wrap_dec_save_bytes(myDecoder)))
    mySaveBuff64 = [UInt8](repeating: 0,
                           count: Int(mte_wrap_dec_save_bytes_b64(myDecoder)))
  }

  // Deallocate. The uninstantiate() method is called.
  deinit {
    // Uninstantiate.
    _ = uninstantiate()

    // Deallocate buffers.
    myDecoder.deallocate()
  }

  // Instantiate the decoder with the personalization string. The entropy and
  // nonce callbacks will be called to get the rest of the seeding material.
  // Returns the status.
  public func instantiate(_ ps: [UInt8]) -> mte_status {
    let uc = Unmanaged.passUnretained(self).toOpaque()
    return mte_wrap_dec_instantiate(myDecoder,
                                    MteBase.ourEntropyCallback, uc,
                                    MteBase.ourNonceCallback, uc,
                                    ps, UInt32(ps.count))
  }
  public func instantiate(_ ps: String) -> mte_status {
    let uc = Unmanaged.passUnretained(self).toOpaque()
    return mte_wrap_dec_instantiate(myDecoder,
                                    MteBase.ourEntropyCallback, uc,
                                    MteBase.ourNonceCallback, uc,
                                    ps, UInt32(ps.utf8.count))
  }

  // Returns the reseed counter.
  public func getReseedCounter() -> UInt64 {
    return mte_dec_reseed_counter(myDecoder)
  }

  // Returns the saved state. The Base64 version returns a Base64-encoded
  // saved state instead. On error, nil is returned.
  public func saveState() -> [UInt8]? {
    let status = mySaveBuff.withUnsafeMutableBytes { buff in
      mte_dec_state_save(myDecoder, buff.baseAddress)
    }
    return status == mte_status_success ? mySaveBuff : nil
  }
  public func saveStateB64() -> String? {
    let status = mySaveBuff64.withUnsafeMutableBytes { buff in
      mte_wrap_dec_state_save_b64(myDecoder, buff.baseAddress)
    }
    return status == mte_status_success ? String(cString: mySaveBuff64) : nil
  }

  // Restore a saved state, which must be the same length as was returned from
  // the saveState() call. The Base64 version takes a Base64-encoded saved
  // state as produced by saveStateB64(). Returns the status.
  public func restoreState(_ saved: [UInt8]) -> mte_status {
    return mte_dec_state_restore(myDecoder, saved)
  }
  public func restoreStateB64(_ saved: String) -> mte_status {
    return mte_wrap_dec_state_restore_b64(myDecoder, saved)
  }

  // Returns the decode buffer size in bytes given the encoded length in bytes.
  public func getBuffBytes(_ encodedBytes: Int) -> Int {
    return Int(mte_wrap_dec_buff_bytes(myDecoder, UInt32(encodedBytes)))
  }
  public func getBuffBytesB64(_ encodedBytes: Int) -> Int {
    return Int(mte_wrap_dec_buff_bytes_b64(myDecoder, UInt32(encodedBytes)))
  }

  // Decode the given encoded version. Returns the decoded data and the status.
  public func decode(_ encoded: [UInt8]) ->
  (decoded: ArraySlice<UInt8>, status: mte_status) {
    // Get the decode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_dec_buff_bytes(myDecoder, UInt32(encoded.count))
    MteBase.resizeArray(&myDecBuff, buffBytes)

    // Decode.
    var dOff: UInt32 = 0
    var dBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = myDecBuff.withUnsafeMutableBytes { buff in
      mte_wrap_dec_decode(myDecoder,
                          MteBase.ourTimestampCallback, uc,
                          encoded, UInt32(encoded.count),
                          buff.baseAddress, &dOff, &dBytes,
                          &myEncTs, &myDecTs, &myMsgSkipped)
    }
    if MteBase.statusIsError(status) {
      return (ArraySlice<UInt8>(), status)
    }

    // Return the decoded part.
    return (myDecBuff[Int(dOff)..<Int(dOff + dBytes)], status)
  }
  public func decodeB64(_ encoded: String) ->
  (decoded: ArraySlice<UInt8>, status: mte_status) {
    // Get the decode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_dec_buff_bytes_b64(myDecoder,
                                                UInt32(encoded.utf8.count))
    MteBase.resizeArray(&myDecBuff, buffBytes)

    // Decode.
    var dOff: UInt32 = 0
    var dBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = myDecBuff.withUnsafeMutableBytes { buff in
      mte_wrap_dec_decode_b64(myDecoder,
                              MteBase.ourTimestampCallback, uc,
                              encoded, UInt32(encoded.utf8.count),
                              buff.baseAddress, &dOff, &dBytes,
                              &myEncTs, &myDecTs, &myMsgSkipped)
    }
    if MteBase.statusIsError(status) {
      return (ArraySlice<UInt8>(), status)
    }

    // Return the decoded part.
    return (myDecBuff[Int(dOff)..<Int(dOff + dBytes)], status)
  }

  // Decode the given encoded version to a string. Returns the decoded string
  // and the status.
  public func decodeStr(_ encoded: [UInt8]) ->
  (str: String, status: mte_status) {
    // Get the decode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_dec_buff_bytes(myDecoder, UInt32(encoded.count))
    MteBase.resizeArray(&myDecBuff, buffBytes)

    // Decode.
    var status = mte_status_success
    let str = myDecBuff.withUnsafeMutableBytes { (buff) -> String in
      var dOff: UInt32 = 0
      var dBytes: UInt32 = 0
      let uc = Unmanaged.passUnretained(self).toOpaque()
      status = mte_wrap_dec_decode(myDecoder,
                                   MteBase.ourTimestampCallback, uc,
                                   encoded, UInt32(encoded.count),
                                   buff.baseAddress, &dOff, &dBytes,
                                   &myEncTs, &myDecTs, &myMsgSkipped)
      if MteBase.statusIsError(status) {
        return String()
      }
      let buffOff = buff.baseAddress!.advanced(by: Int(dOff))
      let buffOffC = buffOff.assumingMemoryBound(to: CChar.self)
      return String(cString: buffOffC)
    }
    return (str, status)
  }
  public func decodeStrB64(_ encoded: String) ->
  (str: String, status: mte_status) {
    // Get the decode buffer requirement and resize if necessary.
    let buffBytes = mte_wrap_dec_buff_bytes_b64(myDecoder,
                                                UInt32(encoded.utf8.count))
    MteBase.resizeArray(&myDecBuff, buffBytes)

    // Decode.
    var status = mte_status_success
    let str = myDecBuff.withUnsafeMutableBytes { (buff) -> String in
      var dOff: UInt32 = 0
      var dBytes: UInt32 = 0
      let uc = Unmanaged.passUnretained(self).toOpaque()
      status = mte_wrap_dec_decode_b64(myDecoder,
                                       MteBase.ourTimestampCallback, uc,
                                       encoded, UInt32(encoded.utf8.count),
                                       buff.baseAddress, &dOff, &dBytes,
                                       &myEncTs, &myDecTs, &myMsgSkipped)
      if MteBase.statusIsError(status) {
        return String()
      }
      let buffOff = buff.baseAddress!.advanced(by: Int(dOff))
      let buffOffC = buffOff.assumingMemoryBound(to: CChar.self)
      return String(cString: buffOffC)
    }
    return (str, status)
  }

  // Decode the given encoded version of the given length at the given offset to
  // the given buffer at the given offset. Returns the offset of the decoded
  // version, length of the decoded version in bytes, and status. The decoded
  // buffer must have sufficient length remaining after the offset. Use
  // getBuffBytes() or getBuffBytes64() to determine the buffer requirement for
  // raw or Base64 respectively.
  public func decode(_ encoded: [UInt8], _ encOff: Int, _ encBytes: Int,
                     _ decoded: inout [UInt8], _ decOff: Int) ->
  (decOff: Int, decBytes: Int, status: mte_status) {
    // Decode.
    var dOff: UInt32 = 0
    var dBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = decoded.withUnsafeMutableBytes { decbuff in
      encoded.withUnsafeBytes { encbuff in
        mte_wrap_dec_decode(myDecoder,
                            MteBase.ourTimestampCallback, uc,
                            encbuff.baseAddress!.advanced(by: encOff),
                            UInt32(encBytes),
                            decbuff.baseAddress!.advanced(by: decOff),
                            &dOff, &dBytes,
                            &myEncTs, &myDecTs, &myMsgSkipped)
      }
    }

    // Return the information.
    return (decOff + Int(dOff), Int(dBytes), status)
  }
  public func decodeB64(_ encoded: [UInt8], _ encOff: Int, _ encBytes: Int,
                        _ decoded: inout [UInt8], _ decOff: Int) ->
  (decOff: Int, decBytes: Int, status: mte_status) {
    // Decode.
    var dOff: UInt32 = 0
    var dBytes: UInt32 = 0
    let uc = Unmanaged.passUnretained(self).toOpaque()
    let status = decoded.withUnsafeMutableBytes { decbuff in
      encoded.withUnsafeBytes { encbuff in
        mte_wrap_dec_decode_b64(myDecoder,
                                MteBase.ourTimestampCallback, uc,
                                encbuff.baseAddress!.advanced(by: encOff),
                                UInt32(encBytes),
                                decbuff.baseAddress!.advanced(by: decOff),
                                &dOff, &dBytes,
                                &myEncTs, &myDecTs, &myMsgSkipped)
      }
    }

    // Return the information.
    return (decOff + Int(dOff), Int(dBytes), status)
  }

  // Returns the timestamp set during encoding or 0 if there is no timestamp.
  public func getEncTs() -> UInt64 {
    return myEncTs
  }

  // Returns the timestamp set during decoding or 0 if there is no timestamp.
  public func getDecTs() -> UInt64 {
    return myDecTs
  }

  // Returns the number of messages that were skipped to get in sync during the
  // decode or 0 if there is no sequencing.
  public func getMsgSkipped() -> UInt32 {
    return myMsgSkipped
  }

  // Uninstantiate the decoder. It is no longer usable after this call. Returns
  // the MTE status.
  public func uninstantiate() -> mte_status {
    return mte_dec_uninstantiate(myDecoder)
  }

  // The decoder state.
  private let myDecoder: UnsafeMutableRawPointer

  // Decoder buffer.
  private var myDecBuff = [UInt8]()

  // State save buffer.
  private var mySaveBuff = [UInt8]()
  private var mySaveBuff64 = [UInt8]()

  // Decode values.
  private var myEncTs = UInt64(0)
  private var myDecTs = UInt64(0)
  private var myMsgSkipped = UInt32(0)
}

