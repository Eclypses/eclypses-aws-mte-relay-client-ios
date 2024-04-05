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
#ifndef mte_struct_h
#define mte_struct_h

#ifndef mte_settings_h
#include "mte_settings.h"
#endif
#ifndef mte_drbgs_h
#include "mte_drbgs.h"
#endif
#ifndef mte_drbg_defs_h
#include "mte_drbg_defs.h"
#endif
#ifndef mte_verifiers_h
#include "mte_verifiers.h"
#endif
#ifndef mte_verifiers_defs_h
#include "mte_verifier_defs.h"
#endif

/* These are the structures used by the MTE API. There are also some helper
   macros.
*/
#ifdef __cplusplus
extern "C"
{
#endif

/* An MTE handle. */
typedef void *MTE_HANDLE;
typedef const void *MTE_CHANDLE;

/* Encode arguments. Be aware that any member may be changed during the encode
   call for internal purposes unless otherwise noted. */
typedef struct mte_enc_args_
{
#if MTE_TIMESTAMP_VERIFIER
  /* The timestamp callback and context which are used to obtain the timestamp
     if the timestamp verifier is enabled. These members are never modified. */
  mte_verifier_get_timestamp64 t_cb;
  void *t_cb_context;
#endif

  /* Input data. */
  const void *data;

  /* Encoded result buffer. The buffer must be of sufficient length to perform
     encoding; see the encode buff bytes function for the encoder. */
  void *encoded;

  /* On input, the length of the input data. On output, the length of the
     result in the result buffer. */
  MTE_SIZE_T bytes;
} mte_enc_args;

/* Initializer for an encode arguments structure.

   d = data
   b = bytes
   e = encoded
   cb = t_cb
   context = t_cb_context
*/
#if MTE_TIMESTAMP_VERIFIER
#  define MTE_ENC_ARGS_INIT(d, b, e, cb, context) \
  { (cb), (context), (d), (e), (b) }
#else
#  define MTE_ENC_ARGS_INIT(d, b, e, cb, context)  \
  { ((void)(cb), (void)(context), (const void *)(d)), (e), (b) }
#endif

/* Set the input data/length and output buffer in the given encode arguments
   structure. */
#define MTE_SET_ENC_IO(args, d, b, e) \
  (args).data = (d);                  \
  (args).bytes = (b);                 \
  (args).encoded = (e)

/* Decode arguments. Be aware that any member may be changed during the encode
   call for internal purposes unless otherwise noted. */
typedef struct mte_dec_args_
{
#if MTE_TIMESTAMP_VERIFIER
  /* The encode/decode timestamps from the most recent decode. */
  MTE_UINT64_T enc_ts;
  MTE_UINT64_T dec_ts;

  /* The timestamp callback and context which are used to obtain the timestamp
     if the timestamp verifier is enabled. These members are never modified. */
  mte_verifier_get_timestamp64 t_cb;
  void *t_cb_context;
#endif

#if MTE_SEQUENCING_VERIFIER
  /* If the sequence window is non-negative, the messages skipped from the most
     recent decode; otherwise the number of messages ahead of the base sequence
     from the most recent decode. */
  MTE_UINT32_T msg_skipped;
#endif

  /* Input encoded data. */
  const void *encoded;

  /* Decoded result buffer. The buffer must be of sufficient length to perform
     decoding; see the decode buff bytes function for the decoder. */
  void *decoded;

  /* On input, the length of the input encoded data. On output, the length of
     the result in the result buffer. */
  MTE_SIZE_T bytes;
} mte_dec_args;

/* Initializer for a decode arguments structure.

   e = encoded
   b = bytes
   d = decoded
   cb = t_cb
   context = t_cb_context
*/
#if MTE_TIMESTAMP_VERIFIER && MTE_SEQUENCING_VERIFIER
#  define MTE_DEC_ARGS_INIT(e, b, d, cb, context) \
  { 0, 0, (cb), (context), 0, (e), (d), (b) }
#elif MTE_TIMESTAMP_VERIFIER && !MTE_SEQUENCING_VERIFIER
#  define MTE_DEC_ARGS_INIT(e, b, d, cb, context) \
  { 0, 0, (cb), (context), (e), (d), (b) }
#elif !MTE_TIMESTAMP_VERIFIER && MTE_SEQUENCING_VERIFIER
#  define MTE_DEC_ARGS_INIT(e, b, d, cb, context)     \
  { 0, ((void)(cb), (void)(context), (const void *)(e)), (d), (b) }
#else
#  define MTE_DEC_ARGS_INIT(e, b, d, cb, context)  \
  { ((void)(cb), (void)(context), (const void *)(e)), (d), (b) }
#endif

/* Set the input encoded data/length and output buffer in the given decode
   arguments structure. */
#define MTE_SET_DEC_IO(args, e, b, d) \
  (args).encoded = (e);               \
  (args).bytes = (b);                 \
  (args).decoded = (d)

/* Sets the timestamp callback and context in the given encode/decode arguments
   structure. */
#if MTE_TIMESTAMP_VERIFIER
#  define MTE_SET_TIMESTAMP_CB(args, cb, context) \
  (args).t_cb = (cb);                             \
  (args).t_cb_context = (context)
#else
#  define MTE_SET_TIMESTAMP_CB(args, cb, context) \
  (void)args; (void)cb; (void)context
#endif

/* Returns the encode/decode timestamp from a successful decode. Returns 0 if
   timestamps are not enabled. */
#if MTE_TIMESTAMP_VERIFIER
#  define MTE_GET_ENC_TS(args) ((args).enc_ts)
#  define MTE_GET_DEC_TS(args) ((args).dec_ts)
#else
#  define MTE_GET_ENC_TS(args) ((void)(args), (MTE_UINT64_T)0)
#  define MTE_GET_DEC_TS(args) ((void)(args), (MTE_UINT64_T)0)
#endif

/* Returns the number of messages skipped after a successful decode. Returns 0
   if sequencing is not enabled. */
#if MTE_SEQUENCING_VERIFIER
#  define MTE_GET_MSG_SKIPPED(args) ((args).msg_skipped)
#else
#  define MTE_GET_MSG_SKIPPED(args) ((void)(args), (MTE_UINT32_T)0)
#endif

/* MTE encoder parameters. */
typedef struct mte_encoder_params_
{
#if MTE_DRBG_EXTERNAL
  /* The DRBG state if drbg is set to mte_drbgs_none. The state must remain
     valid while using the encoder. */
  void *drbg_state;

  /* The DRBG info if drbg is set to mte_drbgs_none. The info must remain
     valid while using the encoder. */
  const mte_drbg_info *drbg_info;
#endif

#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
  /* The DRBG algorithm. */
  mte_drbgs drbg;
#endif

#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
  /* The verifiers algorithm. */
  mte_verifiers verifiers;
#endif

  /* The token size in bytes. */
  MTE_SIZE8_T tok_bytes;
} mte_encoder_params;

/* Initializer for an encoder parameters structure.

   d = drbg
   t = tok_bytes
   v = verifiers
   ds = drbg_state
   di = drbg_info
*/
#if MTE_DRBG_EXTERNAL && (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_ENCODER_PARAMS_INIT(d, t, v, ds, di) { (ds), (di), (d), (v), (t) }
#elif !MTE_DRBG_EXTERNAL && (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_ENCODER_PARAMS_INIT(d, t, v, ds, di) \
  { ((void)(ds), (void)(di), (d)), (v), (t) }
#elif MTE_DRBG_EXTERNAL && !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_ENCODER_PARAMS_INIT(d, t, v, ds, di) \
  { ((void)(d), (void)(v), (ds)), (di), (t) }
#else
#  define MTE_ENCODER_PARAMS_INIT(d, t, v, ds, di)        \
  { ((void)(d), (void)(v), (void)(ds), (void)(di), (t)) }
#endif

/* MTE decoder parameters. */
typedef struct mte_decoder_params_
{
#if MTE_TIMESTAMP_VERIFIER
  /* The timestamp window. */
  MTE_UINT64_T t_window;
#endif

#if MTE_SEQUENCING_VERIFIER
  /* The sequencing window. */
  MTE_INT32_T s_window;
#endif

#if MTE_DRBG_EXTERNAL
  /* The DRBG state if drbg is set to mte_drbgs_none. The state must remain
     valid while using the encoder. */
  void *drbg_state;

  /* The DRBG info if drbg is set to mte_drbgs_none. The info must remain
     valid while using the encoder. */
  const mte_drbg_info *drbg_info;
#endif

#if MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL)
  /* The DRBG algorithm. */
  mte_drbgs drbg;

  /* The verifiers algorithm. */
  mte_verifiers verifiers;
#endif

  /* The token size in bytes. */
  MTE_SIZE8_T tok_bytes;
} mte_decoder_params;

/* Initializer for a decoder parameters structure.

   d = drbg
   t = tok_bytes
   v = verifiers
   tw = timestamp_window
   sw = sequencing window
   ds = drbg_state
   di = drbg_info
*/
#if MTE_TIMESTAMP_VERIFIER &&                       \
    MTE_SEQUENCING_VERIFIER &&                      \
    MTE_DRBG_EXTERNAL &&                            \
    (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { (tw), (sw), (ds), (di), (d), (v), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                        \
      MTE_SEQUENCING_VERIFIER &&                       \
      MTE_DRBG_EXTERNAL &&                             \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { ((void)(d), (void)(v), (tw)), (sw), (ds), (di), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                       \
      MTE_SEQUENCING_VERIFIER &&                      \
      !MTE_DRBG_EXTERNAL &&                           \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { ((void)(ds), (void)(di), (tw)), (sw), (d), (v), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                        \
      MTE_SEQUENCING_VERIFIER &&                       \
      !MTE_DRBG_EXTERNAL &&                            \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)            \
  { ((void)(d), (void)(v), (void)(ds), (void)(di), (tw)), (sw), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                       \
      !MTE_SEQUENCING_VERIFIER &&                     \
      MTE_DRBG_EXTERNAL &&                            \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { ((void)(sw), (tw)), (ds), (di), (d), (v), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                        \
      !MTE_SEQUENCING_VERIFIER &&                      \
      MTE_DRBG_EXTERNAL &&                             \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)      \
  { ((void)(d), (void)(v), (void)(sw), (tw)), (ds), (di), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                       \
      !MTE_SEQUENCING_VERIFIER &&                     \
      !MTE_DRBG_EXTERNAL &&                           \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)      \
  { ((void)(sw), (void)(ds), (void)(di), (tw)), (d), (v), (t) }
#elif MTE_TIMESTAMP_VERIFIER &&                        \
      !MTE_SEQUENCING_VERIFIER &&                      \
      !MTE_DRBG_EXTERNAL &&                            \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)                  \
  { ((void)(d), (void)(v), (void)(sw), (void)(ds), (void)(di), (tw)), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                      \
      MTE_SEQUENCING_VERIFIER &&                      \
      MTE_DRBG_EXTERNAL &&                            \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { ((void)(tw), (sw)), (ds), (di), (d), (v), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                       \
      MTE_SEQUENCING_VERIFIER &&                       \
      MTE_DRBG_EXTERNAL &&                             \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)      \
  { ((void)(d), (void)(v), (void)(tw), (sw)), (ds), (di), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                      \
      MTE_SEQUENCING_VERIFIER &&                      \
      !MTE_DRBG_EXTERNAL &&                           \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)      \
  { ((void)(tw), (void)(ds), (void)(di), (sw)), (d), (v), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                       \
      MTE_SEQUENCING_VERIFIER &&                       \
      !MTE_DRBG_EXTERNAL &&                            \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)                  \
  { ((void)(d), (void)(v), (void)(tw), (void)(ds), (void)(di), (sw)), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                      \
      !MTE_SEQUENCING_VERIFIER &&                     \
      MTE_DRBG_EXTERNAL &&                            \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di) \
  { ((void)(tw), (void)(sw), (ds)), (di), (d), (v), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                       \
      !MTE_SEQUENCING_VERIFIER &&                      \
      MTE_DRBG_EXTERNAL &&                             \
      !(MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)            \
  { ((void)(d), (void)(v), (void)(tw), (void)(sw), (ds)), (di), (t) }
#elif !MTE_TIMESTAMP_VERIFIER &&                      \
      !MTE_SEQUENCING_VERIFIER &&                     \
      !MTE_DRBG_EXTERNAL &&                           \
      (MTE_RUNTIME || !defined(MTE_BUILD_MINSIZEREL))
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)            \
  { ((void)(tw), (void)(sw), (void)(ds), (void)(di), (d)), (v), (t) }
#else
#  define MTE_DECODER_PARAMS_INIT(d, t, v, tw, sw, ds, di)                 \
  { ((void)(d), (void)(v), (void)(tw), (void)(sw), (void)(ds), (void)(di), \
     (t)) }
#endif

/* Set the timestamp window. */
#if MTE_TIMESTAMP_VERIFIER
#  define MTE_SET_T_WINDOW(params, val) (params).t_window = (val)
#else
#  define MTE_SET_T_WINDOW(params, val) ((void)(params), (void)(val))
#endif

/* Set the sequencing window. */
#if MTE_SEQUENCING_VERIFIER
#  define MTE_SET_S_WINDOW(params, val) (params).s_window = (val)
#else
#  define MTE_SET_S_WINDOW(params, val) ((void)(params), (void)(val))
#endif

#ifdef __cplusplus
}
#endif

#endif

