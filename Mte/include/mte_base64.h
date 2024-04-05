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
#ifndef mte_base64_h
#define mte_base64_h

#ifndef mte_export_h
#include "mte_export.h"
#endif
#ifndef mte_int_h
#include "mte_int.h"
#endif

/* Support Base64 encoding. See RFC 4648.

   To use, call mte_base64_encode() to encode data in Base64 format or call
   mte_base64_decode() to decode data from Base64 format.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* Returns the required encode buffer length for the given input data length. */
MTE_SHARED
MTE_SIZE_T mte_base64_encode_bytes(MTE_SIZE_T in_bytes);

/* Encodes the given data to the given string in Base64 format. The encoded
   buffer must be at least mte_base64_encode_bytes() in length. The encoded
   version will be null terminated. Returns the length of the encoded string in
   bytes, not including the null terminator. */
MTE_SHARED
MTE_SIZE_T mte_base64_encode(const void *data, MTE_SIZE_T bytes, char *encoded);

/* Returns the required decode buffer length for the given input Base64
   length. */
MTE_SHARED
MTE_SIZE_T mte_base64_decode_bytes(MTE_SIZE_T in_bytes);

/* Decodes the given Base64 to the given buffer. The decoded buffer must be at
   least mte_base64_decode_bytes() in length. It can be the same as the input
   buffer as long as it has enough length, in which case the encoded version is
   partially overwritten with the decoded version, which is safe because the
   decode of four bytes results in three bytes. The decoded version will be null
   terminated. Returns the decoded length, not including the null terminator.
   Invalid input bytes are ignored, and missing pad characters at the end are
   assumed if necessary. */
MTE_SHARED
MTE_SIZE_T mte_base64_decode(const void *base64,
                             MTE_SIZE_T bytes,
                             void *decoded);

#ifdef __cplusplus
}
#endif

#endif

