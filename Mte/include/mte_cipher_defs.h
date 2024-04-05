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
#ifndef mte_cipher_defs_h
#define mte_cipher_defs_h

#ifndef mte_int_h
#include "mte_int.h"
#endif
#ifndef mte_status_h
#include "mte_status.h"
#endif

/* This has common cipher definitions. */
#ifdef __cplusplus
extern "C"
{
#endif

/* The cipher key function. The state pointer is simply passed through from
   the function that calls the callback. The key is of the required length for
   the cipher. */
typedef void (*mte_cipher_key)(void *state, const void *key);

/* The cipher encrypt/decrypt function. The state pointer is simply passed
   through from the function that calls the callback. The input of length bytes
   must be encrypted or decrypted and written to output, which must have at
   least bytes length. The input and output buffers can be the same as long as
   output is less than or equal to input. The status is returned. */
typedef mte_status (*mte_cipher_enc_dec)(void *state,
                                         const void *input, MTE_SIZE_T bytes,
                                         void *output);

/* The cipher uninitialization function. The state pointer is simply passed
   through from the function that calls the callback. */
typedef void (*mte_cipher_uninit)(void *state);

/* Cipher info. */
typedef struct mte_cipher_info_
{
  /* State size. */
  MTE_SIZE_T state_bytes;

  /* Key size. */
  MTE_SIZE8_T key_bytes;

  /* Block size. */
  MTE_SIZE8_T block_bytes;

  /* Callbacks. */
  mte_cipher_key enc_key;
  mte_cipher_key dec_key;
  mte_cipher_enc_dec encrypt;
  mte_cipher_enc_dec decrypt;
  mte_cipher_uninit uninit;
} mte_cipher_info;

#ifdef __cplusplus
}
#endif

#endif

