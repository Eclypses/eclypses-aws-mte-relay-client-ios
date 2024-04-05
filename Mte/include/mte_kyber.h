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
#ifndef mte_kyber_h
#define mte_kyber_h

#include "mte_settings.h"
#include "mte_export.h"
#include "mte_int.h"



/*************************
 * Status code definitions
 *************************/
#define MTE_KYBER_SUCCESS             0
#define MTE_KYBER_INVALID_STRENGTH   -1
#define MTE_KYBER_ENTROPY_FAIL       -2
#define MTE_KYBER_INVALID_PUBKEY     -3
#define MTE_KYBER_INVALID_PRIVKEY    -4
#define MTE_KYBER_MEMORY_FAIL        -5
#define MTE_KYBER_INVALID_CIPHERTEXT -6



#ifdef __cplusplus
extern "C" {
#endif



/****************************************************************************
 * The mte_kyber_get_entropy() callback function
 * 
 * Use of this function is mandatory to provide a crypographically safe
 * random number generator.
 ****************************************************************************/
typedef int(*mte_kyber_get_entropy)(void *context, void **entropy,
                                    size_t *entropy_bytes,
                                    size_t min_entropy_bytes,
                                    size_t max_entropy_bytes);



/****************************************************************************
 * Initialize the Kyber strength, this function must be called before any
 * attempts to generate keys!
 *
 * [in] security strength, must be ne of these values: 512, 768, 1024
 *
 * return:  MTE_KYBER_SUCCESS on success
 *          MTE_KYBER_INVALID_STRENGTH on failure
 ****************************************************************************/
MTE_SHARED
int mte_kyber_init(uint16_t strength);



/****************************************************************************
 * Returns the size of a Kyber public key.
 * mte_kyber_init must have been completed for this function to work.
 *
 * return:  the size of the public key or 0 if init is missing
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_pubkey_size(void);



/****************************************************************************
 * Returns the size of a Kyber private key.
 * mte_kyber_init must have been completed for this function to work.
 *
 * return:  the size of the private key or 0 if init is missing
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_privkey_size(void);



/****************************************************************************
 * Returns the size of a Kyber secret.
 * mte_kyber_init must have been completed for this function to work.
 *
 * return:  the size of the private key or 0 if init is missing
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_secret_size(void);



/****************************************************************************
 * Returns the size of a Kyber encrypted secret.
 * mte_kyber_init must have been completed for this function to work.
 *
 * return:  the size of the private key or 0 if init is missing
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_encrypted_size(void);



/****************************************************************************
 * Returns the minimum size of Kyber entropy required.
 *
 * return:  the minimum size of required entropy
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_min_entropy_size(void);



/****************************************************************************
 * Returns the maximum size of Kyber entropy required.
 *
 * return:  the maximum size of required entropy
 ****************************************************************************/
MTE_SHARED
size_t mte_kyber_get_max_entropy_size(void);



/****************************************************************************
 * Returns the name of the current Kyber algorithm used.
 *
 * return:  the maximum size of required entropy
 ****************************************************************************/
MTE_SHARED
char *mte_kyber_get_algorithm(void);



/****************************************************************************
 * Generate a Kyber key pair
 *
 * [out] private_key: on success, holds the private key;
 *                    the "size" member is set to the key size.
 * [out] public_key:  on success, holds the public key;
 *                    the "size" member is set to the key size.
 * [in] entropy_cb: pointer to the entropy callback to get entropy bytes
 * [in] entropy_context: language context to be passed to entropy_cb
 *
 * return:  MTE_KYBER_SUCCESS on success
 *          MTE_KYBER_ENTROPY_FAIL if getting entropy did not work
 *          MTE_KYBER_INVALID_STRENGTH if init is missing
 *          MTE_KYBER_MEMORY_FAIL if any key sizes are too small
 ****************************************************************************/
MTE_SHARED
int mte_kyber_create_keypair(void *private_key, size_t *private_key_bytes,
                             void *public_key, size_t *public_key_bytes,
                             mte_kyber_get_entropy entropy_cb,
                             void *entropy_context);



/****************************************************************************
 * Create the Kyber secret and the encrypted secret
 *
 * [in] peer_public_key: the peer's public key
 * [out] secret: on success, holds the shared secret;
 *               the "size" member is set to the secret's size.
 * [out] encrypted: on success, holds the encrypted shared secret;
 *                  the "size" member is set to the encrypted secret's size.
 * [in] entropy_cb: pointer to the entropy callback to get entropy bytes
 * [in] entropy_context: language context to be passed to entropy_cb
 *
 * return:  MTE_KYBER_SUCCESS on success
 *          MTE_KYBER_INVALID_PRIVKEY if private key is invalid
 *          MTE_KYBER_INVALID_PUBKEY if public key is invalid
 *          MTE_KYBER_MEMORY_FAIL if any key sizes are too small or invalid
 ****************************************************************************/
MTE_SHARED
int mte_kyber_create_secret(const void *peer_public_key,
                            size_t peer_public_key_bytes,
                            void *secret, size_t *secret_bytes,
                            void *encrypted, size_t *encrypted_bytes,
                            mte_kyber_get_entropy entropy_cb,
                            void *entropy_context);



/****************************************************************************
 * Decrypt the Kyber secret
 *
 * [in] private_key: our private key
 * [in] encrypted: the peer's encrypted secret
 * [out] secret: on success, holds the shared secret;
 *               the "size" member is set to the secret's size.
 *
 * return:  MTE_KYBER_SUCCESS on success
 *          MTE_KYBER_INVALID_PRIVKEY if private key is invalid
 *          MTE_KYBER_MEMORY_FAIL if any key sizes are too small or invalid
 ****************************************************************************/
MTE_SHARED
int mte_kyber_decrypt_secret(const void *private_key, size_t private_key_bytes,
                             const void *encrypted, size_t encrypted_bytes,
                             void *secret, size_t *secret_bytes);



#ifdef __cplusplus
}
#endif

#endif /* MTE_KYBER_h */

