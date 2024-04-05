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
#ifndef mte_mke_dec_h
#define mte_mke_dec_h

#ifndef mte_base_h
#include "mte_base.h"
#endif
#ifndef mte_cipher_defs_h
#include "mte_cipher_defs.h"
#endif
#ifndef mte_hash_defs_h
#include "mte_hash_defs.h"
#endif

/* This is the Managed-Key Encryption add-on message decoder.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Notes:
   1. All allocations can be static or dynamic. If dynamic, it is up to the
      caller to free it when done. This library does not allocate or deallocate
      any memory.
   2. A buffer must stay in scope while the call refers to it.
   3. All buffers are reusable and need only be allocated once.

   To create a decoder:
   1. Allocate the decoder state buffer of length mte_mke_dec_state_bytes().
   2. Initialize the decoder state with mte_mke_dec_state_init().
   3. Instantiate the decoder with mte_mke_dec_instantiate().

   To save/restore a decoder:
   1. Allocate a buffer of length:
      a. mte_mke_dec_save_bytes() [raw]
      b. mte_mke_dec_save_bytes_b64() [Base64-encoded]
      to hold the saved state.
   2. Save the state with:
      a. mte_mke_dec_state_save() [raw]
      b. mte_mke_dec_state_save_b64() [Base64-encoded]
   3. Restore the state with:
      a. mte_mke_dec_state_restore() [raw]
      b. mte_mke_dec_state_restore_b64() [Base64-encoded]

   To use a decoder:
   1. Allocate the decode buffer of at least length:
      a. mte_mke_dec_buff_bytes() [raw]
      b. mte_mke_dec_buff_bytes_b64() [Base64-encoded]
      where encoded_bytes is the byte length of the encoded data.
   2. Decode each message with:
      a. mte_mke_dec_decode() [raw]
      b. mte_mke_dec_decode_b64() [Base64-encoded]
      where decoded_bytes will be set to the decoded length.
   3. The encode timestamp is retrieved with mte_mke_dec_enc_ts().
   4. The decode timestamp is retrieved with mte_mke_dec_dec_ts().
   5. The number of messages skipped is retrieved with
      mte_mke_dec_msg_skipped().

   To use as a chunk-based decryptor:
   1. Allocate the chunk-based decryption state of at least length
      mte_mke_dec_decrypt_state_bytes().
   2. Call mte_mke_dec_decrypt_start() to start the chunk-based session.
   3. Call mte_mke_dec_decrypt_chunk() repeatedly to decrypt each chunk of data.
   4. Call mte_mke_dec_decrypt_finish().
   The results from step 3-4, concatenated in order, form the full result. Only
   chunk-encrypted data can be decrypted since this is intended for large
   data. The sequencing verifier is not supported for chunk-based decryption.

   To destroy a decoder:
   1. Call mte_mke_dec_uninstantiate(). This will zero the state of the decoder
      for security. The decoder must either be instantiated again or restored to
      be usable.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Initialization information. */
typedef struct mte_mke_dec_init_info_
{
  /* Decoder parameters. */
  mte_decoder_params dec_params;

#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
  /* The cipher algorithm. */
  mte_ciphers cipher;

  /* The hash algorithm. */
  mte_hashes hash;
#endif

#if MTE_CIPHER_EXTERNAL
  /* The cipher state if cipher is set to mte_ciphers_none. The state must
     remain valid while using the encoder. */
  void *cipher_state;

  /* The cipher info if cipher is set to mte_ciphers_none. The info must remain
     valid while using the encoder. */
  const mte_cipher_info *cipher_info;
#endif

#if MTE_HASH_EXTERNAL
  /* The hash state if hash is set to mte_hashes_none. The state must remain
     valid while using the encoder. */
  void *hash_state;

  /* The hash info if hash is set to mte_hashes_none. The info must remain valid
     while using the encoder. */
  const mte_hash_info *hash_info;
#endif
} mte_mke_dec_init_info;

/* Initializer for a decoder init info structure. */
#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
#  if MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,       \
                                       ds, di, cs, ci, hs, hi)      \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)), \
                            (c), (h), (cs), (ci), (hs), (hi) }
#  elif MTE_CIPHER_EXTERNAL && !MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                \
                                       ds, di, cs, ci, hs, hi)               \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),          \
                            (c), (h), (cs), ((void)(hs), (void)(hi), (ci)) }
#  elif !MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                \
                                       ds, di, cs, ci, hs, hi)               \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),          \
                            (c), (h), (hs), ((void)(cs), (void)(ci), (hi)) }
#  else
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                  \
                                       ds, di, cs, ci, hs, hi)                 \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),            \
                  (c), ((void)(cs), (void)(ci), (void)(hs), (void)(hi), (h)) }
#  endif
#else
#  if MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                \
                                       ds, di, cs, ci, hs, hi)               \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),          \
                            (cs), (ci), (hs), ((void)(c), (void)(h), (hi)) }
#  elif MTE_CIPHER_EXTERNAL && !MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                  \
                                       ds, di, cs, ci, hs, hi)                 \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),            \
                  (cs), ((void)(c), (void)(h), (void)(hs), (void)(hi), (ci)) }
#  elif !MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,                  \
                                       ds, di, cs, ci, hs, hi)                 \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds), (di)),            \
                  (hs), ((void)(c), (void)(h), (void)(cs), (void)(ci), (hi)) }
#  else
#    define MTE_MKE_DEC_INIT_INFO_INIT(d, t, v, c, h, tw, sw,              \
                                       ds, di, cs, ci, hs, hi)             \
  { MTE_DECODER_PARAMS_INIT((d), (t), (v), (tw), (sw), (ds),               \
    ((void)(c), (void)(h), (void)(cs), (void)(ci), (void)(hs), (void)(hi), \
                            (di))) }
#  endif
#endif

/* Returns the decoder state size. Returns 0 if the combination is not usable.
   Use mte_drbgs_none for the drbg member if providing your own DRBG. Use
   mte_ciphers_none for the cipher member if providing your own cipher. Use
   mte_hashes_none for the hash member if providing your own hash. */
MTE_SHARED
MTE_SIZE_T mte_mke_dec_state_bytes(const mte_mke_dec_init_info *info);

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
   mte_mke_dec_state_bytes(). */
MTE_SHARED
mte_status mte_mke_dec_state_init(MTE_HANDLE state,
                                  const mte_mke_dec_init_info *info);

/* Instantiate the decoder. Returns the status. */
MTE_SHARED
mte_status mte_mke_dec_instantiate(MTE_HANDLE state,
                                   const mte_drbg_inst_info *info);

/* Returns the reseed counter. */
MTE_SHARED
MTE_UINT64_T mte_mke_dec_reseed_counter(MTE_CHANDLE state);

/* Returns the state save size [raw]. Returns 0 if save is unsupported. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_dec_save_bytes(MTE_CHANDLE state);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the state save size [Base64-encoded]. Returns 0 if save is
   unsupported. */
MTE_SHARED
MTE_SIZE_T mte_mke_dec_save_bytes_b64(MTE_CHANDLE state);
#endif

/* Save the decoder state to the given buffer in raw form. The size of the
   buffer must be mte_mke_dec_save_bytes() and that is the length of the raw
   saved state. Returns mte_status_unsupported if not supported; otherwise
   returns mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_dec_state_save(MTE_CHANDLE state, void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Save the decoder state to the given buffer encoded in Base64. The size of
   the buffer must be mte_mke_dec_save_bytes_b64() and the result is null-
   terminated. Returns mte_status_unsupported if not supported; otherwise
   returns mte_status_success. */
MTE_SHARED
mte_status mte_mke_dec_state_save_b64(MTE_CHANDLE state, void *saved);
#endif

/* Restore the decoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_dec_state_restore(MTE_HANDLE state, const void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Restore the decoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_mke_dec_state_restore_b64(MTE_HANDLE state, const void *saved);
#endif

/* Returns the decode buffer size [raw] in bytes given the encoded length in
   bytes. Returns 0 if the input is invalid. The decode buffer provided to
   mte_mke_dec_decode() must be of at least this length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_dec_buff_bytes(MTE_CHANDLE state, MTE_SIZE_T encoded_bytes);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the decode buffer size [Base64-encoded] in bytes given the encoded
   length in bytes. The decode buffer provided to mte_mke_dec_decode_b64() must
   be of at least this length. */
MTE_SHARED
MTE_SIZE_T mte_mke_dec_buff_bytes_b64(MTE_CHANDLE state,
                                      MTE_SIZE_T encoded_bytes);
#endif

/* Decode. Returns the status. The decoded version is valid only if
   !mte_base_status_is_error(status).

   The decoded buffer must be of sufficient length to hold the decoded version.
   See mte_mke_dec_buff_bytes(). */
MTE_SHARED
mte_status mte_mke_dec_decode(MTE_HANDLE state, mte_dec_args *args);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Decode from Base64. Returns the status. The decoded version is valid only if
   !mte_base_status_is_error(status).

   The decoded buffer must be of sufficient length to hold the decoded version.
   See mte_mke_dec_buff_bytes(). */
MTE_SHARED
mte_status mte_mke_dec_decode_b64(MTE_HANDLE state, mte_dec_args *args);
#endif

/* Returns the chunk-based decryption state size in bytes. The c_state buffer
   provided to the mte_mke_dec_decrypt_*() functions must be of at least this
   length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_dec_decrypt_state_bytes(MTE_CHANDLE state);

/* Start a chunk-based decryption session. Returns the status. Initializes the
   state to the c_state buffer. This state is used by the other chunk-based
   functions.

   The c_state buffer must be of sufficient length. See
   mte_mke_dec_decrypt_state_bytes(). */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_dec_decrypt_start(MTE_HANDLE state, MTE_HANDLE c_state);

/* Decrypt a chunk of data in a chunk-based decryption session. The encrypted
   data of length bytes is used as input and some decrypted data is written to
   the decoded buffer and bytes is set to the amount of decrypted data written.
   The amount decrypted may be less than the input size. Returns the status.

   The decoded buffer must be at least bytes plus the cipher block size bytes
   in length to hold the decrypted version. The decoded buffer cannot overlap
   the encrypted buffer. */
MTE_SHARED
mte_status mte_mke_dec_decrypt_chunk(MTE_HANDLE state, MTE_HANDLE c_state,
                                     mte_dec_args *args);

/* Finish the chunk-based decryption session. Returns the status. Writes the
   final decrypted data to the c_state buffer and sets decoded to the offset in
   the c_state buffer of the final decrypted data and sets bytes to the length
   of the final part of the decrypted data. The c_state is no longer usable for
   a chunk-based decryption session until mte_mke_dec_decrypt_start() is
   called. */
MTE_SHARED
mte_status mte_mke_dec_decrypt_finish(MTE_HANDLE state, MTE_HANDLE c_state,
                                      mte_dec_args *args);

/* Uninstantiate the decoder. Returns the status. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_dec_uninstantiate(MTE_HANDLE state);

#ifdef __cplusplus
}
#endif

#endif

