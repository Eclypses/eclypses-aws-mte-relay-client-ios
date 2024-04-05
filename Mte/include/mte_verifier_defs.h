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
#ifndef mte_verifier_defs_h
#define mte_verifier_defs_h

#ifndef mte_int_h
#include "mte_int.h"
#endif

/* This has common verifier definitions. */
#ifdef __cplusplus
extern "C"
{
#endif

/* A length of data for the DRBG to generate and the buffer to generate to. */
typedef struct mte_verifier_drbg_gen_
{
  MTE_SIZE_T bytes;
  void *buffer;
} mte_verifier_drbg_gen;

/* Return a 64-bit timestamp. The context pointer is simply passed through from
   the function that calls the callback.*/
typedef MTE_UINT64_T (*mte_verifier_get_timestamp64)(void *context);

#ifdef __cplusplus
}
#endif

#endif

