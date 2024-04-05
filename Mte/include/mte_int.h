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
#ifndef mte_int_h
#define mte_int_h

#ifndef mte_settings_h
#include "mte_settings.h"
#endif

#include <limits.h>
#include <stddef.h>
#include <stdint.h>

/* The xc16-gcc compiler's stdint.h has incorrect values but the compiler's
   defines are correct, so use those instead. */
#if defined(__GNUC__) && defined(__XC16__)
#  undef INTPTR_MIN
#  undef INTPTR_MAX
#  undef UINTPTR_MAX
#  undef PTRDIFF_MIN
#  undef PTRDIFF_MAX
#  undef SIZE_MAX
#  define INTPTR_MIN (-__INT_MAX__ - 1)
#  define INTPTR_MAX __INT_MAX__
#  define UINTPTR_MAX __SIZE_MAX__
#  define PTRDIFF_MIN __PTRDIFF_MIN__
#  define PTRDIFF_MAX __PTRDIFF_MAX__
#  define SIZE_MAX __SIZE_MAX__
#endif

/* Determine the register size. */
#if defined(_MSC_VER)
#  if defined(_WIN32) && !defined(_WIN64)
#    define MTE_REGBITS 32
#  elif defined(_WIN64)
#    define MTE_REGBITS 64
#  else
#    error Unknown register size.
#  endif
#elif defined(__EMSCRIPTEN__)
#  define MTE_REGBITS 32
#elif defined(__AVR__)
#  define MTE_REGBITS 8
#elif defined(__clang__) || defined(__GNUG__) || defined(__GNUC__)
#  define MTE_REGBITS (__SIZEOF_POINTER__ * 8)
#endif

/* C99 integer types. */
#define MTE_INT8_T int8_t
#define MTE_UINT8_T uint8_t
#define MTE_INT16_T int16_t
#define MTE_UINT16_T uint16_t
#define MTE_INT32_T int32_t
#define MTE_UINT32_T uint32_t
#define MTE_INT64_T int64_t
#define MTE_UINT64_T uint64_t
#define MTE_SIZE_T size_t
#define MTE_UINTMAX_T uintmax_t
#define MTE_UINTPTR_T uintptr_t

/* Boolean. */
#if MTE_REGBITS > 8
#  define MTE_BOOL int
#else
#  define MTE_BOOL MTE_INT8_T
#endif
#define MTE_TRUE 1
#define MTE_FALSE 0

/* Size type that can hold at least a given size. This is a hybrid of C99's
   "fast" and "least" types, depending on the platform. */
#if MTE_REGBITS > 8
#  define MTE_SIZE8_T MTE_SIZE_T
#else
#  define MTE_SIZE8_T MTE_UINT8_T
#endif

/* Limits for integer types. */
#define MTE_UINT16_MAX UINT16_MAX
#define MTE_UINT64_MAX UINT64_MAX
#define MTE_SIZE_MAX SIZE_MAX
#if MTE_REGBITS > 8
#  define MTE_SIZE8_MAX MTE_SIZE_MAX
#else
#  define MTE_SIZE8_MAX 255
#endif

/* Comparison result types that can hold at least a given range. This is a
   hybrid of C99's "fast" and "least" types, depending on the platform. */
#if MTE_REGBITS > 8
#  define MTE_CMP8_T int
#else
#  define MTE_CMP8_T MTE_INT8_T
#endif
#if MTE_REGBITS > 16
#  define MTE_CMP16_T int
#else
#  define MTE_CMP16_T MTE_INT16_T
#endif

/* Limits for comparison types. */
#if MTE_REGBITS > 8
#  define MTE_CMP8_MAX INT_MAX
#else
#  define MTE_CMP8_MAX INT8_MAX
#endif

/* Declare constants of a specified type. */
#if !defined(__cplusplus) || __cplusplus >= 201103L
#  define MTE_U32(x0, x1) ((UINT32_C(x0) << 16) | UINT32_C(x1))
#  define MTE_U64(x0, x1, x2, x3) ((UINT64_C(x0) << 48) | \
                                   (UINT64_C(x1) << 32) | \
                                   (UINT64_C(x2) << 16) | \
                                   UINT64_C(x3))
#else
#  define MTE_U32(x0, x1) ((uint32_t(x0 ## U) << 16) | uint32_t(x1 ## U))
#  define MTE_U64(x0, x1, x2, x3) ((uint64_t(x0 ## U) << 48) | \
                                   (uint64_t(x1 ## U) << 32) | \
                                   (uint64_t(x2 ## U) << 16) | \
                                   uint64_t(x3 ## U))
#endif
#define MTE_U32S(x) MTE_U32(0, x)
#define MTE_U64S(x) MTE_U64(0, 0, 0, x)

/* Detect large integer support. Typedef 128-bit integers if they exist. */
#if MTE_128 && defined(__SIZEOF_INT128__)
#  if defined(__GNUG__) || defined(__GNUC__)
__extension__ typedef unsigned __int128 MTE_UINT128_T;
#  else
typedef unsigned __int128 MTE_UINT128_T;
#  endif
#  define MTE_HAS_INT128 1
#else
#  define MTE_HAS_INT128 0
#endif

/* The number of bytes in the maximum alignment requirement. */
#if MTE_HAS_INT128
#  define MTE_ALIGN_BYTES 16
#elif defined(__BIGGEST_ALIGNMENT__)
#  if __BIGGEST_ALIGNMENT__ == 16
#    define MTE_ALIGN_BYTES 8
#  else
#    define MTE_ALIGN_BYTES __BIGGEST_ALIGNMENT__
#  endif
#else
#  define MTE_ALIGN_BYTES (MTE_REGBITS / 8)
#endif

/* The integer type that has the maximum alignment requirement. */
#if MTE_ALIGN_BYTES == 1
#  define MTE_ALIGNED_INT MTE_UINT8_T
#elif MTE_ALIGN_BYTES == 2
#  define MTE_ALIGNED_INT MTE_UINT16_T
#elif MTE_ALIGN_BYTES == 4
#  define MTE_ALIGNED_INT MTE_UINT32_T
#elif MTE_ALIGN_BYTES == 8
#  define MTE_ALIGNED_INT MTE_UINT64_T
#elif MTE_ALIGN_BYTES == 16
#  define MTE_ALIGNED_INT MTE_UINT128_T
#else
#  error Unknown alignment requirement.
#endif

/* The maximum amount of padding needed to align to the maximum alignment's
   type. */
#define MTE_ALIGN_PAD (MTE_ALIGN_BYTES - 1)

#endif

