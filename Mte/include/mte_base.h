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
#ifndef mte_base_h
#define mte_base_h

#ifndef mte_struct_h
#include "mte_struct.h"
#endif
#ifndef mte_settings_h
#include "mte_settings.h"
#endif
#ifndef mte_export_h
#include "mte_export.h"
#endif
#ifndef mte_int_h
#include "mte_int.h"
#endif
#ifndef mte_status_h
#include "mte_status.h"
#endif
#ifndef mte_drbg_defs_h
#include "mte_drbg_defs.h"
#endif
#ifndef mte_verifier_defs_h
#include "mte_verifier_defs.h"
#endif
#ifndef mte_drbgs_h
#include "mte_drbgs.h"
#endif
#ifndef mte_verifiers_h
#include "mte_verifiers.h"
#endif
#ifndef mte_ciphers_h
#include "mte_ciphers.h"
#endif
#ifndef mte_hashes_h
#include "mte_hashes.h"
#endif

/* This is the base of MTE. It provides common functions for the core.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Returns the MTE version number as a string. */
MTE_SHARED MTE_WASM_EXPORT
const char *mte_base_version(void);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the count of status codes. */
MTE_SHARED
MTE_SIZE8_T mte_base_status_count(void);

/* Returns the enumeration name for the given status. */
MTE_SHARED
const char *mte_base_status_name(mte_status status);

/* Returns the description for the given status. */
MTE_SHARED
const char *mte_base_status_description(mte_status status);

/* Returns the status code for the given enumeration name. */
MTE_SHARED
mte_status mte_base_status_code(const char *name);
#endif

/* Returns non-MTE_FALSE if the status code is an error; returns MTE_FALSE if
   the status code is success or a warning. */
MTE_SHARED MTE_WASM_EXPORT
MTE_BOOL mte_base_status_is_error(mte_status status);

#if !defined(MTE_BUILD_MINSIZEREL)
/* Returns the count of DRBG algorithms. */
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_count(void);

/* Returns the enumeration name for the given algorithm. */
MTE_SHARED
const char *mte_base_drbgs_name(mte_drbgs algo);

/* Returns the algorithm for the given enumeration name. */
MTE_SHARED
mte_drbgs mte_base_drbgs_algo(const char *name);

/* Returns the security strength for the given algorithm. */
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_sec_strength_bytes(mte_drbgs algo);

/* Returns the minimum/maximum personalization string size for the given
   algorithm. */
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_personal_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_SIZE_T mte_base_drbgs_personal_max_bytes(mte_drbgs algo);

/* Returns the minimum/maximum entropy size for the given algorithm. */
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_entropy_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_SIZE_T mte_base_drbgs_entropy_max_bytes(mte_drbgs algo);

/* Returns the minimum/maximum nonce size for the given algorithm. */
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_nonce_min_bytes(mte_drbgs algo);
MTE_SHARED
MTE_SIZE8_T mte_base_drbgs_nonce_max_bytes(mte_drbgs algo);

/* Returns the reseed interval for the given algorithm. */
MTE_SHARED
MTE_UINT64_T mte_base_drbgs_reseed_interval(mte_drbgs algo);

/* Set the increment DRBG to return an error during instantiation and
   uninstantiation (if MTE_TRUE) or not (if MTE_FALSE). This is useful for
   testing error handling. The flag is MTE_FALSE until set with this. */
MTE_SHARED
void mte_base_drbgs_incr_inst_error(MTE_BOOL flag);

/* Set the increment DRBG to produce an error after the given number of values
   have been generated (if flag is MTE_TRUE) or turn off errors (if flag is
   MTE_FALSE) other than the reseed error, which is always produced when the
   seed interval is reached. The flag is MTE_FALSE until set with this. */
MTE_SHARED
void mte_base_drbgs_incr_gen_error(MTE_BOOL flag, MTE_SIZE_T after);

/* Returns the count of verifier algorithms. */
MTE_SHARED
MTE_SIZE8_T mte_base_verifiers_count(void);

/* Returns the enumeration name for the given algorithm. */
MTE_SHARED
const char *mte_base_verifiers_name(mte_verifiers algo);

/* Returns the algorithm for the given name. */
MTE_SHARED
mte_verifiers mte_base_verifiers_algo(const char *name);

/* Returns the count of cipher algorithms. */
MTE_SHARED
MTE_SIZE8_T mte_base_ciphers_count(void);

/* Returns the enumeration name for the given algorithm. */
MTE_SHARED
const char *mte_base_ciphers_name(mte_ciphers algo);

/* Returns the algorithm for the given name. */
MTE_SHARED
mte_ciphers mte_base_ciphers_algo(const char *name);

/* Returns the block size for the given algorithm. */
MTE_SHARED
MTE_SIZE8_T mte_base_ciphers_block_bytes(mte_ciphers algo);

/* Returns the count of hash algorithms. */
MTE_SHARED
MTE_SIZE8_T mte_base_hashes_count(void);

/* Returns the enumeration name for the given algorithm. */
MTE_SHARED
const char *mte_base_hashes_name(mte_hashes algo);

/* Returns the algorithm for the given name. */
MTE_SHARED
mte_hashes mte_base_hashes_algo(const char *name);
#endif

#ifdef __cplusplus
}
#endif

#endif

