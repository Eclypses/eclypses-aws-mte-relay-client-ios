/*******************************************************************************
 * The MIT License (MIT)
 *
 * Copyright (c) Eclypses, Inc.
 *
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *******************************************************************************/
#ifndef mte_ecdh_h
#define mte_ecdh_h

#include "mte_settings.h"
#include "mte_export.h"
#include "mte_int.h"



/*************************************
 * Constants for key and secrets sizes
 *************************************/
#define MTE_ECDH_PUBLIC_KEY_SZ  64
#define MTE_ECDH_PRIVATE_KEY_SZ 32
#define MTE_ECDH_SECRET_DATA_SZ 32



/*************************
 * Status code definitions
 *************************/
#define MTE_ECDH_SUCCESS            0
#define MTE_ECDH_ENTROPY_FAIL      -1
#define MTE_ECDH_INVALID_PUBKEY    -2
#define MTE_ECDH_INVALID_PRIVKEY   -3
#define MTE_ECDH_MEMORY_FAIL       -4



#ifdef __cplusplus
extern "C" {
#endif



/****************************************************************************
 * The ecdh_get_entropy() callback function
 *
 * Use of this function is mandatory to provide a crypographically safe
 * random number generator.
 * In order to provide 256 bits of security for the generation of an EC P256
 * Diffie-Hellman keypair, 256 bits of entropy must be provided.
 ****************************************************************************/
typedef int(*mte_ecdh_get_entropy)(void *context, void *entropy,
                                   size_t entropy_bytes);



/****************************************************************************
 * Generate a Diffie-Hellman key pair
 *
 * [in] none, draws from mte_generate_random()
 * [out] private_key: on success, holds the private key as a big-endian
 *                    integer; the "size" member is set to the key size.
 * [out] public_key: on success, holds the public key as two big-endian
 *                   integers; the "size" members are set to the key sizes.
 *
 * return:  ECDH_SUCCESS on success
 *          ECDH_RANDOM_FAILED on failure
 ****************************************************************************/
MTE_SHARED
int mte_ecdh_create_keypair(void *private_key, size_t *private_key_bytes,
                            void *public_key, size_t *public_key_bytes,
                            mte_ecdh_get_entropy entropy_cb,
                            void *entropy_context);



/****************************************************************************
 * Compute a Diffie-Hellman shared secret
 *
 * [in] private_key: our private key as a big-endian integer
 * [in] public_key: the peer's public key, as two big-endian integers
 * [out] secret: on success, holds the shared secret as a big-endian integer;
 *               the "size" member is set to the secret's size.
 *
 * return:  P256_SUCCESS on success
 *          P256_INVALID_PRIVKEY if priv is invalid
 *          P256_INVALID_PUBKEY if pub is invalid
 ****************************************************************************/
MTE_SHARED
int mte_ecdh_create_secret(const void *private_key, size_t private_key_bytes,
                           const void *peer_public_key,
                           size_t peer_public_key_bytes,
                           void *secret, size_t *secret_bytes);



#ifdef __cplusplus
}
#endif

#endif /* mte_ecdh_h */

