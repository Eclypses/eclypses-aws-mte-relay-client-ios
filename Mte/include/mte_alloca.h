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
#ifndef mte_alloca_h
#define mte_alloca_h

/* Define a macro to use the alloca() function to dynamically allocate on the
   stack. */
#if defined(_WIN32)
#  include <malloc.h>
#  define MTE_ALLOCA(bytes) _malloca(bytes)
#elif defined(__ANDROID__) ||    \
      defined(__APPLE__) ||      \
      defined(__AVR__) ||        \
      defined(__EMSCRIPTEN__) || \
      defined(__PIC24F__) ||     \
      defined(__PIC32__) ||      \
      defined(__linux__) ||      \
      defined(__xtensa__)
#  include <alloca.h>
#  define MTE_ALLOCA(bytes) alloca(bytes)
#elif defined(__GNUC__) && defined(__has_include)
#  if __has_include(<alloca.h>)
#    include <alloca.h>
#    define MTE_ALLOCA(bytes) alloca(bytes)
#  else
#    error Unknown operating system.
#  endif
#else
#  error Unknown operating system.
#endif

#endif

