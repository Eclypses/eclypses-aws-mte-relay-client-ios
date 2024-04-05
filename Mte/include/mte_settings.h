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

/* WARNING: This file is automatically generated. Do not edit. */
#ifndef mte_settings_h
#define mte_settings_h

/* Define the build type:

   MTE_BUILD_DEBUG: debug build.
   MTE_BUILD_MINSIZEREL: minimum-size release build.
   MTE_BUILD_RELEASE: fully-optimized release build.
*/
#ifndef MTE_BUILD_MULTI
#  define MTE_BUILD_MULTI
#endif

/* True if the library uses 128-bit integers (and requires 16 byte alignment)
   or false if not. */
#define MTE_128 1

/* True if the library usage is "Client" or false if not. */
#define MTE_LIBUSAGE_CLIENT 
/* True if the library usage is "Server" or false if not. */
#define MTE_LIBUSAGE_SERVER 

/* True if the library requires PAA or false if not. */
#define MTE_PAA 0

/* True if the library requires a license or false if not. */
#define MTE_LICENSED 1
/* True if the library's license is paired or false if not. */
#define MTE_PAIRED_LICENSE 1
/* True if the library is built for client usage. */
#define MTE_CLIENT_LICENSE 1
/* True if the library is built for server usage. */
#define MTE_SERVER_LICENSE 0

/* True if the library has runtime options or false if it has buildtime
   settings.
*/
#define MTE_RUNTIME 0

/* The buildtime settings if this build has buildtime settings; otherwise set
   to reasonable defaults for runtime options. */
#define MTE_DRBG_ENUM mte_drbgs_ctr_aes256_df
#define MTE_TOKBYTES 16
#define MTE_VERIFIERS_ENUM mte_verifiers_seq
#define MTE_CIPHER_ENUM mte_ciphers_aes256_ctr
#define MTE_HASH_ENUM mte_hashes_sha256

/* External algorithm settings (true if external, false if internal). True means
   the algorithm can (if MTE_RUNTIME is true) or must (if MTE_RUNTIME is false)
   be provided externally; false means only an internal algorithm can be
   used. */
#define MTE_DRBG_EXTERNAL 0
#define MTE_CIPHER_EXTERNAL 0
#define MTE_HASH_EXTERNAL 0

/* Bit size of the CRC verifier if available, 0 if not. */
#define MTE_CRC_VERIFIER 0

/* 1 if the sequencing verifier if available, 0 if not. */
#define MTE_SEQUENCING_VERIFIER 1

/* Bit size of the timestamp verifier if available, 0 if not. */
#define MTE_TIMESTAMP_VERIFIER 0

#endif

