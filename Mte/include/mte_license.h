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
#ifndef mte_license_h
#define mte_license_h

#ifndef mte_export_h
#include "mte_export.h"
#endif
#ifndef mte_int_h
#include "mte_int.h"
#endif

/* This is the licensing interface.

   To use with a dynamic library, compile with MTE_BUILD_SHARED defined.

   Call mte_license_init() one time before using any MTE function.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Initialize with the company name and license code. Returns MTE_TRUE if
   successful or MTE_FALSE if not. If MTE_TRUE is returned, MTE functions are
   usable; otherwise functions that return a status will return an error
   status. */
MTE_SHARED MTE_WASM_EXPORT
MTE_BOOL mte_license_init(const char *company, const char *license);

#ifdef __cplusplus
}
#endif

#endif

