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
#ifndef mte_init_h
#define mte_init_h

#ifndef mte_export_h
#include "mte_export.h"
#endif
#ifndef mte_int_h
#include "mte_int.h"
#endif
#ifndef mte_init_info_h
#include "mte_init_info.h"
#endif

/* This is the initialization interface.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Call mte_init() one time before using any MTE function. If this is not
   done, the MTE library will not function and crashes may occur.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* The initialization information callback. */
typedef int (*mte_init_info_cb)(void *context, mte_init_info info);

/* Initialize MTE. Returns MTE_TRUE if successful or MTE_FALSE if not. If
   MTE_FALSE is returned, the MTE library is not usable and crashes may occur
   if MTE functions are called.

   The cb argument specifies a callback which can be provided to provide
   additional information to the initialization procedure. If NULL, default
   values will be used, which may result in less than optimal performance.
*/
MTE_SHARED MTE_WASM_EXPORT
MTE_BOOL mte_init(mte_init_info_cb cb, void *context);

#ifdef __cplusplus
}
#endif

#endif

