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
#ifndef mte_enc_h
#define mte_enc_h

#ifndef mte_base_h
#include "mte_base.h"
#endif

/* This is a message encoder.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Notes:
   1. All allocations can be static or dynamic. If dynamic, it is up to the
      caller to free it when done. This library does not allocate or deallocate
      any memory.
   2. A buffer must stay in scope while the call refers to it.
   3. All buffers are reusable and need only be allocated once.

   To create an encoder:
   1. Allocate the encoder state buffer of length mte_enc_state_bytes().
   2. Initialize the encoder state with mte_enc_state_init().
   3. Instantiate the encoder with mte_enc_instantiate().

   To save/restore an encoder:
   1. Allocate a buffer of length:
      a. mte_enc_save_bytes() [raw]
      b. mte_enc_save_bytes_b64() [Base64-encoded]
      to hold the saved state.
   2. Save the state with:
      a. mte_enc_state_save() [raw]
      b. mte_enc_state_save_b64() [Base64-encoded]
   3. Restore the state with:
      a. mte_enc_state_restore() [raw]
      b. mte_enc_state_restore_b64() [Base64-encoded]

   To use an encoder:
   1. Allocate the encode buffer of at least length:
      a. mte_enc_buff_bytes() [raw]
      b. mte_enc_buff_bytes_b64() [Base64-encoded]
      where data_bytes is the byte length of the data to encode.
   2. Encode each message with:
      a. mte_enc_encode() [raw]
      b. mte_enc_encode_b64() [Base64-encoded]
      where encoded_bytes will be set to the encoded length. Exactly this length
      must be given to the decoder to decode successfully.

   To destroy an encoder:
   1. Call mte_enc_uninstantiate(). This will zero the state of the encoder for
      security. The encoder must either be instantiated again or restored to
      be usable.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Initialization information. */
typedef struct mte_enc_init_info_
{
  /* Encoder parameters. */
  mte_encoder_params enc_params;
} mte_enc_init_info;

/* Initializer for an encoder init info structure.

   d = drbg
   t = tok_bytes
   v = verifiers
   ds = drbg_state
   di = drbg_info
*/
#define MTE_ENC_INIT_INFO_INIT(d, t, v, ds, di)          \
  { MTE_ENCODER_PARAMS_INIT((d), (t), (v), (ds), (di)) }

/* Returns the encoder state size. Returns 0 if the combination is not usable.
   Use mte_drbgs_none for the drbg member if providing your own DRBG. */
MTE_SHARED
MTE_SIZE_T mte_enc_state_bytes(const mte_enc_init_info *info);

/* Initialize the encoder state. Returns the status.

   The state buffer must be of sufficient length to hold the encoder state. See
   mte_enc_state_bytes(). */
MTE_SHARED
mte_status mte_enc_state_init(MTE_HANDLE state, const mte_enc_init_info *info);

/* Instantiate the encoder. Returns the status. */
MTE_SHARED
mte_status mte_enc_instantiate(MTE_HANDLE state,
                               const mte_drbg_inst_info *info);

/* Returns the reseed counter. */
MTE_SHARED
MTE_UINT64_T mte_enc_reseed_counter(MTE_CHANDLE state);

/* Returns the state save size [raw]. Returns 0 if save is unsupported. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_enc_save_bytes(MTE_CHANDLE state);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the state save size [Base64-encoded]. Returns 0 if save is
   unsupported. */
MTE_SHARED
MTE_SIZE_T mte_enc_save_bytes_b64(MTE_CHANDLE state);
#endif

/* Save the encoder state to the given buffer in raw form. The size of the
   buffer must be mte_enc_save_bytes() and that is the length of the raw saved
   state. Returns mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_enc_state_save(MTE_CHANDLE state, void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Save the encoder state to the given buffer encoded in Base64. The size of the
   buffer must be mte_enc_save_bytes_b64() and the result is null-terminated.
   Returns mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_enc_state_save_b64(MTE_CHANDLE state, void *saved);
#endif

/* Restore the encoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_enc_state_restore(MTE_HANDLE state, const void *saved);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Restore the encoder state from the given buffer in raw form. Returns
   mte_status_unsupported if not supported; otherwise returns
   mte_status_success. */
MTE_SHARED
mte_status mte_enc_state_restore_b64(MTE_HANDLE state, const void *saved);
#endif

/* Returns the encode buffer size [raw] in bytes given the data length in bytes.
   The encode buffer provided to mte_enc_encode() must be of at least this
   length. */
MTE_SHARED MTE_WASM_EXPORT
MTE_SIZE_T mte_enc_buff_bytes(MTE_CHANDLE state, MTE_SIZE_T data_bytes);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the encode buffer size [Base64-encoded] in bytes given the token
   size in bytes, verifiers algorithm, and data length in bytes. The encode
   buffer provided to mte_enc_encode_b64() must be of at least this length. */
MTE_SHARED
MTE_SIZE_T mte_enc_buff_bytes_b64(MTE_CHANDLE state, MTE_SIZE_T data_bytes);
#endif

/* Encode. Returns the status. The encoded version is valid only if
   mte_status_success is returned.

   The encoded buffer must be of sufficient length to hold the encoded version.
   See mte_enc_buff_bytes(). */
MTE_SHARED
mte_status mte_enc_encode(MTE_HANDLE state, mte_enc_args *args);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Encode in Base64. Returns the status. The encoded version is valid only if
   mte_status_success is returned.

   The encoded buffer must be of sufficient length to hold the encoded version.
   See mte_enc_buff_bytes_b64(). */
MTE_SHARED
mte_status mte_enc_encode_b64(MTE_HANDLE state, mte_enc_args *args);
#endif

/* Uninstantiate the encoder. Returns the status. */
MTE_SHARED MTE_WASM_EXPORT
mte_status mte_enc_uninstantiate(MTE_HANDLE state);

#ifdef __cplusplus
}
#endif

#endif

