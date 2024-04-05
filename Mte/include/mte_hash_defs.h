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
#ifndef mte_hash_defs_h
#define mte_hash_defs_h

#ifndef mte_int_h
#include "mte_int.h"
#endif
#ifndef mte_status_h
#include "mte_status.h"
#endif

/* This has common hash definitions. */
#ifdef __cplusplus
extern "C"
{
#endif

/* The hash calculation function. The state pointer is simply passed through
   from the function that calls the callback. The data and length in bytes
   thereof must be hashed, with the result placed somewhere that will remain in
   scope. A pointer to the digest must be returned or NULL on error. */
typedef const void *(*mte_hash_calc)(void *state,
                                     const void *data,
                                     MTE_SIZE_T bytes);

/* Start a hash calculation. The state pointer is simply passed through from
   the function that calls the callback. */
typedef void (*mte_hash_start)(void *state);

/* Feed data to the hash calculation. The state pointer is simply passed
   through from the function that calls the callback. The data and length in
   bytes thereof must be fed to the hash calculation. The status is returned. */
typedef mte_status (*mte_hash_feed)(void *state,
                                    const void *data,
                                    MTE_SIZE_T bytes);

/* Finish a hash calculation. The state pointer is simply passed through
   from the function that calls the callback. The result must be placed
   somewhere that will remain in scope. A pointer to the digest must be
   returned or NULL on error. */
typedef const void *(*mte_hash_finish)(void *state);

/* Hash info. */
typedef struct mte_hash_info_
{
  /* State size. */
  MTE_SIZE8_T state_bytes;

  /* Digest size. */
  MTE_SIZE8_T digest_bytes;

  /* Callbacks. */
  mte_hash_calc calc;
  mte_hash_start start;
  mte_hash_feed feed;
  mte_hash_finish finish;
} mte_hash_info;

#ifdef __cplusplus
}
#endif

#endif

