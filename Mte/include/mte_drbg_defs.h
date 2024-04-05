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
#ifndef mte_drbg_defs_h
#define mte_drbg_defs_h

#ifndef mte_int_h
#include "mte_int.h"
#endif
#ifndef mte_status_h
#include "mte_status.h"
#endif

/* This has common DRBG definitions. */
#ifdef __cplusplus
extern "C"
{
#endif

/* Entropy input callback info structure. See the entropy input callback
   typedef for the meaning of the fields. */
typedef struct mte_drbg_ei_info_
{
  /* Minimum entropy in bytes. */
  MTE_SIZE8_T min_entropy;

  /* Minimum/maximum entropy input array length in bytes. */
  MTE_SIZE8_T min_length;
  MTE_SIZE_T max_length;

  /* Entropy input buffer. */
  MTE_UINT8_T *buff;

  /* Entropy length in bytes. */
  MTE_SIZE_T bytes;
} mte_drbg_ei_info;

/* The Get_entropy_input() function. NIST SP 800-90A section 9. Prediction
   resistance is not supported. The sizes are all specified in bytes, not bits.
   The info->buff pointer will point at a buffer of at least info->min_length
   bytes. When called, info->bytes will be set to the actual buffer length that
   info->buff points to. The function must do the following:
   - If info->min_length entropy cannot be generated, return a catastrophic
     error.
   - If at least info->min_length and no more than info->bytes entropy is
     generated, fill in the info->entropy_input, set info->bytes to the
     actual entropy length, and return success.
   - If more than info->bytes of entropy is generated, set info->buff to your
     buffer of entropy, set info->bytes to the actual entropy length, and
     return success.
   - It is also acceptable to set info->buff to your buffer even if it is less
     than or equal to info->bytes instead of copying to the provided buffer.
   The context pointer is simply passed through from the function that calls
   the callback. */
typedef mte_status (*mte_drbg_get_entropy_input)(void *context,
                                                 mte_drbg_ei_info *info);

/* Nonce callback info structure. See the nonce callback typedef for the
   meaning of the fields. */
typedef struct mte_drbg_nonce_info_
{
  /* Minimum/maximum nonce array length in bytes. */
  MTE_SIZE8_T min_length;
  MTE_SIZE8_T max_length;

  /* Nonce buffer. */
  MTE_UINT8_T *buff;

  /* Nonce length in bytes. */
  MTE_SIZE8_T bytes;
} mte_drbg_nonce_info;

/* Get a nonce of at least info->min_length and no more than info->max_length
   bytes. The info->buff pointer will point at a buffer of at least
   info->max_length bytes. The function must fill in the info->buff and set
   info->bytes to the actual nonce length in bytes. The context pointer is
   simply passed through from the function that calls the callback. */
typedef void (*mte_drbg_get_nonce)(void *context, mte_drbg_nonce_info *info);

/* Instantiate info structure. */
typedef struct mte_drbg_inst_info_
{
  /* Entropy input callback and context. */
  mte_drbg_get_entropy_input ei_cb;
  void *ei_cb_context;

  /* Nonce callback and context. */
  mte_drbg_get_nonce n_cb;
  void *n_cb_context;

  /* Personalization string and length in bytes. */
  const void *ps;
  MTE_SIZE_T ps_bytes;
} mte_drbg_inst_info;

/* Set the personalization string and length. */
#define MTE_SET_PERSONALIZATION(info, p, pb) \
  (info).ps = (p);                           \
  (info).ps_bytes = (pb)

/* Instantiate the DRBG given the entropy input callback/context, nonce
   callback/context, personalization string and length of the personalization
   string in bytes. Returns the status. */
typedef mte_status (*mte_drbg_instantiate)(void *state,
                                           const mte_drbg_inst_info *info);

/* Returns the current reseed counter value. */
typedef MTE_UINT64_T (*mte_drbg_reseed_counter)(const void *state);

/* Save the DRBG state to the given buffer. */
typedef void (*mte_drbg_state_save)(const void *state, void *saved);

/* Restore the DRBG state from the given buffer. */
typedef void (*mte_drbg_state_restore)(void *state, const void *saved);

/* Generate a random number of the requested length in bytes, placing it in the
   random_number buffer. Returns the status. */
typedef mte_status (*mte_drbg_generate)(void *state,
                                        MTE_SIZE_T requested_number_of_bytes,
                                        void *random_number);

/* Uninstantiate the DRBG. Returns the status. */
typedef mte_status (*mte_drbg_uninstantiate)(void *state);

/* DRBG info. */
typedef struct mte_drbg_info_
{
  /* State size. */
  MTE_SIZE8_T state_bytes;

  /* Save size. */
  MTE_SIZE8_T save_bytes;

  /* Security strength. */
  MTE_SIZE8_T sec_strength_bytes;

  /* Minimum/maximum personalization string size. */
  MTE_SIZE8_T personal_min_bytes;
  MTE_SIZE_T personal_max_bytes;

  /* Minimum/maximum entropy size. */
  MTE_SIZE8_T entropy_min_bytes;
  MTE_SIZE_T entropy_max_bytes;

  /* Minimum/maximum nonce size. */
  MTE_SIZE8_T nonce_min_bytes;
  MTE_SIZE8_T nonce_max_bytes;

  /* Reseed interval. */
  MTE_UINT64_T reseed_interval;

  /* Callbacks. */
  mte_drbg_instantiate instantiate;
  mte_drbg_reseed_counter reseed_counter;
  mte_drbg_state_save state_save;
  mte_drbg_state_restore state_restore;
  mte_drbg_generate generate;
  mte_drbg_uninstantiate uninstantiate;
} mte_drbg_info;

#ifdef __cplusplus
}
#endif

#endif

