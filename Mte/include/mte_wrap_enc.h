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
#ifndef mte_wrap_enc_h
#define mte_wrap_enc_h

#ifndef mte_wrap_base_h
#include "mte_wrap_base.h"
#endif

/* This wraps the MTE encoder functions.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.
*/
#ifdef __cplusplus
extern "C"
{
#endif

MTE_SHARED
MTE_UINT32_T mte_wrap_enc_state_bytes(mte_drbgs drbg,
                                      MTE_UINT32_T tok_bytes,
                                      mte_verifiers verifiers);

MTE_SHARED
mte_status mte_wrap_enc_state_init(MTE_HANDLE state,
                                   mte_drbgs drbg,
                                   MTE_UINT32_T tok_bytes,
                                   mte_verifiers verifiers);

MTE_SHARED
mte_status mte_wrap_enc_instantiate(MTE_HANDLE state,
                                    mte_wrap_get_entropy_input ei_cb,
                                    void *ei_cb_context,
                                    mte_wrap_get_nonce n_cb, void *n_cb_context,
                                    const void *ps, MTE_UINT32_T ps_bytes);

MTE_SHARED
MTE_UINT32_T mte_wrap_enc_save_bytes(MTE_CHANDLE state);

MTE_SHARED
MTE_UINT32_T mte_wrap_enc_save_bytes_b64(MTE_CHANDLE state);

MTE_SHARED
mte_status mte_wrap_enc_state_save_b64(MTE_CHANDLE state, void *saved);

MTE_SHARED
mte_status mte_wrap_enc_state_restore_b64(MTE_HANDLE state, const void *saved);

MTE_SHARED
MTE_UINT32_T mte_wrap_enc_buff_bytes(MTE_CHANDLE state,
                                     MTE_UINT32_T data_bytes);

MTE_SHARED
MTE_UINT32_T mte_wrap_enc_buff_bytes_b64(MTE_CHANDLE state,
                                         MTE_UINT32_T data_bytes);

MTE_SHARED
mte_status mte_wrap_enc_encode(MTE_HANDLE state,
                               mte_verifier_get_timestamp64 t_cb,
                               void *t_cb_context,
                               const void *data, MTE_UINT32_T data_bytes,
                               void *encoded,
                               MTE_UINT32_T *encoded_off,
                               MTE_UINT32_T *encoded_bytes);

MTE_SHARED
mte_status mte_wrap_enc_encode_b64(MTE_HANDLE state,
                                   mte_verifier_get_timestamp64 t_cb,
                                   void *t_cb_context,
                                   const void *data, MTE_UINT32_T data_bytes,
                                   void *encoded,
                                   MTE_UINT32_T *encoded_off,
                                   MTE_UINT32_T *encoded_bytes);

#ifdef __cplusplus
}
#endif

#endif

