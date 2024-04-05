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
#ifndef mte_wrap_base_h
#define mte_wrap_base_h

#ifndef mte_base_h
#include "mte_base.h"
#endif

/* This wraps the MTE base functions.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* The entropy input callback signature for wrappers. */
typedef mte_status (*mte_wrap_get_entropy_input)(void *context,
                                                 MTE_UINT32_T min_entropy,
                                                 MTE_UINT32_T min_length,
                                                 MTE_UINT64_T max_length,
                                                 MTE_UINT8_T **entropy_input,
                                                 MTE_UINT64_T *ei_bytes);

/* The nonce callback signature for wrappers. */
typedef void (*mte_wrap_get_nonce)(void *context,
                                   MTE_UINT32_T min_length,
                                   MTE_UINT32_T max_length,
                                   void *nonce,
                                   MTE_UINT32_T *n_bytes);

/* Returns the MTE version number as individual integer parts. */
MTE_SHARED
MTE_UINT32_T mte_wrap_base_version_major(void);
MTE_SHARED
MTE_UINT32_T mte_wrap_base_version_minor(void);
MTE_SHARED
MTE_UINT32_T mte_wrap_base_version_patch(void);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_status_count(void);

MTE_SHARED
const char *mte_wrap_base_status_name(mte_status status);

MTE_SHARED
const char *mte_wrap_base_status_description(mte_status status);

MTE_SHARED
mte_status mte_wrap_base_status_code(const char *name);

MTE_SHARED
MTE_BOOL mte_wrap_base_has_runtime_opts(void);

MTE_SHARED
mte_drbgs mte_wrap_base_default_drbg(void);

MTE_SHARED
uint32_t mte_wrap_base_default_tok_bytes(void);

MTE_SHARED
mte_verifiers mte_wrap_base_default_verifiers(void);

MTE_SHARED
mte_ciphers mte_wrap_base_default_cipher(void);

MTE_SHARED
mte_hashes mte_wrap_base_default_hash(void);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_count(void);

MTE_SHARED
const char *mte_wrap_base_drbgs_name(mte_drbgs algo);

MTE_SHARED
mte_drbgs mte_wrap_base_drbgs_algo(const char *name);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_sec_strength_bytes(mte_drbgs algo);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_personal_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_UINT64_T mte_wrap_base_drbgs_personal_max_bytes(mte_drbgs algo);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_entropy_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_UINT64_T mte_wrap_base_drbgs_entropy_max_bytes(mte_drbgs algo);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_nonce_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_UINT32_T mte_wrap_base_drbgs_nonce_max_bytes(mte_drbgs algo);

MTE_SHARED
MTE_UINT64_T mte_wrap_base_drbgs_reseed_interval(mte_drbgs algo);

MTE_SHARED
void mte_wrap_base_drbgs_incr_inst_error(MTE_BOOL flag);

MTE_SHARED
void mte_wrap_base_drbgs_incr_gen_error(MTE_BOOL flag, MTE_UINT32_T after);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_verifiers_count(void);

MTE_SHARED
const char *mte_wrap_base_verifiers_name(mte_verifiers algo);

MTE_SHARED
mte_verifiers mte_wrap_base_verifiers_algo(const char *name);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_ciphers_count(void);

MTE_SHARED
const char *mte_wrap_base_ciphers_name(mte_ciphers algo);

MTE_SHARED
mte_ciphers mte_wrap_base_ciphers_algo(const char *name);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_ciphers_block_bytes(mte_ciphers algo);

MTE_SHARED
MTE_UINT32_T mte_wrap_base_hashes_count(void);

MTE_SHARED
const char *mte_wrap_base_hashes_name(mte_hashes algo);

MTE_SHARED
mte_hashes mte_wrap_base_hashes_algo(const char *name);

#ifdef __cplusplus
}
#endif

#endif

