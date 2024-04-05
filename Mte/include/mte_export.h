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
#ifndef mte_export_h
#define mte_export_h

#if defined(_WIN32)
/* Define DLL import/export. */
#  define MTE_IMPORT __declspec(dllimport)
#  define MTE_EXPORT __declspec(dllexport)
#else
/* Define exports. */
#  define MTE_IMPORT
#  define MTE_EXPORT __attribute__((visibility("default")))
#endif

/* If shared library support is defined, define the sharing mode. */
#ifdef MTE_BUILD_SHARED
/* If the exports flag is set, we are creating the dynamic library so use
   the export attribute. */
#  ifdef mte_EXPORTS
#    define MTE_SHARED MTE_EXPORT
#  else
/* Not exporting so we are importing. */
#    define MTE_SHARED MTE_IMPORT
#  endif
#else
#  define MTE_SHARED
#endif

/* Define WASM export. */
#ifdef __EMSCRIPTEN__
#  define MTE_WASM_EXPORT __attribute__((used))
#else
#  define MTE_WASM_EXPORT
#endif

#endif

