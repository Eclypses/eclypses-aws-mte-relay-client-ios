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
#ifndef mte_mke_enc_h
#define mte_mke_enc_h

#ifndef mte_base_h
#include "mte_base.h"
#endif
#ifndef mte_cipher_defs_h
#include "mte_cipher_defs.h"
#endif
#ifndef mte_hash_defs_h
#include "mte_hash_defs.h"
#endif

/* This is the Managed-Key Encryption add-on message encoder.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Notes:
   1. All allocations can be static or dynamic. If dynamic, it is up to the
      caller to free it when done. This library does not allocate or deallocate
      any memory.
   2. A buffer must stay in scope while the call refers to it.
   3. All buffers are reusable and need only be allocated once.

   To create an encoder:
   1. Allocate the encoder state buffer of length mte_mke_enc_state_bytes().
   2. Initialize the encoder state with mte_mke_enc_state_init().
   3. Instantiate the encoder with mte_mke_enc_instantiate().

   To save/restore an encoder:
   1. Allocate a buffer of length:
      a. mte_mke_enc_save_bytes() [raw]
      b. mte_mke_enc_save_bytes_b64() [Base64-encoded]
      to hold the saved state.
   2. Save the state with:
      a. mte_mke_enc_state_save() [raw]
      b. mte_mke_enc_state_save_b64() [Base64-encoded]
   3. Restore the state with:
      a. mte_mke_enc_state_restore() [raw]
      b. mte_mke_enc_state_restore_b64() [Base64-encoded]

   To use an encoder:
   1. Allocate the encode buffer of at least length:
      a. mte_mke_enc_buff_bytes() [raw]
      b. mte_mke_enc_buff_bytes_b64() [Base64-encoded]
      where data_bytes is the byte length of the data to encode.
   2. Encode each message with:
      a. mte_mke_enc_encode() [raw]
      b. mte_mke_enc_encode_b64() [Base64-encoded]
      where encoded_bytes will be set to the encoded length. Exactly this length
      must be given to the decoder to decode successfully.

   To use as a chunk-based encoder:
   1. Allocate the chunk-based encryption state of at least length
      mte_mke_enc_encrypt_state_bytes().
   2. Call mte_mke_enc_encrypt_start() to start the chunk-based session.
   3. Call mte_mke_enc_encrypt_chunk() repeatedly to encrypt each chunk of data.
   4. Call mte_mke_enc_encrypt_finish().
   The results from steps 3-4, concatenated in order, form the full result. The
   result must be given to the chunk-based decoder to restore. The total size
   of the full result is the sum of the sizes given to steps 3 and 4; you can
   use mte_mke_enc_encrypt_finish_bytes() to get the size of step 4 before
   actually doing step 4 if needed.

   To destroy an encoder:
   1. Call mte_mke_enc_uninstantiate(). This will zero the state of the encoder
      for security. The encoder must either be instantiated again or restored to
      be usable.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Initialization information. */
typedef struct mte_mke_enc_init_info_
{
  /* Encoder parameters. */
  mte_encoder_params enc_params;

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
} mte_mke_enc_init_info;

/* Initializer for an encoder init info structure.

   d = drbg
   t = tok_bytes
   v = verifiers
   c = cipher
   h = hash
   ds = drbg_state
   di = drbg_info
   cs = cipher_state
   ci = cipher_info
   hs = hash_state
   hi = hash_info
*/
#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
#  if MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi) \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                       \
                            (c), (h), (cs), (ci), (hs), (hi) }
#  elif MTE_CIPHER_EXTERNAL && !MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi) \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                       \
                            (c), (h), (cs), ((void)(hs), (void)(hi), (ci)) }
#  elif !MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi) \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                       \
                            (c), (h), (hs), ((void)(cs), (void)(ci), (hi)) }
#  else
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi)  \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                        \
                  (c), ((void)(cs), (void)(ci), (void)(hs), (void)(hi), (h)) }
#  endif
#else
#  if MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi) \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                       \
                            (cs), (ci), (hs), ((void)(c), (void)(h), (hi)) }
#  elif MTE_CIPHER_EXTERNAL && !MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi)  \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                        \
                  (cs), ((void)(c), (void)(h), (void)(hs), (void)(hi), (ci)) }
#  elif !MTE_CIPHER_EXTERNAL && MTE_HASH_EXTERNAL
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi)  \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)),                        \
                  (hs), ((void)(c), (void)(h), (void)(cs), (void)(ci), (hi)) }
#  else
#    define MTE_MKE_ENC_INIT_INFO_INIT(d, t, v, c, h, ds, di, cs, ci, hs, hi) \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds),                              \
    ((void)(c), (void)(h), (void)(cs), (void)(ci), (void)(hs), (void)(hi),    \
                            (di))) }
#  endif
#endif

/* Returns the encoder state size. Returns 0 if the combination is not usable.
   Use mte_drbgs_none for the drbg member if providing your own DRBG. Use
   mte_ciphers_none for the cipher member if providing your own cipher. Use
   mte_hashes_none for the hash member if providing your own hash. */
MTE_SHARED
MTE_SIZE_T mte_mke_enc_state_bytes(const mte_mke_enc_init_info *info);

/* Initialize the encoder state. Returns the status.

   The state buffer must be of sufficient length to hold the encoder state. See
   mte_mke_enc_state_bytes(). */
MTE_SHARED
mte_status mte_mke_enc_state_init(MTE_HANDLE state,
                                  const mte_mke_enc_init_info *info);

/* Instantiate the encoder. Returns the status. */
MTE_SHARED
mte_status mte_mke_enc_instantiate(MTE_HANDLE state,
                                   const mte_drbg_inst_info *info);

/* Returns the reseed counter. */
MTE_SHARED
MTE_UINT64_T mte_mke_enc_reseed_counter(MTE_CHANDLE state);

/* Returns the state save size [raw]. Returns 0 if save is unsupported. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_enc_save_bytes(MTE_CHANDLE state);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the state save size [Base64-encoded]. Returns 0 if save is
   unsupported. */
MTE_SHARED
MTE_SIZE_T mte_mke_enc_save_bytes_b64(MTE_CHANDLE state);
#endif

/* Save the encoder state to the given buffer in raw form. The size of the
   buffer must be mte_mke_enc_save_bytes() and that is the length of the raw
   saved state. Returns mte_status_unsupported if not supported; otherwise
   returns mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_enc_state_save(MTE_CHANDLE state, void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Save the encoder state to the given buffer encoded in Base64. The size of
   the buffer must be mte_mke_enc_save_bytes_b64() and the result is null-
   terminated. Returns mte_status_unsupported if not supported; otherwise
   returns mte_status_success. */
MTE_SHARED
mte_status mte_mke_enc_state_save_b64(MTE_CHANDLE state, void *saved);
#endif

/* Restore the encoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_enc_state_restore(MTE_HANDLE state, const void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Restore the encoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_mke_enc_state_restore_b64(MTE_HANDLE state, const void *saved);
#endif

/* Returns the encode buffer size [raw] in bytes given the data length in bytes.
   The encode buffer provided to mte_mke_enc_encode() must be of at least this
   length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_enc_buff_bytes(MTE_CHANDLE state, MTE_SIZE_T data_bytes);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the encode buffer size [Base64-encoded] in bytes given the data
   length in bytes. The encode buffer provided to mte_mke_enc_encode_b64() must
   be of at least this length. */
MTE_SHARED
MTE_SIZE_T mte_mke_enc_buff_bytes_b64(MTE_CHANDLE state, MTE_SIZE_T data_bytes);
#endif

/* Encode. Returns the status. The encoded version is valid only if
   mte_status_success is returned.

   The encoded buffer must be of sufficient length to hold the encoded version.
   See mte_mke_enc_buff_bytes(). */
MTE_SHARED
mte_status mte_mke_enc_encode(MTE_HANDLE state, mte_enc_args *args);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Encode in Base64. Returns the status. The encoded version is valid only if
   mte_status_success is returned.

   The encoded buffer must be of sufficient length to hold the encoded version.
   See mte_mke_enc_buff_bytes_b64(). */
MTE_SHARED
mte_status mte_mke_enc_encode_b64(MTE_HANDLE state, mte_enc_args *args);
#endif

/* Returns the length of the result mte_mke_enc_encrypt_finish() will produce.
   Use this if you need to know that size before you can call it. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_enc_encrypt_finish_bytes(MTE_CHANDLE state);

/* Returns the chunk-based encryption state size in bytes. The c_state buffer
   provided to the mte_mke_enc_encrypt_*() functions must be of at least this
   length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_mke_enc_encrypt_state_bytes(MTE_CHANDLE state);

/* Start a chunk-based encryption session. Returns the status. Initializes the
   state to the c_state buffer. This state is used by the other chunk-based
   functions.

   The c_state buffer must be of sufficient length. See
   mte_mke_enc_encrypt_state_bytes(). */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_enc_encrypt_start(MTE_HANDLE state, MTE_HANDLE c_state);

/* Encrypt a chunk of data in a chunk-based encryption session. The bytes must
   be a multiple of the cipher block size being used. This means you must
   either choose a cipher with block size of 1 or perform your own padding.
   Returns the status.

   The encoded buffer must be at least bytes in length to hold the encrypted
   version. The encoded buffer may be the same as the data buffer to overwrite
   the data with the encrypted version. The encrypted version length is
   bytes. */
MTE_SHARED
mte_status mte_mke_enc_encrypt_chunk(MTE_HANDLE state, MTE_HANDLE c_state,
                                     mte_enc_args *args);

/* Finish the chunk-based encryption session. Returns the status. Writes the
   final part of the result to the c_state buffer and sets encoded to point at
   the offset in the c_state buffer and sets bytes to the length of this
   part of the result. The c_state is no longer usable for a chunk-based
   encryption session until mte_mke_enc_encrypt_start() is called. */
MTE_SHARED
mte_status mte_mke_enc_encrypt_finish(MTE_HANDLE state, MTE_HANDLE c_state,
                                      mte_enc_args *args);

/* Uninstantiate the encoder. Returns the status. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_mke_enc_uninstantiate(MTE_HANDLE state);

#ifdef __cplusplus
}
#endif

#endif

