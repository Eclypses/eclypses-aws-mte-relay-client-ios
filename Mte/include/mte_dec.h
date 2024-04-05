/*
Copyright (c) Eclypses, Inc.

All rights reserved.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
#ifndef mte_dec_h
#define mte_dec_h

#ifndef mte_base_h
#include "mte_base.h"
#endif

/* This is a message decoder.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Notes:
   1. All allocations can be static or dynamic. If dynamic, it is up to the
      caller to free it when done. This library does not allocate or deallocate
      any memory.
   2. A buffer must stay in scope while the call refers to it.
   3. All buffers are reusable and need only be allocated once.

   To create a decoder:
   1. Allocate the decoder state buffer of length mte_dec_state_bytes().
   2. Initialize the decoder state with mte_dec_state_init().
   3. Instantiate the decoder with mte_dec_instantiate().

   To save/restore a decoder:
   1. Allocate a buffer of length:
      a. mte_dec_save_bytes() [raw]
      b. mte_dec_save_bytes_b64() [Base64-encoded]
      to hold the saved state.
   2. Save the state with:
      a. mte_dec_state_save() [raw]
      b. mte_dec_state_save_b64() [Base64-encoded]
   3. Restore the state with:
      a. mte_dec_state_restore() [raw]
      b. mte_dec_state_restore_b64() [Base64-encoded]

   To use a decoder:
   1. Allocate the decode buffer of at least length:
      a. mte_dec_buff_bytes() [raw]
      b. mte_dec_buff_bytes_b64() [Base64-encoded]
      where encoded_bytes is the byte length of the encoded data.
   2. Decode each message with:
      a. mte_dec_decode() [raw]
      b. mte_dec_decode_b64() [Base64-encoded]
      where decoded_bytes will be set to the decoded length.
   3. The encode timestamp is retrieved with mte_dec_enc_ts().
   4. The decode timestamp is retrieved with mte_dec_dec_ts().
   5. The number of messages skipped is retrieved with mte_dec_msg_skipped().

   To destroy a decoder:
   1. Call mte_dec_uninstantiate(). This will zero the state of the decoder for
      security. The decoder must either be instantiated again or restored to
      be usable.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Initialization information. */
typedef struct mte_dec_init_info_
{
  /* Decoder parameters. */
  mte_decoder_params dec_params;
} mte_dec_init_info;

/* Initializer for a decoder init info structure.

   d = drbg
   t = tok_bytes
   v = verifiers
   tw = timestamp_window
   sw = sequencing window
   ds = drbg_state
   di = drbg_info
*/
#define MTE_DEC_INIT_INFO_INIT(d, t, v, tw, sw, ds, di)              \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)) }

/* Returns the decoder state size. Returns 0 if the combination is not usable.
   Use mte_drbgs_none for the drbg member if providing your own DRBG. */
MTE_SHARED
MTE_SIZE_T mte_dec_state_bytes(const mte_dec_init_info *info);

/* Initialize the decoder state. Returns the status.

   If a sequencing verifier is used, s_window has the following properties:
     a. If s_window == 0, any message out of sequence is flagged as an error
        before attempting decode.
     b. If -63 <= s_window <= -1, any message that comes out of sequence within
        abs(s_window) messages will be decoded, but the state is not advanced,
        so an earlier message can be decoded later. If a message comes out of
        sequence more than abs(s_window) ahead but no more than 2*abs(s_window)
        ahead, the message will be decoded and the state is advanced so the
        sequence number received is now only abs(s_window) ahead; any messages
        that come in before the base sequence number are flagged as an error
        before attempting to decode.
     c. If s_window > 0, any message that comes out of sequence within s_window
        messages will be decoded and the state is advanced so the sequence
        number received is now the base sequence number; any messages that come
        in before the new base sequence number are flagged as an error before
        attempting to decode.

   The state buffer must be of sufficient length to hold the decoder state. See
   mte_dec_state_bytes(). */
MTE_SHARED
mte_status mte_dec_state_init(MTE_HANDLE state, const mte_dec_init_info *info);

/* Instantiate the decoder. Returns the status. */
MTE_SHARED
mte_status mte_dec_instantiate(MTE_HANDLE state,
                               const mte_drbg_inst_info *info);

/* Returns the reseed counter. */
MTE_SHARED
MTE_UINT64_T mte_dec_reseed_counter(MTE_CHANDLE state);

/* Returns the state save size [raw]. Returns 0 if save is unsupported. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_dec_save_bytes(MTE_CHANDLE state);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the state save size [Base64-encoded]. Returns 0 if save is
   unsupported. */
MTE_SHARED
MTE_SIZE_T mte_dec_save_bytes_b64(MTE_CHANDLE state);
#endif

/* Save the decoder state to the given buffer in raw form. The size of the
   buffer must be mte_dec_save_bytes() and that is the length of the raw saved
   state. Returns mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_dec_state_save(MTE_CHANDLE state, void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Save the decoder state to the given buffer encoded in Base64. The size of the
   buffer must be mte_dec_save_bytes_b64() and the result is null-terminated.
   Returns mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_dec_state_save_b64(MTE_CHANDLE state, void *saved);
#endif

/* Restore the decoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_dec_state_restore(MTE_HANDLE state, const void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Restore the decoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_dec_state_restore_b64(MTE_HANDLE state, const void *saved);
#endif

/* Returns the decode buffer size [raw] in bytes given the encoded length in
   bytes. The decode buffer provided to mte_dec_decode() must be of at least
   this length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_dec_buff_bytes(MTE_CHANDLE state, MTE_SIZE_T encoded_bytes);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the decode buffer size [Base64-encoded] in bytes given the encoded
   length in bytes. The decode buffer provided to mte_dec_decode_b64() must be
   of at least this length. */
MTE_SHARED
MTE_SIZE_T mte_dec_buff_bytes_b64(MTE_CHANDLE state, MTE_SIZE_T encoded_bytes);
#endif

/* Decode. Returns the status. The decoded version is valid only if
   !mte_base_status_is_error(status).

   The decoded buffer must be of sufficient length to hold the decoded version.
   See mte_dec_buff_bytes(). */
MTE_SHARED
mte_status mte_dec_decode(MTE_HANDLE state, mte_dec_args *args);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Decode from Base64. Returns the status. The decoded version is valid only if
   !mte_base_status_is_error(status).

   The decoded buffer must be of sufficient length to hold the decoded version.
   See mte_dec_buff_bytes_b64(). */
MTE_SHARED
mte_status mte_dec_decode_b64(MTE_HANDLE state, mte_dec_args *args);
#endif

/* Uninstantiate the decoder. Returns the status. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_dec_uninstantiate(MTE_HANDLE state);

#ifdef __cplusplus
}
#endif

#endif

