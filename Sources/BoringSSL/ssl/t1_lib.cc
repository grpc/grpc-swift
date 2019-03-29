/* Copyright (C) 1995-1998 Eric Young (eay@cryptsoft.com)
 * All rights reserved.
 *
 * This package is an SSL implementation written
 * by Eric Young (eay@cryptsoft.com).
 * The implementation was written so as to conform with Netscapes SSL.
 *
 * This library is free for commercial and non-commercial use as long as
 * the following conditions are aheared to.  The following conditions
 * apply to all code found in this distribution, be it the RC4, RSA,
 * lhash, DES, etc., code; not just the SSL code.  The SSL documentation
 * included with this distribution is covered by the same copyright terms
 * except that the holder is Tim Hudson (tjh@cryptsoft.com).
 *
 * Copyright remains Eric Young's, and as such any Copyright notices in
 * the code are not to be removed.
 * If this package is used in a product, Eric Young should be given attribution
 * as the author of the parts of the library used.
 * This can be in the form of a textual message at program startup or
 * in documentation (online or textual) provided with the package.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *    "This product includes cryptographic software written by
 *     Eric Young (eay@cryptsoft.com)"
 *    The word 'cryptographic' can be left out if the rouines from the library
 *    being used are not cryptographic related :-).
 * 4. If you include any Windows specific code (or a derivative thereof) from
 *    the apps directory (application code) you must include an acknowledgement:
 *    "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
 *
 * THIS SOFTWARE IS PROVIDED BY ERIC YOUNG ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The licence and distribution terms for any publically available version or
 * derivative of this code cannot be changed.  i.e. this code cannot simply be
 * copied and put under another distribution licence
 * [including the GNU Public Licence.]
 */
/* ====================================================================
 * Copyright (c) 1998-2007 The OpenSSL Project.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. All advertising materials mentioning features or use of this
 *    software must display the following acknowledgment:
 *    "This product includes software developed by the OpenSSL Project
 *    for use in the OpenSSL Toolkit. (http://www.openssl.org/)"
 *
 * 4. The names "OpenSSL Toolkit" and "OpenSSL Project" must not be used to
 *    endorse or promote products derived from this software without
 *    prior written permission. For written permission, please contact
 *    openssl-core@openssl.org.
 *
 * 5. Products derived from this software may not be called "OpenSSL"
 *    nor may "OpenSSL" appear in their names without prior written
 *    permission of the OpenSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *    acknowledgment:
 *    "This product includes software developed by the OpenSSL Project
 *    for use in the OpenSSL Toolkit (http://www.openssl.org/)"
 *
 * THIS SOFTWARE IS PROVIDED BY THE OpenSSL PROJECT ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE OpenSSL PROJECT OR
 * ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * ====================================================================
 *
 * This product includes cryptographic software written by Eric Young
 * (eay@cryptsoft.com).  This product includes software written by Tim
 * Hudson (tjh@cryptsoft.com). */

#include <openssl/ssl.h>

#include <assert.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#include <utility>

#include <openssl/bytestring.h>
#include <openssl/chacha.h>
#include <openssl/digest.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/mem.h>
#include <openssl/nid.h>
#include <openssl/rand.h>

#include "internal.h"
#include "../crypto/internal.h"


namespace bssl {

static int ssl_check_clienthello_tlsext(SSL_HANDSHAKE *hs);

static int compare_uint16_t(const void *p1, const void *p2) {
  uint16_t u1 = *((const uint16_t *)p1);
  uint16_t u2 = *((const uint16_t *)p2);
  if (u1 < u2) {
    return -1;
  } else if (u1 > u2) {
    return 1;
  } else {
    return 0;
  }
}

// Per http://tools.ietf.org/html/rfc5246#section-7.4.1.4, there may not be
// more than one extension of the same type in a ClientHello or ServerHello.
// This function does an initial scan over the extensions block to filter those
// out.
static int tls1_check_duplicate_extensions(const CBS *cbs) {
  // First pass: count the extensions.
  size_t num_extensions = 0;
  CBS extensions = *cbs;
  while (CBS_len(&extensions) > 0) {
    uint16_t type;
    CBS extension;

    if (!CBS_get_u16(&extensions, &type) ||
        !CBS_get_u16_length_prefixed(&extensions, &extension)) {
      return 0;
    }

    num_extensions++;
  }

  if (num_extensions == 0) {
    return 1;
  }

  Array<uint16_t> extension_types;
  if (!extension_types.Init(num_extensions)) {
    return 0;
  }

  // Second pass: gather the extension types.
  extensions = *cbs;
  for (size_t i = 0; i < extension_types.size(); i++) {
    CBS extension;

    if (!CBS_get_u16(&extensions, &extension_types[i]) ||
        !CBS_get_u16_length_prefixed(&extensions, &extension)) {
      // This should not happen.
      return 0;
    }
  }
  assert(CBS_len(&extensions) == 0);

  // Sort the extensions and make sure there are no duplicates.
  qsort(extension_types.data(), extension_types.size(), sizeof(uint16_t),
        compare_uint16_t);
  for (size_t i = 1; i < num_extensions; i++) {
    if (extension_types[i - 1] == extension_types[i]) {
      return 0;
    }
  }

  return 1;
}

int ssl_client_hello_init(SSL *ssl, SSL_CLIENT_HELLO *out,
                          const SSLMessage &msg) {
  OPENSSL_memset(out, 0, sizeof(*out));
  out->ssl = ssl;
  out->client_hello = CBS_data(&msg.body);
  out->client_hello_len = CBS_len(&msg.body);

  CBS client_hello, random, session_id;
  CBS_init(&client_hello, out->client_hello, out->client_hello_len);
  if (!CBS_get_u16(&client_hello, &out->version) ||
      !CBS_get_bytes(&client_hello, &random, SSL3_RANDOM_SIZE) ||
      !CBS_get_u8_length_prefixed(&client_hello, &session_id) ||
      CBS_len(&session_id) > SSL_MAX_SSL_SESSION_ID_LENGTH) {
    return 0;
  }

  out->random = CBS_data(&random);
  out->random_len = CBS_len(&random);
  out->session_id = CBS_data(&session_id);
  out->session_id_len = CBS_len(&session_id);

  // Skip past DTLS cookie
  if (SSL_is_dtls(out->ssl)) {
    CBS cookie;
    if (!CBS_get_u8_length_prefixed(&client_hello, &cookie) ||
        CBS_len(&cookie) > DTLS1_COOKIE_LENGTH) {
      return 0;
    }
  }

  CBS cipher_suites, compression_methods;
  if (!CBS_get_u16_length_prefixed(&client_hello, &cipher_suites) ||
      CBS_len(&cipher_suites) < 2 || (CBS_len(&cipher_suites) & 1) != 0 ||
      !CBS_get_u8_length_prefixed(&client_hello, &compression_methods) ||
      CBS_len(&compression_methods) < 1) {
    return 0;
  }

  out->cipher_suites = CBS_data(&cipher_suites);
  out->cipher_suites_len = CBS_len(&cipher_suites);
  out->compression_methods = CBS_data(&compression_methods);
  out->compression_methods_len = CBS_len(&compression_methods);

  // If the ClientHello ends here then it's valid, but doesn't have any
  // extensions. (E.g. SSLv3.)
  if (CBS_len(&client_hello) == 0) {
    out->extensions = NULL;
    out->extensions_len = 0;
    return 1;
  }

  // Extract extensions and check it is valid.
  CBS extensions;
  if (!CBS_get_u16_length_prefixed(&client_hello, &extensions) ||
      !tls1_check_duplicate_extensions(&extensions) ||
      CBS_len(&client_hello) != 0) {
    return 0;
  }

  out->extensions = CBS_data(&extensions);
  out->extensions_len = CBS_len(&extensions);

  return 1;
}

int ssl_client_hello_get_extension(const SSL_CLIENT_HELLO *client_hello,
                                   CBS *out, uint16_t extension_type) {
  CBS extensions;
  CBS_init(&extensions, client_hello->extensions, client_hello->extensions_len);
  while (CBS_len(&extensions) != 0) {
    // Decode the next extension.
    uint16_t type;
    CBS extension;
    if (!CBS_get_u16(&extensions, &type) ||
        !CBS_get_u16_length_prefixed(&extensions, &extension)) {
      return 0;
    }

    if (type == extension_type) {
      *out = extension;
      return 1;
    }
  }

  return 0;
}

static const uint16_t kDefaultGroups[] = {
    SSL_CURVE_X25519,
    SSL_CURVE_SECP256R1,
    SSL_CURVE_SECP384R1,
};

Span<const uint16_t> tls1_get_grouplist(const SSL *ssl) {
  if (ssl->supported_group_list != nullptr) {
    return MakeConstSpan(ssl->supported_group_list,
                         ssl->supported_group_list_len);
  }
  return Span<const uint16_t>(kDefaultGroups);
}

int tls1_get_shared_group(SSL_HANDSHAKE *hs, uint16_t *out_group_id) {
  SSL *const ssl = hs->ssl;
  assert(ssl->server);

  // Clients are not required to send a supported_groups extension. In this
  // case, the server is free to pick any group it likes. See RFC 4492,
  // section 4, paragraph 3.
  //
  // However, in the interests of compatibility, we will skip ECDH if the
  // client didn't send an extension because we can't be sure that they'll
  // support our favoured group. Thus we do not special-case an emtpy
  // |peer_supported_group_list|.

  Span<const uint16_t> groups = tls1_get_grouplist(ssl);
  Span<const uint16_t> pref, supp;
  if (ssl->options & SSL_OP_CIPHER_SERVER_PREFERENCE) {
    pref = groups;
    supp = hs->peer_supported_group_list;
  } else {
    pref = hs->peer_supported_group_list;
    supp = groups;
  }

  for (uint16_t pref_group : pref) {
    for (uint16_t supp_group : supp) {
      if (pref_group == supp_group) {
        *out_group_id = pref_group;
        return 1;
      }
    }
  }

  return 0;
}

int tls1_set_curves(uint16_t **out_group_ids, size_t *out_group_ids_len,
                    const int *curves, size_t ncurves) {
  uint16_t *group_ids = (uint16_t *)OPENSSL_malloc(ncurves * sizeof(uint16_t));
  if (group_ids == NULL) {
    return 0;
  }

  for (size_t i = 0; i < ncurves; i++) {
    if (!ssl_nid_to_group_id(&group_ids[i], curves[i])) {
      OPENSSL_free(group_ids);
      return 0;
    }
  }

  OPENSSL_free(*out_group_ids);
  *out_group_ids = group_ids;
  *out_group_ids_len = ncurves;

  return 1;
}

int tls1_set_curves_list(uint16_t **out_group_ids, size_t *out_group_ids_len,
                         const char *curves) {
  uint16_t *group_ids = NULL;
  size_t ncurves = 0;

  const char *col;
  const char *ptr = curves;

  do {
    col = strchr(ptr, ':');

    uint16_t group_id;
    if (!ssl_name_to_group_id(&group_id, ptr,
                              col ? (size_t)(col - ptr) : strlen(ptr))) {
      goto err;
    }

    uint16_t *new_group_ids = (uint16_t *)OPENSSL_realloc(
        group_ids, (ncurves + 1) * sizeof(uint16_t));
    if (new_group_ids == NULL) {
      goto err;
    }
    group_ids = new_group_ids;

    group_ids[ncurves] = group_id;
    ncurves++;

    if (col) {
      ptr = col + 1;
    }
  } while (col);

  OPENSSL_free(*out_group_ids);
  *out_group_ids = group_ids;
  *out_group_ids_len = ncurves;

  return 1;

err:
  OPENSSL_free(group_ids);
  return 0;
}

int tls1_check_group_id(const SSL *ssl, uint16_t group_id) {
  for (uint16_t supported : tls1_get_grouplist(ssl)) {
    if (supported == group_id) {
      return 1;
    }
  }

  return 0;
}

// kVerifySignatureAlgorithms is the default list of accepted signature
// algorithms for verifying.
//
// For now, RSA-PSS signature algorithms are not enabled on Android's system
// BoringSSL. Once the change in Chrome has stuck and the values are finalized,
// restore them.
static const uint16_t kVerifySignatureAlgorithms[] = {
    // List our preferred algorithms first.
    SSL_SIGN_ED25519,
    SSL_SIGN_ECDSA_SECP256R1_SHA256,
    SSL_SIGN_RSA_PSS_SHA256,
    SSL_SIGN_RSA_PKCS1_SHA256,

    // Larger hashes are acceptable.
    SSL_SIGN_ECDSA_SECP384R1_SHA384,
    SSL_SIGN_RSA_PSS_SHA384,
    SSL_SIGN_RSA_PKCS1_SHA384,

    SSL_SIGN_RSA_PSS_SHA512,
    SSL_SIGN_RSA_PKCS1_SHA512,

    // For now, SHA-1 is still accepted but least preferable.
    SSL_SIGN_RSA_PKCS1_SHA1,

};

// kSignSignatureAlgorithms is the default list of supported signature
// algorithms for signing.
//
// For now, RSA-PSS signature algorithms are not enabled on Android's system
// BoringSSL. Once the change in Chrome has stuck and the values are finalized,
// restore them.
static const uint16_t kSignSignatureAlgorithms[] = {
    // List our preferred algorithms first.
    SSL_SIGN_ED25519,
    SSL_SIGN_ECDSA_SECP256R1_SHA256,
    SSL_SIGN_RSA_PSS_SHA256,
    SSL_SIGN_RSA_PKCS1_SHA256,

    // If needed, sign larger hashes.
    //
    // TODO(davidben): Determine which of these may be pruned.
    SSL_SIGN_ECDSA_SECP384R1_SHA384,
    SSL_SIGN_RSA_PSS_SHA384,
    SSL_SIGN_RSA_PKCS1_SHA384,

    SSL_SIGN_ECDSA_SECP521R1_SHA512,
    SSL_SIGN_RSA_PSS_SHA512,
    SSL_SIGN_RSA_PKCS1_SHA512,

    // If the peer supports nothing else, sign with SHA-1.
    SSL_SIGN_ECDSA_SHA1,
    SSL_SIGN_RSA_PKCS1_SHA1,
};

bool tls12_add_verify_sigalgs(const SSL *ssl, CBB *out) {
  bool use_default = ssl->ctx->num_verify_sigalgs == 0;
  Span<const uint16_t> sigalgs = kVerifySignatureAlgorithms;
  if (!use_default) {
    sigalgs = MakeConstSpan(ssl->ctx->verify_sigalgs,
                            ssl->ctx->num_verify_sigalgs);
  }

  for (uint16_t sigalg : sigalgs) {
    if (use_default &&
        sigalg == SSL_SIGN_ED25519 &&
        !ssl->ctx->ed25519_enabled) {
      continue;
    }
    if (!CBB_add_u16(out, sigalg)) {
      return false;
    }
  }

  return true;
}

bool tls12_check_peer_sigalg(const SSL *ssl, uint8_t *out_alert,
                             uint16_t sigalg) {
  const uint16_t *sigalgs = kVerifySignatureAlgorithms;
  size_t num_sigalgs = OPENSSL_ARRAY_SIZE(kVerifySignatureAlgorithms);
  if (ssl->ctx->num_verify_sigalgs != 0) {
    sigalgs = ssl->ctx->verify_sigalgs;
    num_sigalgs = ssl->ctx->num_verify_sigalgs;
  }

  for (size_t i = 0; i < num_sigalgs; i++) {
    if (sigalgs == kVerifySignatureAlgorithms &&
        sigalgs[i] == SSL_SIGN_ED25519 &&
        !ssl->ctx->ed25519_enabled) {
      continue;
    }
    if (sigalg == sigalgs[i]) {
      return true;
    }
  }

  OPENSSL_PUT_ERROR(SSL, SSL_R_WRONG_SIGNATURE_TYPE);
  *out_alert = SSL_AD_ILLEGAL_PARAMETER;
  return false;
}

// tls_extension represents a TLS extension that is handled internally. The
// |init| function is called for each handshake, before any other functions of
// the extension. Then the add and parse callbacks are called as needed.
//
// The parse callbacks receive a |CBS| that contains the contents of the
// extension (i.e. not including the type and length bytes). If an extension is
// not received then the parse callbacks will be called with a NULL CBS so that
// they can do any processing needed to handle the absence of an extension.
//
// The add callbacks receive a |CBB| to which the extension can be appended but
// the function is responsible for appending the type and length bytes too.
//
// All callbacks return true for success and false for error. If a parse
// function returns zero then a fatal alert with value |*out_alert| will be
// sent. If |*out_alert| isn't set, then a |decode_error| alert will be sent.
struct tls_extension {
  uint16_t value;
  void (*init)(SSL_HANDSHAKE *hs);

  bool (*add_clienthello)(SSL_HANDSHAKE *hs, CBB *out);
  bool (*parse_serverhello)(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                            CBS *contents);

  bool (*parse_clienthello)(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                            CBS *contents);
  bool (*add_serverhello)(SSL_HANDSHAKE *hs, CBB *out);
};

static bool forbid_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                    CBS *contents) {
  if (contents != NULL) {
    // Servers MUST NOT send this extension.
    *out_alert = SSL_AD_UNSUPPORTED_EXTENSION;
    OPENSSL_PUT_ERROR(SSL, SSL_R_UNEXPECTED_EXTENSION);
    return false;
  }

  return true;
}

static bool ignore_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                    CBS *contents) {
  // This extension from the client is handled elsewhere.
  return true;
}

static bool dont_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  return true;
}

// Server name indication (SNI).
//
// https://tools.ietf.org/html/rfc6066#section-3.

static bool ext_sni_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->tlsext_hostname == NULL) {
    return true;
  }

  CBB contents, server_name_list, name;
  if (!CBB_add_u16(out, TLSEXT_TYPE_server_name) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &server_name_list) ||
      !CBB_add_u8(&server_name_list, TLSEXT_NAMETYPE_host_name) ||
      !CBB_add_u16_length_prefixed(&server_name_list, &name) ||
      !CBB_add_bytes(&name, (const uint8_t *)ssl->tlsext_hostname,
                     strlen(ssl->tlsext_hostname)) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_sni_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  // The server may acknowledge SNI with an empty extension. We check the syntax
  // but otherwise ignore this signal.
  return contents == NULL || CBS_len(contents) == 0;
}

static bool ext_sni_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  CBS server_name_list, host_name;
  uint8_t name_type;
  if (!CBS_get_u16_length_prefixed(contents, &server_name_list) ||
      !CBS_get_u8(&server_name_list, &name_type) ||
      // Although the server_name extension was intended to be extensible to
      // new name types and multiple names, OpenSSL 1.0.x had a bug which meant
      // different name types will cause an error. Further, RFC 4366 originally
      // defined syntax inextensibly. RFC 6066 corrected this mistake, but
      // adding new name types is no longer feasible.
      //
      // Act as if the extensibility does not exist to simplify parsing.
      !CBS_get_u16_length_prefixed(&server_name_list, &host_name) ||
      CBS_len(&server_name_list) != 0 ||
      CBS_len(contents) != 0) {
    return false;
  }

  if (name_type != TLSEXT_NAMETYPE_host_name ||
      CBS_len(&host_name) == 0 ||
      CBS_len(&host_name) > TLSEXT_MAXLEN_host_name ||
      CBS_contains_zero_byte(&host_name)) {
    *out_alert = SSL_AD_UNRECOGNIZED_NAME;
    return false;
  }

  // Copy the hostname as a string.
  char *raw = nullptr;
  if (!CBS_strdup(&host_name, &raw)) {
    *out_alert = SSL_AD_INTERNAL_ERROR;
    return false;
  }
  ssl->s3->hostname.reset(raw);

  hs->should_ack_sni = true;
  return true;
}

static bool ext_sni_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (hs->ssl->s3->session_reused ||
      !hs->should_ack_sni) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_server_name) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}


// Renegotiation indication.
//
// https://tools.ietf.org/html/rfc5746

static bool ext_ri_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  // Renegotiation indication is not necessary in TLS 1.3.
  if (hs->min_version >= TLS1_3_VERSION) {
    return true;
  }

  assert(ssl->s3->initial_handshake_complete ==
         (ssl->s3->previous_client_finished_len != 0));

  CBB contents, prev_finished;
  if (!CBB_add_u16(out, TLSEXT_TYPE_renegotiate) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u8_length_prefixed(&contents, &prev_finished) ||
      !CBB_add_bytes(&prev_finished, ssl->s3->previous_client_finished,
                     ssl->s3->previous_client_finished_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_ri_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                     CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents != NULL && ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  // Servers may not switch between omitting the extension and supporting it.
  // See RFC 5746, sections 3.5 and 4.2.
  if (ssl->s3->initial_handshake_complete &&
      (contents != NULL) != ssl->s3->send_connection_binding) {
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_MISMATCH);
    return false;
  }

  if (contents == NULL) {
    // Strictly speaking, if we want to avoid an attack we should *always* see
    // RI even on initial ServerHello because the client doesn't see any
    // renegotiation during an attack. However this would mean we could not
    // connect to any server which doesn't support RI.
    //
    // OpenSSL has |SSL_OP_LEGACY_SERVER_CONNECT| to control this, but in
    // practical terms every client sets it so it's just assumed here.
    return true;
  }

  const size_t expected_len = ssl->s3->previous_client_finished_len +
                              ssl->s3->previous_server_finished_len;

  // Check for logic errors
  assert(!expected_len || ssl->s3->previous_client_finished_len);
  assert(!expected_len || ssl->s3->previous_server_finished_len);
  assert(ssl->s3->initial_handshake_complete ==
         (ssl->s3->previous_client_finished_len != 0));
  assert(ssl->s3->initial_handshake_complete ==
         (ssl->s3->previous_server_finished_len != 0));

  // Parse out the extension contents.
  CBS renegotiated_connection;
  if (!CBS_get_u8_length_prefixed(contents, &renegotiated_connection) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_ENCODING_ERR);
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  // Check that the extension matches.
  if (CBS_len(&renegotiated_connection) != expected_len) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_MISMATCH);
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    return false;
  }

  const uint8_t *d = CBS_data(&renegotiated_connection);
  bool ok = CRYPTO_memcmp(d, ssl->s3->previous_client_finished,
                          ssl->s3->previous_client_finished_len) == 0;
#if defined(BORINGSSL_UNSAFE_FUZZER_MODE)
  ok = true;
#endif
  if (!ok) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_MISMATCH);
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    return false;
  }
  d += ssl->s3->previous_client_finished_len;

  ok = CRYPTO_memcmp(d, ssl->s3->previous_server_finished,
                     ssl->s3->previous_server_finished_len) == 0;
#if defined(BORINGSSL_UNSAFE_FUZZER_MODE)
  ok = true;
#endif
  if (!ok) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_MISMATCH);
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    return false;
  }
  ssl->s3->send_connection_binding = true;

  return true;
}

static bool ext_ri_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                     CBS *contents) {
  SSL *const ssl = hs->ssl;
  // Renegotiation isn't supported as a server so this function should never be
  // called after the initial handshake.
  assert(!ssl->s3->initial_handshake_complete);

  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return true;
  }

  if (contents == NULL) {
    return true;
  }

  CBS renegotiated_connection;
  if (!CBS_get_u8_length_prefixed(contents, &renegotiated_connection) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_ENCODING_ERR);
    return false;
  }

  // Check that the extension matches. We do not support renegotiation as a
  // server, so this must be empty.
  if (CBS_len(&renegotiated_connection) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_MISMATCH);
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    return false;
  }

  ssl->s3->send_connection_binding = true;

  return true;
}

static bool ext_ri_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  // Renegotiation isn't supported as a server so this function should never be
  // called after the initial handshake.
  assert(!ssl->s3->initial_handshake_complete);

  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_renegotiate) ||
      !CBB_add_u16(out, 1 /* length */) ||
      !CBB_add_u8(out, 0 /* empty renegotiation info */)) {
    return false;
  }

  return true;
}


// Extended Master Secret.
//
// https://tools.ietf.org/html/rfc7627

static bool ext_ems_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  // Extended master secret is not necessary in TLS 1.3.
  if (hs->min_version >= TLS1_3_VERSION || hs->max_version <= SSL3_VERSION) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_extended_master_secret) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}

static bool ext_ems_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  SSL *const ssl = hs->ssl;

  if (contents != NULL) {
    if (ssl_protocol_version(ssl) >= TLS1_3_VERSION ||
        ssl->version == SSL3_VERSION ||
        CBS_len(contents) != 0) {
      return false;
    }

    hs->extended_master_secret = true;
  }

  // Whether EMS is negotiated may not change on renegotiation.
  if (ssl->s3->established_session != nullptr &&
      hs->extended_master_secret !=
          !!ssl->s3->established_session->extended_master_secret) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_RENEGOTIATION_EMS_MISMATCH);
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  return true;
}

static bool ext_ems_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  uint16_t version = ssl_protocol_version(hs->ssl);
  if (version >= TLS1_3_VERSION ||
      version == SSL3_VERSION) {
    return true;
  }

  if (contents == NULL) {
    return true;
  }

  if (CBS_len(contents) != 0) {
    return false;
  }

  hs->extended_master_secret = true;
  return true;
}

static bool ext_ems_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (!hs->extended_master_secret) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_extended_master_secret) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}


// Session tickets.
//
// https://tools.ietf.org/html/rfc5077

static bool ext_ticket_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  // TLS 1.3 uses a different ticket extension.
  if (hs->min_version >= TLS1_3_VERSION ||
      SSL_get_options(ssl) & SSL_OP_NO_TICKET) {
    return true;
  }

  const uint8_t *ticket_data = NULL;
  int ticket_len = 0;

  // Renegotiation does not participate in session resumption. However, still
  // advertise the extension to avoid potentially breaking servers which carry
  // over the state from the previous handshake, such as OpenSSL servers
  // without upstream's 3c3f0259238594d77264a78944d409f2127642c4.
  if (!ssl->s3->initial_handshake_complete &&
      ssl->session != NULL &&
      ssl->session->tlsext_tick != NULL &&
      // Don't send TLS 1.3 session tickets in the ticket extension.
      ssl_session_protocol_version(ssl->session) < TLS1_3_VERSION) {
    ticket_data = ssl->session->tlsext_tick;
    ticket_len = ssl->session->tlsext_ticklen;
  }

  CBB ticket;
  if (!CBB_add_u16(out, TLSEXT_TYPE_session_ticket) ||
      !CBB_add_u16_length_prefixed(out, &ticket) ||
      !CBB_add_bytes(&ticket, ticket_data, ticket_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_ticket_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                         CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return false;
  }

  // If |SSL_OP_NO_TICKET| is set then no extension will have been sent and
  // this function should never be called, even if the server tries to send the
  // extension.
  assert((SSL_get_options(ssl) & SSL_OP_NO_TICKET) == 0);

  if (CBS_len(contents) != 0) {
    return false;
  }

  hs->ticket_expected = true;
  return true;
}

static bool ext_ticket_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (!hs->ticket_expected) {
    return true;
  }

  // If |SSL_OP_NO_TICKET| is set, |ticket_expected| should never be true.
  assert((SSL_get_options(hs->ssl) & SSL_OP_NO_TICKET) == 0);

  if (!CBB_add_u16(out, TLSEXT_TYPE_session_ticket) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}


// Signature Algorithms.
//
// https://tools.ietf.org/html/rfc5246#section-7.4.1.4.1

static bool ext_sigalgs_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (hs->max_version < TLS1_2_VERSION) {
    return true;
  }

  CBB contents, sigalgs_cbb;
  if (!CBB_add_u16(out, TLSEXT_TYPE_signature_algorithms) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &sigalgs_cbb) ||
      !tls12_add_verify_sigalgs(ssl, &sigalgs_cbb) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_sigalgs_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                          CBS *contents) {
  hs->peer_sigalgs.Reset();
  if (contents == NULL) {
    return true;
  }

  CBS supported_signature_algorithms;
  if (!CBS_get_u16_length_prefixed(contents, &supported_signature_algorithms) ||
      CBS_len(contents) != 0 ||
      CBS_len(&supported_signature_algorithms) == 0 ||
      !tls1_parse_peer_sigalgs(hs, &supported_signature_algorithms)) {
    return false;
  }

  return true;
}


// OCSP Stapling.
//
// https://tools.ietf.org/html/rfc6066#section-8

static bool ext_ocsp_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->ocsp_stapling_enabled) {
    return true;
  }

  CBB contents;
  if (!CBB_add_u16(out, TLSEXT_TYPE_status_request) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u8(&contents, TLSEXT_STATUSTYPE_ocsp) ||
      !CBB_add_u16(&contents, 0 /* empty responder ID list */) ||
      !CBB_add_u16(&contents, 0 /* empty request extensions */) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_ocsp_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                       CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  // TLS 1.3 OCSP responses are included in the Certificate extensions.
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return false;
  }

  // OCSP stapling is forbidden on non-certificate ciphers.
  if (CBS_len(contents) != 0 ||
      !ssl_cipher_uses_certificate_auth(hs->new_cipher)) {
    return false;
  }

  // Note this does not check for resumption in TLS 1.2. Sending
  // status_request here does not make sense, but OpenSSL does so and the
  // specification does not say anything. Tolerate it but ignore it.

  hs->certificate_status_expected = true;
  return true;
}

static bool ext_ocsp_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                       CBS *contents) {
  if (contents == NULL) {
    return true;
  }

  uint8_t status_type;
  if (!CBS_get_u8(contents, &status_type)) {
    return false;
  }

  // We cannot decide whether OCSP stapling will occur yet because the correct
  // SSL_CTX might not have been selected.
  hs->ocsp_stapling_requested = status_type == TLSEXT_STATUSTYPE_ocsp;

  return true;
}

static bool ext_ocsp_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION ||
      !hs->ocsp_stapling_requested ||
      ssl->cert->ocsp_response == NULL ||
      ssl->s3->session_reused ||
      !ssl_cipher_uses_certificate_auth(hs->new_cipher)) {
    return true;
  }

  hs->certificate_status_expected = true;

  return CBB_add_u16(out, TLSEXT_TYPE_status_request) &&
         CBB_add_u16(out, 0 /* length */);
}


// Next protocol negotiation.
//
// https://htmlpreview.github.io/?https://github.com/agl/technotes/blob/master/nextprotoneg.html

static bool ext_npn_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->s3->initial_handshake_complete ||
      ssl->ctx->next_proto_select_cb == NULL ||
      SSL_is_dtls(ssl)) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_next_proto_neg) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}

static bool ext_npn_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return false;
  }

  // If any of these are false then we should never have sent the NPN
  // extension in the ClientHello and thus this function should never have been
  // called.
  assert(!ssl->s3->initial_handshake_complete);
  assert(!SSL_is_dtls(ssl));
  assert(ssl->ctx->next_proto_select_cb != NULL);

  if (!ssl->s3->alpn_selected.empty()) {
    // NPN and ALPN may not be negotiated in the same connection.
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    OPENSSL_PUT_ERROR(SSL, SSL_R_NEGOTIATED_BOTH_NPN_AND_ALPN);
    return false;
  }

  const uint8_t *const orig_contents = CBS_data(contents);
  const size_t orig_len = CBS_len(contents);

  while (CBS_len(contents) != 0) {
    CBS proto;
    if (!CBS_get_u8_length_prefixed(contents, &proto) ||
        CBS_len(&proto) == 0) {
      return false;
    }
  }

  uint8_t *selected;
  uint8_t selected_len;
  if (ssl->ctx->next_proto_select_cb(
          ssl, &selected, &selected_len, orig_contents, orig_len,
          ssl->ctx->next_proto_select_cb_arg) != SSL_TLSEXT_ERR_OK ||
      !ssl->s3->next_proto_negotiated.CopyFrom(
          MakeConstSpan(selected, selected_len))) {
    *out_alert = SSL_AD_INTERNAL_ERROR;
    return false;
  }

  hs->next_proto_neg_seen = true;
  return true;
}

static bool ext_npn_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return true;
  }

  if (contents != NULL && CBS_len(contents) != 0) {
    return false;
  }

  if (contents == NULL ||
      ssl->s3->initial_handshake_complete ||
      ssl->ctx->next_protos_advertised_cb == NULL ||
      SSL_is_dtls(ssl)) {
    return true;
  }

  hs->next_proto_neg_seen = true;
  return true;
}

static bool ext_npn_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  // |next_proto_neg_seen| might have been cleared when an ALPN extension was
  // parsed.
  if (!hs->next_proto_neg_seen) {
    return true;
  }

  const uint8_t *npa;
  unsigned npa_len;

  if (ssl->ctx->next_protos_advertised_cb(
          ssl, &npa, &npa_len, ssl->ctx->next_protos_advertised_cb_arg) !=
      SSL_TLSEXT_ERR_OK) {
    hs->next_proto_neg_seen = false;
    return true;
  }

  CBB contents;
  if (!CBB_add_u16(out, TLSEXT_TYPE_next_proto_neg) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_bytes(&contents, npa, npa_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// Signed certificate timestamps.
//
// https://tools.ietf.org/html/rfc6962#section-3.3.1

static bool ext_sct_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->signed_cert_timestamps_enabled) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_certificate_timestamp) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}

static bool ext_sct_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  // TLS 1.3 SCTs are included in the Certificate extensions.
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // If this is false then we should never have sent the SCT extension in the
  // ClientHello and thus this function should never have been called.
  assert(ssl->signed_cert_timestamps_enabled);

  if (!ssl_is_sct_list_valid(contents)) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // Session resumption uses the original session information. The extension
  // should not be sent on resumption, but RFC 6962 did not make it a
  // requirement, so tolerate this.
  //
  // TODO(davidben): Enforce this anyway.
  if (!ssl->s3->session_reused) {
    CRYPTO_BUFFER_free(hs->new_session->signed_cert_timestamp_list);
    hs->new_session->signed_cert_timestamp_list =
        CRYPTO_BUFFER_new_from_CBS(contents, ssl->ctx->pool);
    if (hs->new_session->signed_cert_timestamp_list == nullptr) {
      *out_alert = SSL_AD_INTERNAL_ERROR;
      return false;
    }
  }

  return true;
}

static bool ext_sct_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                      CBS *contents) {
  if (contents == NULL) {
    return true;
  }

  if (CBS_len(contents) != 0) {
    return false;
  }

  hs->scts_requested = true;
  return true;
}

static bool ext_sct_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  // The extension shouldn't be sent when resuming sessions.
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION ||
      ssl->s3->session_reused ||
      ssl->cert->signed_cert_timestamp_list == NULL) {
    return true;
  }

  CBB contents;
  return CBB_add_u16(out, TLSEXT_TYPE_certificate_timestamp) &&
         CBB_add_u16_length_prefixed(out, &contents) &&
         CBB_add_bytes(
             &contents,
             CRYPTO_BUFFER_data(ssl->cert->signed_cert_timestamp_list),
             CRYPTO_BUFFER_len(ssl->cert->signed_cert_timestamp_list)) &&
         CBB_flush(out);
}


// Application-level Protocol Negotiation.
//
// https://tools.ietf.org/html/rfc7301

static bool ext_alpn_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->alpn_client_proto_list == NULL ||
      ssl->s3->initial_handshake_complete) {
    return true;
  }

  CBB contents, proto_list;
  if (!CBB_add_u16(out, TLSEXT_TYPE_application_layer_protocol_negotiation) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &proto_list) ||
      !CBB_add_bytes(&proto_list, ssl->alpn_client_proto_list,
                     ssl->alpn_client_proto_list_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_alpn_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                       CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  assert(!ssl->s3->initial_handshake_complete);
  assert(ssl->alpn_client_proto_list != NULL);

  if (hs->next_proto_neg_seen) {
    // NPN and ALPN may not be negotiated in the same connection.
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    OPENSSL_PUT_ERROR(SSL, SSL_R_NEGOTIATED_BOTH_NPN_AND_ALPN);
    return false;
  }

  // The extension data consists of a ProtocolNameList which must have
  // exactly one ProtocolName. Each of these is length-prefixed.
  CBS protocol_name_list, protocol_name;
  if (!CBS_get_u16_length_prefixed(contents, &protocol_name_list) ||
      CBS_len(contents) != 0 ||
      !CBS_get_u8_length_prefixed(&protocol_name_list, &protocol_name) ||
      // Empty protocol names are forbidden.
      CBS_len(&protocol_name) == 0 ||
      CBS_len(&protocol_name_list) != 0) {
    return false;
  }

  if (!ssl_is_alpn_protocol_allowed(ssl, protocol_name)) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_INVALID_ALPN_PROTOCOL);
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  if (!ssl->s3->alpn_selected.CopyFrom(protocol_name)) {
    *out_alert = SSL_AD_INTERNAL_ERROR;
    return false;
  }

  return true;
}

bool ssl_is_alpn_protocol_allowed(const SSL *ssl,
                                  Span<const uint8_t> protocol) {
  if (ssl->alpn_client_proto_list == nullptr) {
    return false;
  }

  if (ssl->ctx->allow_unknown_alpn_protos) {
    return true;
  }

  // Check that the protocol name is one of the ones we advertised.
  CBS client_protocol_name_list, client_protocol_name;
  CBS_init(&client_protocol_name_list, ssl->alpn_client_proto_list,
           ssl->alpn_client_proto_list_len);
  while (CBS_len(&client_protocol_name_list) > 0) {
    if (!CBS_get_u8_length_prefixed(&client_protocol_name_list,
                                    &client_protocol_name)) {
      return false;
    }

    if (client_protocol_name == protocol) {
      return true;
    }
  }

  return false;
}

bool ssl_negotiate_alpn(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                        const SSL_CLIENT_HELLO *client_hello) {
  SSL *const ssl = hs->ssl;
  CBS contents;
  if (ssl->ctx->alpn_select_cb == NULL ||
      !ssl_client_hello_get_extension(
          client_hello, &contents,
          TLSEXT_TYPE_application_layer_protocol_negotiation)) {
    // Ignore ALPN if not configured or no extension was supplied.
    return true;
  }

  // ALPN takes precedence over NPN.
  hs->next_proto_neg_seen = false;

  CBS protocol_name_list;
  if (!CBS_get_u16_length_prefixed(&contents, &protocol_name_list) ||
      CBS_len(&contents) != 0 ||
      CBS_len(&protocol_name_list) < 2) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_PARSE_TLSEXT);
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // Validate the protocol list.
  CBS protocol_name_list_copy = protocol_name_list;
  while (CBS_len(&protocol_name_list_copy) > 0) {
    CBS protocol_name;

    if (!CBS_get_u8_length_prefixed(&protocol_name_list_copy, &protocol_name) ||
        // Empty protocol names are forbidden.
        CBS_len(&protocol_name) == 0) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_PARSE_TLSEXT);
      *out_alert = SSL_AD_DECODE_ERROR;
      return false;
    }
  }

  const uint8_t *selected;
  uint8_t selected_len;
  if (ssl->ctx->alpn_select_cb(
          ssl, &selected, &selected_len, CBS_data(&protocol_name_list),
          CBS_len(&protocol_name_list),
          ssl->ctx->alpn_select_cb_arg) == SSL_TLSEXT_ERR_OK) {
    if (!ssl->s3->alpn_selected.CopyFrom(
            MakeConstSpan(selected, selected_len))) {
      *out_alert = SSL_AD_INTERNAL_ERROR;
      return false;
    }
  }

  return true;
}

static bool ext_alpn_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->s3->alpn_selected.empty()) {
    return true;
  }

  CBB contents, proto_list, proto;
  if (!CBB_add_u16(out, TLSEXT_TYPE_application_layer_protocol_negotiation) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &proto_list) ||
      !CBB_add_u8_length_prefixed(&proto_list, &proto) ||
      !CBB_add_bytes(&proto, ssl->s3->alpn_selected.data(),
                     ssl->s3->alpn_selected.size()) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// Channel ID.
//
// https://tools.ietf.org/html/draft-balfanz-tls-channelid-01

static void ext_channel_id_init(SSL_HANDSHAKE *hs) {
  hs->ssl->s3->tlsext_channel_id_valid = false;
}

static bool ext_channel_id_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->tlsext_channel_id_enabled ||
      SSL_is_dtls(ssl)) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_channel_id) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}

static bool ext_channel_id_parse_serverhello(SSL_HANDSHAKE *hs,
                                             uint8_t *out_alert,
                                             CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  assert(!SSL_is_dtls(ssl));
  assert(ssl->tlsext_channel_id_enabled);

  if (CBS_len(contents) != 0) {
    return false;
  }

  ssl->s3->tlsext_channel_id_valid = true;
  return true;
}

static bool ext_channel_id_parse_clienthello(SSL_HANDSHAKE *hs,
                                             uint8_t *out_alert,
                                             CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL ||
      !ssl->tlsext_channel_id_enabled ||
      SSL_is_dtls(ssl)) {
    return true;
  }

  if (CBS_len(contents) != 0) {
    return false;
  }

  ssl->s3->tlsext_channel_id_valid = true;
  return true;
}

static bool ext_channel_id_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->s3->tlsext_channel_id_valid) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_channel_id) ||
      !CBB_add_u16(out, 0 /* length */)) {
    return false;
  }

  return true;
}


// Secure Real-time Transport Protocol (SRTP) extension.
//
// https://tools.ietf.org/html/rfc5764


static void ext_srtp_init(SSL_HANDSHAKE *hs) {
  hs->ssl->srtp_profile = NULL;
}

static bool ext_srtp_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  STACK_OF(SRTP_PROTECTION_PROFILE) *profiles = SSL_get_srtp_profiles(ssl);
  if (profiles == NULL ||
      sk_SRTP_PROTECTION_PROFILE_num(profiles) == 0) {
    return true;
  }

  CBB contents, profile_ids;
  if (!CBB_add_u16(out, TLSEXT_TYPE_srtp) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &profile_ids)) {
    return false;
  }

  for (const SRTP_PROTECTION_PROFILE *profile : profiles) {
    if (!CBB_add_u16(&profile_ids, profile->id)) {
      return false;
    }
  }

  if (!CBB_add_u8(&contents, 0 /* empty use_mki value */) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_srtp_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                       CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  // The extension consists of a u16-prefixed profile ID list containing a
  // single uint16_t profile ID, then followed by a u8-prefixed srtp_mki field.
  //
  // See https://tools.ietf.org/html/rfc5764#section-4.1.1
  CBS profile_ids, srtp_mki;
  uint16_t profile_id;
  if (!CBS_get_u16_length_prefixed(contents, &profile_ids) ||
      !CBS_get_u16(&profile_ids, &profile_id) ||
      CBS_len(&profile_ids) != 0 ||
      !CBS_get_u8_length_prefixed(contents, &srtp_mki) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_BAD_SRTP_PROTECTION_PROFILE_LIST);
    return false;
  }

  if (CBS_len(&srtp_mki) != 0) {
    // Must be no MKI, since we never offer one.
    OPENSSL_PUT_ERROR(SSL, SSL_R_BAD_SRTP_MKI_VALUE);
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  STACK_OF(SRTP_PROTECTION_PROFILE) *profiles = SSL_get_srtp_profiles(ssl);

  // Check to see if the server gave us something we support (and presumably
  // offered).
  for (const SRTP_PROTECTION_PROFILE *profile : profiles) {
    if (profile->id == profile_id) {
      ssl->srtp_profile = profile;
      return true;
    }
  }

  OPENSSL_PUT_ERROR(SSL, SSL_R_BAD_SRTP_PROTECTION_PROFILE_LIST);
  *out_alert = SSL_AD_ILLEGAL_PARAMETER;
  return false;
}

static bool ext_srtp_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                       CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  CBS profile_ids, srtp_mki;
  if (!CBS_get_u16_length_prefixed(contents, &profile_ids) ||
      CBS_len(&profile_ids) < 2 ||
      !CBS_get_u8_length_prefixed(contents, &srtp_mki) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_BAD_SRTP_PROTECTION_PROFILE_LIST);
    return false;
  }
  // Discard the MKI value for now.

  const STACK_OF(SRTP_PROTECTION_PROFILE) *server_profiles =
      SSL_get_srtp_profiles(ssl);

  // Pick the server's most preferred profile.
  for (const SRTP_PROTECTION_PROFILE *server_profile : server_profiles) {
    CBS profile_ids_tmp;
    CBS_init(&profile_ids_tmp, CBS_data(&profile_ids), CBS_len(&profile_ids));

    while (CBS_len(&profile_ids_tmp) > 0) {
      uint16_t profile_id;
      if (!CBS_get_u16(&profile_ids_tmp, &profile_id)) {
        return false;
      }

      if (server_profile->id == profile_id) {
        ssl->srtp_profile = server_profile;
        return true;
      }
    }
  }

  return true;
}

static bool ext_srtp_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->srtp_profile == NULL) {
    return true;
  }

  CBB contents, profile_ids;
  if (!CBB_add_u16(out, TLSEXT_TYPE_srtp) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &profile_ids) ||
      !CBB_add_u16(&profile_ids, ssl->srtp_profile->id) ||
      !CBB_add_u8(&contents, 0 /* empty MKI */) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// EC point formats.
//
// https://tools.ietf.org/html/rfc4492#section-5.1.2

static bool ext_ec_point_add_extension(SSL_HANDSHAKE *hs, CBB *out) {
  CBB contents, formats;
  if (!CBB_add_u16(out, TLSEXT_TYPE_ec_point_formats) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u8_length_prefixed(&contents, &formats) ||
      !CBB_add_u8(&formats, TLSEXT_ECPOINTFORMAT_uncompressed) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_ec_point_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  // The point format extension is unneccessary in TLS 1.3.
  if (hs->min_version >= TLS1_3_VERSION) {
    return true;
  }

  return ext_ec_point_add_extension(hs, out);
}

static bool ext_ec_point_parse_serverhello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                           CBS *contents) {
  if (contents == NULL) {
    return true;
  }

  if (ssl_protocol_version(hs->ssl) >= TLS1_3_VERSION) {
    return false;
  }

  CBS ec_point_format_list;
  if (!CBS_get_u8_length_prefixed(contents, &ec_point_format_list) ||
      CBS_len(contents) != 0) {
    return false;
  }

  // Per RFC 4492, section 5.1.2, implementations MUST support the uncompressed
  // point format.
  if (OPENSSL_memchr(CBS_data(&ec_point_format_list),
                     TLSEXT_ECPOINTFORMAT_uncompressed,
                     CBS_len(&ec_point_format_list)) == NULL) {
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  return true;
}

static bool ext_ec_point_parse_clienthello(SSL_HANDSHAKE *hs, uint8_t *out_alert,
                                          CBS *contents) {
  if (ssl_protocol_version(hs->ssl) >= TLS1_3_VERSION) {
    return true;
  }

  return ext_ec_point_parse_serverhello(hs, out_alert, contents);
}

static bool ext_ec_point_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    return true;
  }

  const uint32_t alg_k = hs->new_cipher->algorithm_mkey;
  const uint32_t alg_a = hs->new_cipher->algorithm_auth;
  const bool using_ecc = (alg_k & SSL_kECDHE) || (alg_a & SSL_aECDSA);

  if (!using_ecc) {
    return true;
  }

  return ext_ec_point_add_extension(hs, out);
}


// Pre Shared Key
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-18#section-4.2.6

static size_t ext_pre_shared_key_clienthello_length(SSL_HANDSHAKE *hs) {
  SSL *const ssl = hs->ssl;
  if (hs->max_version < TLS1_3_VERSION || ssl->session == NULL ||
      ssl_session_protocol_version(ssl->session) < TLS1_3_VERSION) {
    return 0;
  }

  size_t binder_len = EVP_MD_size(ssl_session_get_digest(ssl->session));
  return 15 + ssl->session->tlsext_ticklen + binder_len;
}

static bool ext_pre_shared_key_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  hs->needs_psk_binder = false;
  if (hs->max_version < TLS1_3_VERSION || ssl->session == NULL ||
      ssl_session_protocol_version(ssl->session) < TLS1_3_VERSION) {
    return true;
  }

  // Per draft-ietf-tls-tls13-21 section 4.1.4, skip offering the session if the
  // selected cipher in HelloRetryRequest does not match. This avoids performing
  // the transcript hash transformation for multiple hashes.
  if (hs->received_hello_retry_request &&
      ssl->session->cipher->algorithm_prf != hs->new_cipher->algorithm_prf) {
    return true;
  }

  struct OPENSSL_timeval now;
  ssl_get_current_time(ssl, &now);
  uint32_t ticket_age = 1000 * (now.tv_sec - ssl->session->time);
  uint32_t obfuscated_ticket_age = ticket_age + ssl->session->ticket_age_add;

  // Fill in a placeholder zero binder of the appropriate length. It will be
  // computed and filled in later after length prefixes are computed.
  uint8_t zero_binder[EVP_MAX_MD_SIZE] = {0};
  size_t binder_len = EVP_MD_size(ssl_session_get_digest(ssl->session));

  CBB contents, identity, ticket, binders, binder;
  if (!CBB_add_u16(out, TLSEXT_TYPE_pre_shared_key) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &identity) ||
      !CBB_add_u16_length_prefixed(&identity, &ticket) ||
      !CBB_add_bytes(&ticket, ssl->session->tlsext_tick,
                     ssl->session->tlsext_ticklen) ||
      !CBB_add_u32(&identity, obfuscated_ticket_age) ||
      !CBB_add_u16_length_prefixed(&contents, &binders) ||
      !CBB_add_u8_length_prefixed(&binders, &binder) ||
      !CBB_add_bytes(&binder, zero_binder, binder_len)) {
    return false;
  }

  hs->needs_psk_binder = true;
  return CBB_flush(out);
}

bool ssl_ext_pre_shared_key_parse_serverhello(SSL_HANDSHAKE *hs,
                                              uint8_t *out_alert,
                                              CBS *contents) {
  uint16_t psk_id;
  if (!CBS_get_u16(contents, &psk_id) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // We only advertise one PSK identity, so the only legal index is zero.
  if (psk_id != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_PSK_IDENTITY_NOT_FOUND);
    *out_alert = SSL_AD_UNKNOWN_PSK_IDENTITY;
    return false;
  }

  return true;
}

bool ssl_ext_pre_shared_key_parse_clienthello(
    SSL_HANDSHAKE *hs, CBS *out_ticket, CBS *out_binders,
    uint32_t *out_obfuscated_ticket_age, uint8_t *out_alert, CBS *contents) {
  // We only process the first PSK identity since we don't support pure PSK.
  CBS identities, binders;
  if (!CBS_get_u16_length_prefixed(contents, &identities) ||
      !CBS_get_u16_length_prefixed(&identities, out_ticket) ||
      !CBS_get_u32(&identities, out_obfuscated_ticket_age) ||
      !CBS_get_u16_length_prefixed(contents, &binders) ||
      CBS_len(&binders) == 0 ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  *out_binders = binders;

  // Check the syntax of the remaining identities, but do not process them.
  size_t num_identities = 1;
  while (CBS_len(&identities) != 0) {
    CBS unused_ticket;
    uint32_t unused_obfuscated_ticket_age;
    if (!CBS_get_u16_length_prefixed(&identities, &unused_ticket) ||
        !CBS_get_u32(&identities, &unused_obfuscated_ticket_age)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
      *out_alert = SSL_AD_DECODE_ERROR;
      return false;
    }

    num_identities++;
  }

  // Check the syntax of the binders. The value will be checked later if
  // resuming.
  size_t num_binders = 0;
  while (CBS_len(&binders) != 0) {
    CBS binder;
    if (!CBS_get_u8_length_prefixed(&binders, &binder)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
      *out_alert = SSL_AD_DECODE_ERROR;
      return false;
    }

    num_binders++;
  }

  if (num_identities != num_binders) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_PSK_IDENTITY_BINDER_COUNT_MISMATCH);
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  return true;
}

bool ssl_ext_pre_shared_key_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (!hs->ssl->s3->session_reused) {
    return true;
  }

  CBB contents;
  if (!CBB_add_u16(out, TLSEXT_TYPE_pre_shared_key) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      // We only consider the first identity for resumption
      !CBB_add_u16(&contents, 0) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// Pre-Shared Key Exchange Modes
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-18#section-4.2.7

static bool ext_psk_key_exchange_modes_add_clienthello(SSL_HANDSHAKE *hs,
                                                       CBB *out) {
  if (hs->max_version < TLS1_3_VERSION) {
    return true;
  }

  CBB contents, ke_modes;
  if (!CBB_add_u16(out, TLSEXT_TYPE_psk_key_exchange_modes) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u8_length_prefixed(&contents, &ke_modes) ||
      !CBB_add_u8(&ke_modes, SSL_PSK_DHE_KE)) {
    return false;
  }

  return CBB_flush(out);
}

static bool ext_psk_key_exchange_modes_parse_clienthello(SSL_HANDSHAKE *hs,
                                                         uint8_t *out_alert,
                                                         CBS *contents) {
  if (contents == NULL) {
    return true;
  }

  CBS ke_modes;
  if (!CBS_get_u8_length_prefixed(contents, &ke_modes) ||
      CBS_len(&ke_modes) == 0 ||
      CBS_len(contents) != 0) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // We only support tickets with PSK_DHE_KE.
  hs->accept_psk_mode = OPENSSL_memchr(CBS_data(&ke_modes), SSL_PSK_DHE_KE,
                                       CBS_len(&ke_modes)) != NULL;

  return true;
}


// Early Data Indication
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-18#section-4.2.8

static bool ext_early_data_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->cert->enable_early_data ||
      // Session must be 0-RTT capable.
      ssl->session == NULL ||
      ssl_session_protocol_version(ssl->session) < TLS1_3_VERSION ||
      ssl->session->ticket_max_early_data == 0 ||
      // The second ClientHello never offers early data.
      hs->received_hello_retry_request ||
      // In case ALPN preferences changed since this session was established,
      // avoid reporting a confusing value in |SSL_get0_alpn_selected|.
      (ssl->session->early_alpn_len != 0 &&
       !ssl_is_alpn_protocol_allowed(
           ssl, MakeConstSpan(ssl->session->early_alpn,
                              ssl->session->early_alpn_len)))) {
    return true;
  }

  hs->early_data_offered = true;

  if (!CBB_add_u16(out, TLSEXT_TYPE_early_data) ||
      !CBB_add_u16(out, 0) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_early_data_parse_serverhello(SSL_HANDSHAKE *hs,
                                             uint8_t *out_alert, CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL) {
    return true;
  }

  if (CBS_len(contents) != 0) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  if (!ssl->s3->session_reused) {
    *out_alert = SSL_AD_UNSUPPORTED_EXTENSION;
    OPENSSL_PUT_ERROR(SSL, SSL_R_UNEXPECTED_EXTENSION);
    return false;
  }

  ssl->s3->early_data_accepted = true;
  return true;
}

static bool ext_early_data_parse_clienthello(SSL_HANDSHAKE *hs,
                                             uint8_t *out_alert, CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == NULL ||
      ssl_protocol_version(ssl) < TLS1_3_VERSION) {
    return true;
  }

  if (CBS_len(contents) != 0) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  hs->early_data_offered = true;
  return true;
}

static bool ext_early_data_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (!hs->ssl->s3->early_data_accepted) {
    return true;
  }

  if (!CBB_add_u16(out, TLSEXT_TYPE_early_data) ||
      !CBB_add_u16(out, 0) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// Key Share
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-16#section-4.2.5

static bool ext_key_share_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (hs->max_version < TLS1_3_VERSION) {
    return true;
  }

  CBB contents, kse_bytes;
  if (!CBB_add_u16(out, TLSEXT_TYPE_key_share) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &kse_bytes)) {
    return false;
  }

  uint16_t group_id = hs->retry_group;
  if (hs->received_hello_retry_request) {
    // We received a HelloRetryRequest without a new curve, so there is no new
    // share to append. Leave |hs->key_share| as-is.
    if (group_id == 0 &&
        !CBB_add_bytes(&kse_bytes, hs->key_share_bytes.data(),
                       hs->key_share_bytes.size())) {
      return false;
    }
    hs->key_share_bytes.Reset();
    if (group_id == 0) {
      return CBB_flush(out);
    }
  } else {
    // Add a fake group. See draft-davidben-tls-grease-01.
    if (ssl->ctx->grease_enabled &&
        (!CBB_add_u16(&kse_bytes,
                      ssl_get_grease_value(hs, ssl_grease_group)) ||
         !CBB_add_u16(&kse_bytes, 1 /* length */) ||
         !CBB_add_u8(&kse_bytes, 0 /* one byte key share */))) {
      return false;
    }

    // Predict the most preferred group.
    Span<const uint16_t> groups = tls1_get_grouplist(ssl);
    if (groups.empty()) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_NO_GROUPS_SPECIFIED);
      return false;
    }

    group_id = groups[0];
  }

  hs->key_share = SSLKeyShare::Create(group_id);
  CBB key_exchange;
  if (!hs->key_share ||
      !CBB_add_u16(&kse_bytes, group_id) ||
      !CBB_add_u16_length_prefixed(&kse_bytes, &key_exchange) ||
      !hs->key_share->Offer(&key_exchange) ||
      !CBB_flush(&kse_bytes)) {
    return false;
  }

  // Save the contents of the extension to repeat it in the second ClientHello.
  if (!hs->received_hello_retry_request &&
      !hs->key_share_bytes.CopyFrom(
          MakeConstSpan(CBB_data(&kse_bytes), CBB_len(&kse_bytes)))) {
    return false;
  }

  return CBB_flush(out);
}

bool ssl_ext_key_share_parse_serverhello(SSL_HANDSHAKE *hs,
                                         Array<uint8_t> *out_secret,
                                         uint8_t *out_alert, CBS *contents) {
  CBS peer_key;
  uint16_t group_id;
  if (!CBS_get_u16(contents, &group_id) ||
      !CBS_get_u16_length_prefixed(contents, &peer_key) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  if (hs->key_share->GroupID() != group_id) {
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    OPENSSL_PUT_ERROR(SSL, SSL_R_WRONG_CURVE);
    return false;
  }

  if (!hs->key_share->Finish(out_secret, out_alert, peer_key)) {
    *out_alert = SSL_AD_INTERNAL_ERROR;
    return false;
  }

  hs->new_session->group_id = group_id;
  hs->key_share.reset();
  return true;
}

bool ssl_ext_key_share_parse_clienthello(SSL_HANDSHAKE *hs, bool *out_found,
                                         Array<uint8_t> *out_secret,
                                         uint8_t *out_alert, CBS *contents) {
  uint16_t group_id;
  CBS key_shares;
  if (!tls1_get_shared_group(hs, &group_id)) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_NO_SHARED_GROUP);
    *out_alert = SSL_AD_HANDSHAKE_FAILURE;
    return false;
  }

  if (!CBS_get_u16_length_prefixed(contents, &key_shares) ||
      CBS_len(contents) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    return false;
  }

  // Find the corresponding key share.
  CBS peer_key;
  CBS_init(&peer_key, NULL, 0);
  while (CBS_len(&key_shares) > 0) {
    uint16_t id;
    CBS peer_key_tmp;
    if (!CBS_get_u16(&key_shares, &id) ||
        !CBS_get_u16_length_prefixed(&key_shares, &peer_key_tmp) ||
        CBS_len(&peer_key_tmp) == 0) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
      return false;
    }

    if (id == group_id) {
      if (CBS_len(&peer_key) != 0) {
        OPENSSL_PUT_ERROR(SSL, SSL_R_DUPLICATE_KEY_SHARE);
        *out_alert = SSL_AD_ILLEGAL_PARAMETER;
        return false;
      }

      peer_key = peer_key_tmp;
      // Continue parsing the structure to keep peers honest.
    }
  }

  if (CBS_len(&peer_key) == 0) {
    *out_found = false;
    out_secret->Reset();
    return true;
  }

  // Compute the DH secret.
  Array<uint8_t> secret;
  ScopedCBB public_key;
  UniquePtr<SSLKeyShare> key_share = SSLKeyShare::Create(group_id);
  if (!key_share ||
      !CBB_init(public_key.get(), 32) ||
      !key_share->Accept(public_key.get(), &secret, out_alert, peer_key) ||
      !CBBFinishArray(public_key.get(), &hs->ecdh_public_key)) {
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  *out_secret = std::move(secret);
  *out_found = true;
  return true;
}

bool ssl_ext_key_share_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  uint16_t group_id;
  CBB kse_bytes, public_key;
  if (!tls1_get_shared_group(hs, &group_id) ||
      !CBB_add_u16(out, TLSEXT_TYPE_key_share) ||
      !CBB_add_u16_length_prefixed(out, &kse_bytes) ||
      !CBB_add_u16(&kse_bytes, group_id) ||
      !CBB_add_u16_length_prefixed(&kse_bytes, &public_key) ||
      !CBB_add_bytes(&public_key, hs->ecdh_public_key.data(),
                     hs->ecdh_public_key.size()) ||
      !CBB_flush(out)) {
    return false;
  }

  hs->ecdh_public_key.Reset();

  hs->new_session->group_id = group_id;
  return true;
}


// Supported Versions
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-16#section-4.2.1

static bool ext_supported_versions_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (hs->max_version <= TLS1_2_VERSION) {
    return true;
  }

  CBB contents, versions;
  if (!CBB_add_u16(out, TLSEXT_TYPE_supported_versions) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u8_length_prefixed(&contents, &versions)) {
    return false;
  }

  // Add a fake version. See draft-davidben-tls-grease-01.
  if (ssl->ctx->grease_enabled &&
      !CBB_add_u16(&versions, ssl_get_grease_value(hs, ssl_grease_version))) {
    return false;
  }

  if (!ssl_add_supported_versions(hs, &versions) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// Cookie
//
// https://tools.ietf.org/html/draft-ietf-tls-tls13-16#section-4.2.2

static bool ext_cookie_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  if (hs->cookie.empty()) {
    return true;
  }

  CBB contents, cookie;
  if (!CBB_add_u16(out, TLSEXT_TYPE_cookie) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &cookie) ||
      !CBB_add_bytes(&cookie, hs->cookie.data(), hs->cookie.size()) ||
      !CBB_flush(out)) {
    return false;
  }

  // The cookie is no longer needed in memory.
  hs->cookie.Reset();
  return true;
}


// Dummy PQ Padding extension
//
// Dummy post-quantum padding invovles the client (and later server) sending
// useless, random-looking bytes in an extension in their ClientHello or
// ServerHello. These extensions are sized to simulate a post-quantum
// key-exchange and so enable measurement of the latency impact of the
// additional bandwidth.

static bool ext_dummy_pq_padding_add(CBB *out, size_t len) {
  CBB contents;
  uint8_t *buffer;
  if (!CBB_add_u16(out, TLSEXT_TYPE_dummy_pq_padding) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_space(&contents, &buffer, len)) {
    return false;
  }

  // The length is used as the nonce so that different length extensions have
  // different contents. There's no reason this has to be the case, it just
  // makes things a little more obvious in a packet dump.
  uint8_t nonce[12] = {0};
  memcpy(nonce, &len, sizeof(len));

  memset(buffer, 0, len);
  static const uint8_t kZeroKey[32] = {0};
  CRYPTO_chacha_20(buffer, buffer, len, kZeroKey, nonce, 0);

  return CBB_flush(out);
}

static bool ext_dummy_pq_padding_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  const size_t len = hs->ssl->dummy_pq_padding_len;
  if (len == 0) {
    return true;
  }

  return ext_dummy_pq_padding_add(out, len);
}

static bool ext_dummy_pq_padding_parse_serverhello(SSL_HANDSHAKE *hs,
                                                   uint8_t *out_alert,
                                                   CBS *contents) {
  if (contents == nullptr) {
    return true;
  }

  if (CBS_len(contents) != hs->ssl->dummy_pq_padding_len) {
    return false;
  }

  hs->ssl->did_dummy_pq_padding = true;
  return true;
}

static bool ext_dummy_pq_padding_parse_clienthello(SSL_HANDSHAKE *hs,
                                                   uint8_t *out_alert,
                                                   CBS *contents) {
  if (contents != nullptr &&
      0 < CBS_len(contents) && CBS_len(contents) < (1 << 12)) {
    hs->dummy_pq_padding_len = CBS_len(contents);
  }

  return true;
}

static bool ext_dummy_pq_padding_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  if (!hs->dummy_pq_padding_len) {
    return true;
  }

  return ext_dummy_pq_padding_add(out, hs->dummy_pq_padding_len);
}

// Negotiated Groups
//
// https://tools.ietf.org/html/rfc4492#section-5.1.2
// https://tools.ietf.org/html/draft-ietf-tls-tls13-16#section-4.2.4

static bool ext_supported_groups_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  CBB contents, groups_bytes;
  if (!CBB_add_u16(out, TLSEXT_TYPE_supported_groups) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16_length_prefixed(&contents, &groups_bytes)) {
    return false;
  }

  // Add a fake group. See draft-davidben-tls-grease-01.
  if (ssl->ctx->grease_enabled &&
      !CBB_add_u16(&groups_bytes,
                   ssl_get_grease_value(hs, ssl_grease_group))) {
    return false;
  }

  for (uint16_t group : tls1_get_grouplist(ssl)) {
    if (!CBB_add_u16(&groups_bytes, group)) {
      return false;
    }
  }

  return CBB_flush(out);
}

static bool ext_supported_groups_parse_serverhello(SSL_HANDSHAKE *hs,
                                                   uint8_t *out_alert,
                                                   CBS *contents) {
  // This extension is not expected to be echoed by servers in TLS 1.2, but some
  // BigIP servers send it nonetheless, so do not enforce this.
  return true;
}

static bool parse_u16_array(const CBS *cbs, Array<uint16_t> *out) {
  CBS copy = *cbs;
  if ((CBS_len(&copy) & 1) != 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    return false;
  }

  Array<uint16_t> ret;
  if (!ret.Init(CBS_len(&copy) / 2)) {
    return false;
  }
  for (size_t i = 0; i < ret.size(); i++) {
    if (!CBS_get_u16(&copy, &ret[i])) {
      OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
      return false;
    }
  }

  assert(CBS_len(&copy) == 0);
  *out = std::move(ret);
  return 1;
}

static bool ext_supported_groups_parse_clienthello(SSL_HANDSHAKE *hs,
                                                  uint8_t *out_alert,
                                                   CBS *contents) {
  if (contents == NULL) {
    return true;
  }

  CBS supported_group_list;
  if (!CBS_get_u16_length_prefixed(contents, &supported_group_list) ||
      CBS_len(&supported_group_list) == 0 ||
      CBS_len(contents) != 0 ||
      !parse_u16_array(&supported_group_list, &hs->peer_supported_group_list)) {
    return false;
  }

  return true;
}

// Token Binding
//
// https://tools.ietf.org/html/draft-ietf-tokbind-negotiation-10

// The Token Binding version number currently matches the draft number of
// draft-ietf-tokbind-protocol, and when published as an RFC it will be 0x0100.
// Since there are no wire changes to the protocol from draft 13 through the
// current draft (16), this implementation supports all versions in that range.
static uint16_t kTokenBindingMaxVersion = 16;
static uint16_t kTokenBindingMinVersion = 13;

static bool ext_token_binding_add_clienthello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  if (ssl->token_binding_params == nullptr || SSL_is_dtls(ssl)) {
    return true;
  }

  CBB contents, params;
  if (!CBB_add_u16(out, TLSEXT_TYPE_token_binding) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16(&contents, kTokenBindingMaxVersion) ||
      !CBB_add_u8_length_prefixed(&contents, &params) ||
      !CBB_add_bytes(&params, ssl->token_binding_params,
                     ssl->token_binding_params_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

static bool ext_token_binding_parse_serverhello(SSL_HANDSHAKE *hs,
                                                uint8_t *out_alert,
                                                CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == nullptr) {
    return true;
  }

  CBS params_list;
  uint16_t version;
  uint8_t param;
  if (!CBS_get_u16(contents, &version) ||
      !CBS_get_u8_length_prefixed(contents, &params_list) ||
      !CBS_get_u8(&params_list, &param) ||
      CBS_len(&params_list) > 0 ||
      CBS_len(contents) > 0) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // The server-negotiated version must be less than or equal to our version.
  if (version > kTokenBindingMaxVersion) {
    *out_alert = SSL_AD_ILLEGAL_PARAMETER;
    return false;
  }

  // If the server-selected version is less than what we support, then Token
  // Binding wasn't negotiated (but the extension was parsed successfully).
  if (version < kTokenBindingMinVersion) {
    return true;
  }

  for (size_t i = 0; i < ssl->token_binding_params_len; ++i) {
    if (param == ssl->token_binding_params[i]) {
      ssl->negotiated_token_binding_param = param;
      ssl->token_binding_negotiated = true;
      return true;
    }
  }

  *out_alert = SSL_AD_ILLEGAL_PARAMETER;
  return false;
}

// select_tb_param looks for the first token binding param in
// |ssl->token_binding_params| that is also in |params| and puts it in
// |ssl->negotiated_token_binding_param|. It returns true if a token binding
// param is found, and false otherwise.
static bool select_tb_param(SSL *ssl, Span<const uint8_t> peer_params) {
  for (size_t i = 0; i < ssl->token_binding_params_len; ++i) {
    uint8_t tb_param = ssl->token_binding_params[i];
    for (uint8_t peer_param : peer_params) {
      if (tb_param == peer_param) {
        ssl->negotiated_token_binding_param = tb_param;
        return true;
      }
    }
  }
  return false;
}

static bool ext_token_binding_parse_clienthello(SSL_HANDSHAKE *hs,
                                                uint8_t *out_alert,
                                                CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == nullptr || ssl->token_binding_params == nullptr) {
    return true;
  }

  CBS params;
  uint16_t version;
  if (!CBS_get_u16(contents, &version) ||
      !CBS_get_u8_length_prefixed(contents, &params) ||
      CBS_len(&params) == 0 ||
      CBS_len(contents) > 0) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return false;
  }

  // If the client-selected version is less than what we support, then Token
  // Binding wasn't negotiated (but the extension was parsed successfully).
  if (version < kTokenBindingMinVersion) {
    return true;
  }

  // If the client-selected version is higher than we support, use our max
  // version. Otherwise, use the client's version.
  hs->negotiated_token_binding_version =
      std::min(version, kTokenBindingMaxVersion);
  if (!select_tb_param(ssl, params)) {
    return true;
  }

  ssl->token_binding_negotiated = true;
  return true;
}

static bool ext_token_binding_add_serverhello(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;

  if (!ssl->token_binding_negotiated) {
    return true;
  }

  CBB contents, params;
  if (!CBB_add_u16(out, TLSEXT_TYPE_token_binding) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_u16(&contents, hs->negotiated_token_binding_version) ||
      !CBB_add_u8_length_prefixed(&contents, &params) ||
      !CBB_add_u8(&params, ssl->negotiated_token_binding_param) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}

// QUIC Transport Parameters

static bool ext_quic_transport_params_add_clienthello(SSL_HANDSHAKE *hs,
                                                      CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->quic_transport_params || hs->max_version <= TLS1_2_VERSION) {
    return true;
  }

  CBB contents;
  if (!CBB_add_u16(out, TLSEXT_TYPE_quic_transport_parameters) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_bytes(&contents, ssl->quic_transport_params,
                     ssl->quic_transport_params_len) ||
      !CBB_flush(out)) {
    return false;
  }
  return true;
}

static bool ext_quic_transport_params_parse_serverhello(SSL_HANDSHAKE *hs,
                                                        uint8_t *out_alert,
                                                        CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (contents == nullptr) {
    return true;
  }
  // QUIC requires TLS 1.3.
  if (ssl_protocol_version(ssl) < TLS1_3_VERSION) {
    *out_alert = SSL_AD_UNSUPPORTED_EXTENSION;
    return false;
  }

  return ssl->s3->peer_quic_transport_params.CopyFrom(*contents);
}

static bool ext_quic_transport_params_parse_clienthello(SSL_HANDSHAKE *hs,
                                                        uint8_t *out_alert,
                                                        CBS *contents) {
  SSL *const ssl = hs->ssl;
  if (!contents || !ssl->quic_transport_params) {
    return true;
  }
  // Ignore the extension before TLS 1.3.
  if (ssl_protocol_version(ssl) < TLS1_3_VERSION) {
    return true;
  }

  return ssl->s3->peer_quic_transport_params.CopyFrom(*contents);
}

static bool ext_quic_transport_params_add_serverhello(SSL_HANDSHAKE *hs,
                                                      CBB *out) {
  SSL *const ssl = hs->ssl;
  if (!ssl->quic_transport_params) {
    return true;
  }

  CBB contents;
  if (!CBB_add_u16(out, TLSEXT_TYPE_quic_transport_parameters) ||
      !CBB_add_u16_length_prefixed(out, &contents) ||
      !CBB_add_bytes(&contents, ssl->quic_transport_params,
                     ssl->quic_transport_params_len) ||
      !CBB_flush(out)) {
    return false;
  }

  return true;
}


// kExtensions contains all the supported extensions.
static const struct tls_extension kExtensions[] = {
  {
    TLSEXT_TYPE_renegotiate,
    NULL,
    ext_ri_add_clienthello,
    ext_ri_parse_serverhello,
    ext_ri_parse_clienthello,
    ext_ri_add_serverhello,
  },
  {
    TLSEXT_TYPE_server_name,
    NULL,
    ext_sni_add_clienthello,
    ext_sni_parse_serverhello,
    ext_sni_parse_clienthello,
    ext_sni_add_serverhello,
  },
  {
    TLSEXT_TYPE_extended_master_secret,
    NULL,
    ext_ems_add_clienthello,
    ext_ems_parse_serverhello,
    ext_ems_parse_clienthello,
    ext_ems_add_serverhello,
  },
  {
    TLSEXT_TYPE_session_ticket,
    NULL,
    ext_ticket_add_clienthello,
    ext_ticket_parse_serverhello,
    // Ticket extension client parsing is handled in ssl_session.c
    ignore_parse_clienthello,
    ext_ticket_add_serverhello,
  },
  {
    TLSEXT_TYPE_signature_algorithms,
    NULL,
    ext_sigalgs_add_clienthello,
    forbid_parse_serverhello,
    ext_sigalgs_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_status_request,
    NULL,
    ext_ocsp_add_clienthello,
    ext_ocsp_parse_serverhello,
    ext_ocsp_parse_clienthello,
    ext_ocsp_add_serverhello,
  },
  {
    TLSEXT_TYPE_next_proto_neg,
    NULL,
    ext_npn_add_clienthello,
    ext_npn_parse_serverhello,
    ext_npn_parse_clienthello,
    ext_npn_add_serverhello,
  },
  {
    TLSEXT_TYPE_certificate_timestamp,
    NULL,
    ext_sct_add_clienthello,
    ext_sct_parse_serverhello,
    ext_sct_parse_clienthello,
    ext_sct_add_serverhello,
  },
  {
    TLSEXT_TYPE_application_layer_protocol_negotiation,
    NULL,
    ext_alpn_add_clienthello,
    ext_alpn_parse_serverhello,
    // ALPN is negotiated late in |ssl_negotiate_alpn|.
    ignore_parse_clienthello,
    ext_alpn_add_serverhello,
  },
  {
    TLSEXT_TYPE_channel_id,
    ext_channel_id_init,
    ext_channel_id_add_clienthello,
    ext_channel_id_parse_serverhello,
    ext_channel_id_parse_clienthello,
    ext_channel_id_add_serverhello,
  },
  {
    TLSEXT_TYPE_srtp,
    ext_srtp_init,
    ext_srtp_add_clienthello,
    ext_srtp_parse_serverhello,
    ext_srtp_parse_clienthello,
    ext_srtp_add_serverhello,
  },
  {
    TLSEXT_TYPE_ec_point_formats,
    NULL,
    ext_ec_point_add_clienthello,
    ext_ec_point_parse_serverhello,
    ext_ec_point_parse_clienthello,
    ext_ec_point_add_serverhello,
  },
  {
    TLSEXT_TYPE_key_share,
    NULL,
    ext_key_share_add_clienthello,
    forbid_parse_serverhello,
    ignore_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_psk_key_exchange_modes,
    NULL,
    ext_psk_key_exchange_modes_add_clienthello,
    forbid_parse_serverhello,
    ext_psk_key_exchange_modes_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_early_data,
    NULL,
    ext_early_data_add_clienthello,
    ext_early_data_parse_serverhello,
    ext_early_data_parse_clienthello,
    ext_early_data_add_serverhello,
  },
  {
    TLSEXT_TYPE_supported_versions,
    NULL,
    ext_supported_versions_add_clienthello,
    forbid_parse_serverhello,
    ignore_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_cookie,
    NULL,
    ext_cookie_add_clienthello,
    forbid_parse_serverhello,
    ignore_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_dummy_pq_padding,
    NULL,
    ext_dummy_pq_padding_add_clienthello,
    ext_dummy_pq_padding_parse_serverhello,
    ext_dummy_pq_padding_parse_clienthello,
    ext_dummy_pq_padding_add_serverhello,
  },
  {
    TLSEXT_TYPE_quic_transport_parameters,
    NULL,
    ext_quic_transport_params_add_clienthello,
    ext_quic_transport_params_parse_serverhello,
    ext_quic_transport_params_parse_clienthello,
    ext_quic_transport_params_add_serverhello,
  },
  // The final extension must be non-empty. WebSphere Application Server 7.0 is
  // intolerant to the last extension being zero-length. See
  // https://crbug.com/363583.
  {
    TLSEXT_TYPE_supported_groups,
    NULL,
    ext_supported_groups_add_clienthello,
    ext_supported_groups_parse_serverhello,
    ext_supported_groups_parse_clienthello,
    dont_add_serverhello,
  },
  {
    TLSEXT_TYPE_token_binding,
    NULL,
    ext_token_binding_add_clienthello,
    ext_token_binding_parse_serverhello,
    ext_token_binding_parse_clienthello,
    ext_token_binding_add_serverhello,
  },
};

#define kNumExtensions (sizeof(kExtensions) / sizeof(struct tls_extension))

static_assert(kNumExtensions <=
                  sizeof(((SSL_HANDSHAKE *)NULL)->extensions.sent) * 8,
              "too many extensions for sent bitset");
static_assert(kNumExtensions <=
                  sizeof(((SSL_HANDSHAKE *)NULL)->extensions.received) * 8,
              "too many extensions for received bitset");

static const struct tls_extension *tls_extension_find(uint32_t *out_index,
                                                      uint16_t value) {
  unsigned i;
  for (i = 0; i < kNumExtensions; i++) {
    if (kExtensions[i].value == value) {
      *out_index = i;
      return &kExtensions[i];
    }
  }

  return NULL;
}

int ssl_add_clienthello_tlsext(SSL_HANDSHAKE *hs, CBB *out, size_t header_len) {
  SSL *const ssl = hs->ssl;
  // Don't add extensions for SSLv3 unless doing secure renegotiation.
  if (hs->client_version == SSL3_VERSION &&
      !ssl->s3->send_connection_binding) {
    return 1;
  }

  CBB extensions;
  if (!CBB_add_u16_length_prefixed(out, &extensions)) {
    OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
    return 0;
  }

  hs->extensions.sent = 0;
  hs->custom_extensions.sent = 0;

  for (size_t i = 0; i < kNumExtensions; i++) {
    if (kExtensions[i].init != NULL) {
      kExtensions[i].init(hs);
    }
  }

  uint16_t grease_ext1 = 0;
  if (ssl->ctx->grease_enabled) {
    // Add a fake empty extension. See draft-davidben-tls-grease-01.
    grease_ext1 = ssl_get_grease_value(hs, ssl_grease_extension1);
    if (!CBB_add_u16(&extensions, grease_ext1) ||
        !CBB_add_u16(&extensions, 0 /* zero length */)) {
      OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
      return 0;
    }
  }

  for (size_t i = 0; i < kNumExtensions; i++) {
    const size_t len_before = CBB_len(&extensions);
    if (!kExtensions[i].add_clienthello(hs, &extensions)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_ERROR_ADDING_EXTENSION);
      ERR_add_error_dataf("extension %u", (unsigned)kExtensions[i].value);
      return 0;
    }

    if (CBB_len(&extensions) != len_before) {
      hs->extensions.sent |= (1u << i);
    }
  }

  if (!custom_ext_add_clienthello(hs, &extensions)) {
    OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
    return 0;
  }

  if (ssl->ctx->grease_enabled) {
    // Add a fake non-empty extension. See draft-davidben-tls-grease-01.
    uint16_t grease_ext2 = ssl_get_grease_value(hs, ssl_grease_extension2);

    // The two fake extensions must not have the same value. GREASE values are
    // of the form 0x1a1a, 0x2a2a, 0x3a3a, etc., so XOR to generate a different
    // one.
    if (grease_ext1 == grease_ext2) {
      grease_ext2 ^= 0x1010;
    }

    if (!CBB_add_u16(&extensions, grease_ext2) ||
        !CBB_add_u16(&extensions, 1 /* one byte length */) ||
        !CBB_add_u8(&extensions, 0 /* single zero byte as contents */)) {
      OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
      return 0;
    }
  }

  if (!SSL_is_dtls(ssl)) {
    size_t psk_extension_len = ext_pre_shared_key_clienthello_length(hs);
    header_len += 2 + CBB_len(&extensions) + psk_extension_len;
    if (header_len > 0xff && header_len < 0x200) {
      // Add padding to workaround bugs in F5 terminators. See RFC 7685.
      //
      // NB: because this code works out the length of all existing extensions
      // it MUST always appear last.
      size_t padding_len = 0x200 - header_len;
      // Extensions take at least four bytes to encode. Always include at least
      // one byte of data if including the extension. WebSphere Application
      // Server 7.0 is intolerant to the last extension being zero-length. See
      // https://crbug.com/363583.
      if (padding_len >= 4 + 1) {
        padding_len -= 4;
      } else {
        padding_len = 1;
      }

      uint8_t *padding_bytes;
      if (!CBB_add_u16(&extensions, TLSEXT_TYPE_padding) ||
          !CBB_add_u16(&extensions, padding_len) ||
          !CBB_add_space(&extensions, &padding_bytes, padding_len)) {
        OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
        return 0;
      }

      OPENSSL_memset(padding_bytes, 0, padding_len);
    }
  }

  // The PSK extension must be last, including after the padding.
  if (!ext_pre_shared_key_add_clienthello(hs, &extensions)) {
    OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
    return 0;
  }

  // Discard empty extensions blocks.
  if (CBB_len(&extensions) == 0) {
    CBB_discard_child(out);
  }

  return CBB_flush(out);
}

int ssl_add_serverhello_tlsext(SSL_HANDSHAKE *hs, CBB *out) {
  SSL *const ssl = hs->ssl;
  CBB extensions;
  if (!CBB_add_u16_length_prefixed(out, &extensions)) {
    goto err;
  }

  for (unsigned i = 0; i < kNumExtensions; i++) {
    if (!(hs->extensions.received & (1u << i))) {
      // Don't send extensions that were not received.
      continue;
    }

    if (!kExtensions[i].add_serverhello(hs, &extensions)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_ERROR_ADDING_EXTENSION);
      ERR_add_error_dataf("extension %u", (unsigned)kExtensions[i].value);
      goto err;
    }
  }

  if (!custom_ext_add_serverhello(hs, &extensions)) {
    goto err;
  }

  // Discard empty extensions blocks before TLS 1.3.
  if (ssl_protocol_version(ssl) < TLS1_3_VERSION &&
      CBB_len(&extensions) == 0) {
    CBB_discard_child(out);
  }

  return CBB_flush(out);

err:
  OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
  return 0;
}

static int ssl_scan_clienthello_tlsext(SSL_HANDSHAKE *hs,
                                       const SSL_CLIENT_HELLO *client_hello,
                                       int *out_alert) {
  SSL *const ssl = hs->ssl;
  for (size_t i = 0; i < kNumExtensions; i++) {
    if (kExtensions[i].init != NULL) {
      kExtensions[i].init(hs);
    }
  }

  hs->extensions.received = 0;
  hs->custom_extensions.received = 0;
  CBS extensions;
  CBS_init(&extensions, client_hello->extensions, client_hello->extensions_len);
  while (CBS_len(&extensions) != 0) {
    uint16_t type;
    CBS extension;

    // Decode the next extension.
    if (!CBS_get_u16(&extensions, &type) ||
        !CBS_get_u16_length_prefixed(&extensions, &extension)) {
      *out_alert = SSL_AD_DECODE_ERROR;
      return 0;
    }

    // RFC 5746 made the existence of extensions in SSL 3.0 somewhat
    // ambiguous. Ignore all but the renegotiation_info extension.
    if (ssl->version == SSL3_VERSION && type != TLSEXT_TYPE_renegotiate) {
      continue;
    }

    unsigned ext_index;
    const struct tls_extension *const ext =
        tls_extension_find(&ext_index, type);

    if (ext == NULL) {
      if (!custom_ext_parse_clienthello(hs, out_alert, type, &extension)) {
        OPENSSL_PUT_ERROR(SSL, SSL_R_ERROR_PARSING_EXTENSION);
        return 0;
      }
      continue;
    }

    hs->extensions.received |= (1u << ext_index);
    uint8_t alert = SSL_AD_DECODE_ERROR;
    if (!ext->parse_clienthello(hs, &alert, &extension)) {
      *out_alert = alert;
      OPENSSL_PUT_ERROR(SSL, SSL_R_ERROR_PARSING_EXTENSION);
      ERR_add_error_dataf("extension %u", (unsigned)type);
      return 0;
    }
  }

  for (size_t i = 0; i < kNumExtensions; i++) {
    if (hs->extensions.received & (1u << i)) {
      continue;
    }

    CBS *contents = NULL, fake_contents;
    static const uint8_t kFakeRenegotiateExtension[] = {0};
    if (kExtensions[i].value == TLSEXT_TYPE_renegotiate &&
        ssl_client_cipher_list_contains_cipher(client_hello,
                                               SSL3_CK_SCSV & 0xffff)) {
      // The renegotiation SCSV was received so pretend that we received a
      // renegotiation extension.
      CBS_init(&fake_contents, kFakeRenegotiateExtension,
               sizeof(kFakeRenegotiateExtension));
      contents = &fake_contents;
      hs->extensions.received |= (1u << i);
    }

    // Extension wasn't observed so call the callback with a NULL
    // parameter.
    uint8_t alert = SSL_AD_DECODE_ERROR;
    if (!kExtensions[i].parse_clienthello(hs, &alert, contents)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_MISSING_EXTENSION);
      ERR_add_error_dataf("extension %u", (unsigned)kExtensions[i].value);
      *out_alert = alert;
      return 0;
    }
  }

  return 1;
}

int ssl_parse_clienthello_tlsext(SSL_HANDSHAKE *hs,
                                 const SSL_CLIENT_HELLO *client_hello) {
  SSL *const ssl = hs->ssl;
  int alert = SSL_AD_DECODE_ERROR;
  if (ssl_scan_clienthello_tlsext(hs, client_hello, &alert) <= 0) {
    ssl_send_alert(ssl, SSL3_AL_FATAL, alert);
    return 0;
  }

  if (ssl_check_clienthello_tlsext(hs) <= 0) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_CLIENTHELLO_TLSEXT);
    return 0;
  }

  return 1;
}

static int ssl_scan_serverhello_tlsext(SSL_HANDSHAKE *hs, CBS *cbs,
                                       int *out_alert) {
  SSL *const ssl = hs->ssl;
  // Before TLS 1.3, ServerHello extensions blocks may be omitted if empty.
  if (CBS_len(cbs) == 0 && ssl_protocol_version(ssl) < TLS1_3_VERSION) {
    return 1;
  }

  // Decode the extensions block and check it is valid.
  CBS extensions;
  if (!CBS_get_u16_length_prefixed(cbs, &extensions) ||
      !tls1_check_duplicate_extensions(&extensions)) {
    *out_alert = SSL_AD_DECODE_ERROR;
    return 0;
  }

  uint32_t received = 0;
  while (CBS_len(&extensions) != 0) {
    uint16_t type;
    CBS extension;

    // Decode the next extension.
    if (!CBS_get_u16(&extensions, &type) ||
        !CBS_get_u16_length_prefixed(&extensions, &extension)) {
      *out_alert = SSL_AD_DECODE_ERROR;
      return 0;
    }

    unsigned ext_index;
    const struct tls_extension *const ext =
        tls_extension_find(&ext_index, type);

    if (ext == NULL) {
      hs->received_custom_extension = true;
      if (!custom_ext_parse_serverhello(hs, out_alert, type, &extension)) {
        return 0;
      }
      continue;
    }

    static_assert(kNumExtensions <= sizeof(hs->extensions.sent) * 8,
                  "too many bits");

    if (!(hs->extensions.sent & (1u << ext_index)) &&
        type != TLSEXT_TYPE_renegotiate) {
      // If the extension was never sent then it is illegal, except for the
      // renegotiation extension which, in SSL 3.0, is signaled via SCSV.
      OPENSSL_PUT_ERROR(SSL, SSL_R_UNEXPECTED_EXTENSION);
      ERR_add_error_dataf("extension :%u", (unsigned)type);
      *out_alert = SSL_AD_UNSUPPORTED_EXTENSION;
      return 0;
    }

    received |= (1u << ext_index);

    uint8_t alert = SSL_AD_DECODE_ERROR;
    if (!ext->parse_serverhello(hs, &alert, &extension)) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_ERROR_PARSING_EXTENSION);
      ERR_add_error_dataf("extension %u", (unsigned)type);
      *out_alert = alert;
      return 0;
    }
  }

  for (size_t i = 0; i < kNumExtensions; i++) {
    if (!(received & (1u << i))) {
      // Extension wasn't observed so call the callback with a NULL
      // parameter.
      uint8_t alert = SSL_AD_DECODE_ERROR;
      if (!kExtensions[i].parse_serverhello(hs, &alert, NULL)) {
        OPENSSL_PUT_ERROR(SSL, SSL_R_MISSING_EXTENSION);
        ERR_add_error_dataf("extension %u", (unsigned)kExtensions[i].value);
        *out_alert = alert;
        return 0;
      }
    }
  }

  return 1;
}

static int ssl_check_clienthello_tlsext(SSL_HANDSHAKE *hs) {
  SSL *const ssl = hs->ssl;

  if (ssl->token_binding_negotiated &&
      !(SSL_get_secure_renegotiation_support(ssl) &&
        SSL_get_extms_support(ssl))) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_NEGOTIATED_TB_WITHOUT_EMS_OR_RI);
    ssl_send_alert(ssl, SSL3_AL_FATAL, SSL_AD_UNSUPPORTED_EXTENSION);
    return -1;
  }

  int ret = SSL_TLSEXT_ERR_NOACK;
  int al = SSL_AD_UNRECOGNIZED_NAME;

  if (ssl->ctx->tlsext_servername_callback != 0) {
    ret = ssl->ctx->tlsext_servername_callback(ssl, &al,
                                               ssl->ctx->tlsext_servername_arg);
  } else if (ssl->session_ctx->tlsext_servername_callback != 0) {
    ret = ssl->session_ctx->tlsext_servername_callback(
        ssl, &al, ssl->session_ctx->tlsext_servername_arg);
  }

  switch (ret) {
    case SSL_TLSEXT_ERR_ALERT_FATAL:
      ssl_send_alert(ssl, SSL3_AL_FATAL, al);
      return -1;

    case SSL_TLSEXT_ERR_NOACK:
      hs->should_ack_sni = false;
      return 1;

    default:
      return 1;
  }
}

int ssl_parse_serverhello_tlsext(SSL_HANDSHAKE *hs, CBS *cbs) {
  SSL *const ssl = hs->ssl;
  int alert = SSL_AD_DECODE_ERROR;
  if (ssl_scan_serverhello_tlsext(hs, cbs, &alert) <= 0) {
    ssl_send_alert(ssl, SSL3_AL_FATAL, alert);
    return 0;
  }

  return 1;
}

static enum ssl_ticket_aead_result_t decrypt_ticket_with_cipher_ctx(
    uint8_t **out, size_t *out_len, EVP_CIPHER_CTX *cipher_ctx,
    HMAC_CTX *hmac_ctx, const uint8_t *ticket, size_t ticket_len) {
  size_t iv_len = EVP_CIPHER_CTX_iv_length(cipher_ctx);

  // Check the MAC at the end of the ticket.
  uint8_t mac[EVP_MAX_MD_SIZE];
  size_t mac_len = HMAC_size(hmac_ctx);
  if (ticket_len < SSL_TICKET_KEY_NAME_LEN + iv_len + 1 + mac_len) {
    // The ticket must be large enough for key name, IV, data, and MAC.
    return ssl_ticket_aead_ignore_ticket;
  }
  HMAC_Update(hmac_ctx, ticket, ticket_len - mac_len);
  HMAC_Final(hmac_ctx, mac, NULL);
  int mac_ok =
      CRYPTO_memcmp(mac, ticket + (ticket_len - mac_len), mac_len) == 0;
#if defined(BORINGSSL_UNSAFE_FUZZER_MODE)
  mac_ok = 1;
#endif
  if (!mac_ok) {
    return ssl_ticket_aead_ignore_ticket;
  }

  // Decrypt the session data.
  const uint8_t *ciphertext = ticket + SSL_TICKET_KEY_NAME_LEN + iv_len;
  size_t ciphertext_len = ticket_len - SSL_TICKET_KEY_NAME_LEN - iv_len -
                          mac_len;
  UniquePtr<uint8_t> plaintext((uint8_t *)OPENSSL_malloc(ciphertext_len));
  if (!plaintext) {
    return ssl_ticket_aead_error;
  }
  size_t plaintext_len;
#if defined(BORINGSSL_UNSAFE_FUZZER_MODE)
  OPENSSL_memcpy(plaintext.get(), ciphertext, ciphertext_len);
  plaintext_len = ciphertext_len;
#else
  if (ciphertext_len >= INT_MAX) {
    return ssl_ticket_aead_ignore_ticket;
  }
  int len1, len2;
  if (!EVP_DecryptUpdate(cipher_ctx, plaintext.get(), &len1, ciphertext,
                         (int)ciphertext_len) ||
      !EVP_DecryptFinal_ex(cipher_ctx, plaintext.get() + len1, &len2)) {
    ERR_clear_error();
    return ssl_ticket_aead_ignore_ticket;
  }
  plaintext_len = (size_t)(len1) + len2;
#endif

  *out = plaintext.release();
  *out_len = plaintext_len;
  return ssl_ticket_aead_success;
}

static enum ssl_ticket_aead_result_t ssl_decrypt_ticket_with_cb(
    SSL *ssl, uint8_t **out, size_t *out_len, bool *out_renew_ticket,
    const uint8_t *ticket, size_t ticket_len) {
  assert(ticket_len >= SSL_TICKET_KEY_NAME_LEN + EVP_MAX_IV_LENGTH);
  ScopedEVP_CIPHER_CTX cipher_ctx;
  ScopedHMAC_CTX hmac_ctx;
  const uint8_t *iv = ticket + SSL_TICKET_KEY_NAME_LEN;
  int cb_ret = ssl->session_ctx->tlsext_ticket_key_cb(
      ssl, (uint8_t *)ticket /* name */, (uint8_t *)iv, cipher_ctx.get(),
      hmac_ctx.get(), 0 /* decrypt */);
  if (cb_ret < 0) {
    return ssl_ticket_aead_error;
  } else if (cb_ret == 0) {
    return ssl_ticket_aead_ignore_ticket;
  } else if (cb_ret == 2) {
    *out_renew_ticket = true;
  } else {
    assert(cb_ret == 1);
  }
  return decrypt_ticket_with_cipher_ctx(out, out_len, cipher_ctx.get(),
                                        hmac_ctx.get(), ticket, ticket_len);
}

static enum ssl_ticket_aead_result_t ssl_decrypt_ticket_with_ticket_keys(
    SSL *ssl, uint8_t **out, size_t *out_len, const uint8_t *ticket,
    size_t ticket_len) {
  assert(ticket_len >= SSL_TICKET_KEY_NAME_LEN + EVP_MAX_IV_LENGTH);
  SSL_CTX *ctx = ssl->session_ctx;

  // Rotate the ticket key if necessary.
  if (!ssl_ctx_rotate_ticket_encryption_key(ctx)) {
    return ssl_ticket_aead_error;
  }

  // Pick the matching ticket key and decrypt.
  ScopedEVP_CIPHER_CTX cipher_ctx;
  ScopedHMAC_CTX hmac_ctx;
  {
    MutexReadLock lock(&ctx->lock);
    const tlsext_ticket_key *key;
    if (ctx->tlsext_ticket_key_current &&
        !OPENSSL_memcmp(ctx->tlsext_ticket_key_current->name, ticket,
                        SSL_TICKET_KEY_NAME_LEN)) {
      key = ctx->tlsext_ticket_key_current;
    } else if (ctx->tlsext_ticket_key_prev &&
               !OPENSSL_memcmp(ctx->tlsext_ticket_key_prev->name, ticket,
                               SSL_TICKET_KEY_NAME_LEN)) {
      key = ctx->tlsext_ticket_key_prev;
    } else {
      return ssl_ticket_aead_ignore_ticket;
    }
    const uint8_t *iv = ticket + SSL_TICKET_KEY_NAME_LEN;
    if (!HMAC_Init_ex(hmac_ctx.get(), key->hmac_key, sizeof(key->hmac_key),
                      tlsext_tick_md(), NULL) ||
        !EVP_DecryptInit_ex(cipher_ctx.get(), EVP_aes_128_cbc(), NULL,
                            key->aes_key, iv)) {
      return ssl_ticket_aead_error;
    }
  }
  return decrypt_ticket_with_cipher_ctx(out, out_len, cipher_ctx.get(),
                                        hmac_ctx.get(), ticket, ticket_len);
}

static enum ssl_ticket_aead_result_t ssl_decrypt_ticket_with_method(
    SSL *ssl, uint8_t **out, size_t *out_len, bool *out_renew_ticket,
    const uint8_t *ticket, size_t ticket_len) {
  uint8_t *plaintext = (uint8_t *)OPENSSL_malloc(ticket_len);
  if (plaintext == NULL) {
    OPENSSL_PUT_ERROR(SSL, ERR_R_MALLOC_FAILURE);
    return ssl_ticket_aead_error;
  }

  size_t plaintext_len;
  const enum ssl_ticket_aead_result_t result =
      ssl->session_ctx->ticket_aead_method->open(
          ssl, plaintext, &plaintext_len, ticket_len, ticket, ticket_len);

  if (result == ssl_ticket_aead_success) {
    *out = plaintext;
    plaintext = NULL;
    *out_len = plaintext_len;
  }

  OPENSSL_free(plaintext);
  return result;
}

enum ssl_ticket_aead_result_t ssl_process_ticket(
    SSL *ssl, UniquePtr<SSL_SESSION> *out_session, bool *out_renew_ticket,
    const uint8_t *ticket, size_t ticket_len, const uint8_t *session_id,
    size_t session_id_len) {
  *out_renew_ticket = false;
  out_session->reset();

  if ((SSL_get_options(ssl) & SSL_OP_NO_TICKET) ||
      session_id_len > SSL_MAX_SSL_SESSION_ID_LENGTH) {
    return ssl_ticket_aead_ignore_ticket;
  }

  uint8_t *plaintext = NULL;
  size_t plaintext_len;
  enum ssl_ticket_aead_result_t result;
  if (ssl->session_ctx->ticket_aead_method != NULL) {
    result = ssl_decrypt_ticket_with_method(
        ssl, &plaintext, &plaintext_len, out_renew_ticket, ticket, ticket_len);
  } else {
    // Ensure there is room for the key name and the largest IV
    // |tlsext_ticket_key_cb| may try to consume. The real limit may be lower,
    // but the maximum IV length should be well under the minimum size for the
    // session material and HMAC.
    if (ticket_len < SSL_TICKET_KEY_NAME_LEN + EVP_MAX_IV_LENGTH) {
      return ssl_ticket_aead_ignore_ticket;
    }
    if (ssl->session_ctx->tlsext_ticket_key_cb != NULL) {
      result = ssl_decrypt_ticket_with_cb(ssl, &plaintext, &plaintext_len,
                                          out_renew_ticket, ticket, ticket_len);
    } else {
      result = ssl_decrypt_ticket_with_ticket_keys(
          ssl, &plaintext, &plaintext_len, ticket, ticket_len);
    }
  }

  if (result != ssl_ticket_aead_success) {
    return result;
  }

  // Decode the session.
  UniquePtr<SSL_SESSION> session(
      SSL_SESSION_from_bytes(plaintext, plaintext_len, ssl->ctx));
  OPENSSL_free(plaintext);

  if (!session) {
    ERR_clear_error();  // Don't leave an error on the queue.
    return ssl_ticket_aead_ignore_ticket;
  }

  // Copy the client's session ID into the new session, to denote the ticket has
  // been accepted.
  OPENSSL_memcpy(session->session_id, session_id, session_id_len);
  session->session_id_length = session_id_len;

  *out_session = std::move(session);
  return ssl_ticket_aead_success;
}

bool tls1_parse_peer_sigalgs(SSL_HANDSHAKE *hs, const CBS *in_sigalgs) {
  // Extension ignored for inappropriate versions
  if (ssl_protocol_version(hs->ssl) < TLS1_2_VERSION) {
    return true;
  }

  return parse_u16_array(in_sigalgs, &hs->peer_sigalgs);
}

bool tls1_get_legacy_signature_algorithm(uint16_t *out, const EVP_PKEY *pkey) {
  switch (EVP_PKEY_id(pkey)) {
    case EVP_PKEY_RSA:
      *out = SSL_SIGN_RSA_PKCS1_MD5_SHA1;
      return true;
    case EVP_PKEY_EC:
      *out = SSL_SIGN_ECDSA_SHA1;
      return true;
    default:
      return false;
  }
}

bool tls1_choose_signature_algorithm(SSL_HANDSHAKE *hs, uint16_t *out) {
  SSL *const ssl = hs->ssl;
  CERT *cert = ssl->cert;

  // Before TLS 1.2, the signature algorithm isn't negotiated as part of the
  // handshake.
  if (ssl_protocol_version(ssl) < TLS1_2_VERSION) {
    if (!tls1_get_legacy_signature_algorithm(out, hs->local_pubkey.get())) {
      OPENSSL_PUT_ERROR(SSL, SSL_R_NO_COMMON_SIGNATURE_ALGORITHMS);
      return false;
    }
    return true;
  }

  Span<const uint16_t> sigalgs = kSignSignatureAlgorithms;
  if (cert->sigalgs != nullptr) {
    sigalgs = MakeConstSpan(cert->sigalgs, cert->num_sigalgs);
  }

  Span<const uint16_t> peer_sigalgs = hs->peer_sigalgs;
  if (peer_sigalgs.empty() && ssl_protocol_version(ssl) < TLS1_3_VERSION) {
    // If the client didn't specify any signature_algorithms extension then
    // we can assume that it supports SHA1. See
    // http://tools.ietf.org/html/rfc5246#section-7.4.1.4.1
    static const uint16_t kDefaultPeerAlgorithms[] = {SSL_SIGN_RSA_PKCS1_SHA1,
                                                      SSL_SIGN_ECDSA_SHA1};
    peer_sigalgs = kDefaultPeerAlgorithms;
  }

  for (uint16_t sigalg : sigalgs) {
    // SSL_SIGN_RSA_PKCS1_MD5_SHA1 is an internal value and should never be
    // negotiated.
    if (sigalg == SSL_SIGN_RSA_PKCS1_MD5_SHA1 ||
        !ssl_private_key_supports_signature_algorithm(hs, sigalg)) {
      continue;
    }

    for (uint16_t peer_sigalg : peer_sigalgs) {
      if (sigalg == peer_sigalg) {
        *out = sigalg;
        return true;
      }
    }
  }

  OPENSSL_PUT_ERROR(SSL, SSL_R_NO_COMMON_SIGNATURE_ALGORITHMS);
  return false;
}

int tls1_verify_channel_id(SSL_HANDSHAKE *hs, const SSLMessage &msg) {
  SSL *const ssl = hs->ssl;
  // A Channel ID handshake message is structured to contain multiple
  // extensions, but the only one that can be present is Channel ID.
  uint16_t extension_type;
  CBS channel_id = msg.body, extension;
  if (!CBS_get_u16(&channel_id, &extension_type) ||
      !CBS_get_u16_length_prefixed(&channel_id, &extension) ||
      CBS_len(&channel_id) != 0 ||
      extension_type != TLSEXT_TYPE_channel_id ||
      CBS_len(&extension) != TLSEXT_CHANNEL_ID_SIZE) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_DECODE_ERROR);
    ssl_send_alert(ssl, SSL3_AL_FATAL, SSL_AD_DECODE_ERROR);
    return 0;
  }

  UniquePtr<EC_GROUP> p256(EC_GROUP_new_by_curve_name(NID_X9_62_prime256v1));
  if (!p256) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_NO_P256_SUPPORT);
    return 0;
  }

  UniquePtr<ECDSA_SIG> sig(ECDSA_SIG_new());
  UniquePtr<BIGNUM> x(BN_new()), y(BN_new());
  if (!sig || !x || !y) {
    return 0;
  }

  const uint8_t *p = CBS_data(&extension);
  if (BN_bin2bn(p + 0, 32, x.get()) == NULL ||
      BN_bin2bn(p + 32, 32, y.get()) == NULL ||
      BN_bin2bn(p + 64, 32, sig->r) == NULL ||
      BN_bin2bn(p + 96, 32, sig->s) == NULL) {
    return 0;
  }

  UniquePtr<EC_KEY> key(EC_KEY_new());
  UniquePtr<EC_POINT> point(EC_POINT_new(p256.get()));
  if (!key || !point ||
      !EC_POINT_set_affine_coordinates_GFp(p256.get(), point.get(), x.get(),
                                           y.get(), nullptr) ||
      !EC_KEY_set_group(key.get(), p256.get()) ||
      !EC_KEY_set_public_key(key.get(), point.get())) {
    return 0;
  }

  uint8_t digest[EVP_MAX_MD_SIZE];
  size_t digest_len;
  if (!tls1_channel_id_hash(hs, digest, &digest_len)) {
    return 0;
  }

  int sig_ok = ECDSA_do_verify(digest, digest_len, sig.get(), key.get());
#if defined(BORINGSSL_UNSAFE_FUZZER_MODE)
  sig_ok = 1;
  ERR_clear_error();
#endif
  if (!sig_ok) {
    OPENSSL_PUT_ERROR(SSL, SSL_R_CHANNEL_ID_SIGNATURE_INVALID);
    ssl_send_alert(ssl, SSL3_AL_FATAL, SSL_AD_DECRYPT_ERROR);
    ssl->s3->tlsext_channel_id_valid = false;
    return 0;
  }

  OPENSSL_memcpy(ssl->s3->tlsext_channel_id, p, 64);
  return 1;
}

bool tls1_write_channel_id(SSL_HANDSHAKE *hs, CBB *cbb) {
  SSL *const ssl = hs->ssl;
  uint8_t digest[EVP_MAX_MD_SIZE];
  size_t digest_len;
  if (!tls1_channel_id_hash(hs, digest, &digest_len)) {
    return false;
  }

  EC_KEY *ec_key = EVP_PKEY_get0_EC_KEY(ssl->tlsext_channel_id_private);
  if (ec_key == nullptr) {
    OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
    return false;
  }

  UniquePtr<BIGNUM> x(BN_new()), y(BN_new());
  if (!x || !y ||
      !EC_POINT_get_affine_coordinates_GFp(EC_KEY_get0_group(ec_key),
                                           EC_KEY_get0_public_key(ec_key),
                                           x.get(), y.get(), nullptr)) {
    return false;
  }

  UniquePtr<ECDSA_SIG> sig(ECDSA_do_sign(digest, digest_len, ec_key));
  if (!sig) {
    return false;
  }

  CBB child;
  if (!CBB_add_u16(cbb, TLSEXT_TYPE_channel_id) ||
      !CBB_add_u16_length_prefixed(cbb, &child) ||
      !BN_bn2cbb_padded(&child, 32, x.get()) ||
      !BN_bn2cbb_padded(&child, 32, y.get()) ||
      !BN_bn2cbb_padded(&child, 32, sig->r) ||
      !BN_bn2cbb_padded(&child, 32, sig->s) ||
      !CBB_flush(cbb)) {
    return false;
  }

  return true;
}

int tls1_channel_id_hash(SSL_HANDSHAKE *hs, uint8_t *out, size_t *out_len) {
  SSL *const ssl = hs->ssl;
  if (ssl_protocol_version(ssl) >= TLS1_3_VERSION) {
    Array<uint8_t> msg;
    if (!tls13_get_cert_verify_signature_input(hs, &msg,
                                               ssl_cert_verify_channel_id)) {
      return 0;
    }
    SHA256(msg.data(), msg.size(), out);
    *out_len = SHA256_DIGEST_LENGTH;
    return 1;
  }

  SHA256_CTX ctx;

  SHA256_Init(&ctx);
  static const char kClientIDMagic[] = "TLS Channel ID signature";
  SHA256_Update(&ctx, kClientIDMagic, sizeof(kClientIDMagic));

  if (ssl->session != NULL) {
    static const char kResumptionMagic[] = "Resumption";
    SHA256_Update(&ctx, kResumptionMagic, sizeof(kResumptionMagic));
    if (ssl->session->original_handshake_hash_len == 0) {
      OPENSSL_PUT_ERROR(SSL, ERR_R_INTERNAL_ERROR);
      return 0;
    }
    SHA256_Update(&ctx, ssl->session->original_handshake_hash,
                  ssl->session->original_handshake_hash_len);
  }

  uint8_t hs_hash[EVP_MAX_MD_SIZE];
  size_t hs_hash_len;
  if (!hs->transcript.GetHash(hs_hash, &hs_hash_len)) {
    return 0;
  }
  SHA256_Update(&ctx, hs_hash, (size_t)hs_hash_len);
  SHA256_Final(out, &ctx);
  *out_len = SHA256_DIGEST_LENGTH;
  return 1;
}

// tls1_record_handshake_hashes_for_channel_id records the current handshake
// hashes in |hs->new_session| so that Channel ID resumptions can sign that
// data.
int tls1_record_handshake_hashes_for_channel_id(SSL_HANDSHAKE *hs) {
  SSL *const ssl = hs->ssl;
  // This function should never be called for a resumed session because the
  // handshake hashes that we wish to record are for the original, full
  // handshake.
  if (ssl->session != NULL) {
    return 0;
  }

  static_assert(
      sizeof(hs->new_session->original_handshake_hash) == EVP_MAX_MD_SIZE,
      "original_handshake_hash is too small");

  size_t digest_len;
  if (!hs->transcript.GetHash(hs->new_session->original_handshake_hash,
                              &digest_len)) {
    return 0;
  }

  static_assert(EVP_MAX_MD_SIZE <= 0xff,
                "EVP_MAX_MD_SIZE does not fit in uint8_t");
  hs->new_session->original_handshake_hash_len = (uint8_t)digest_len;

  return 1;
}

int ssl_do_channel_id_callback(SSL *ssl) {
  if (ssl->tlsext_channel_id_private != NULL ||
      ssl->ctx->channel_id_cb == NULL) {
    return 1;
  }

  EVP_PKEY *key = NULL;
  ssl->ctx->channel_id_cb(ssl, &key);
  if (key == NULL) {
    // The caller should try again later.
    return 1;
  }

  int ret = SSL_set1_tls_channel_id(ssl, key);
  EVP_PKEY_free(key);
  return ret;
}

int ssl_is_sct_list_valid(const CBS *contents) {
  // Shallow parse the SCT list for sanity. By the RFC
  // (https://tools.ietf.org/html/rfc6962#section-3.3) neither the list nor any
  // of the SCTs may be empty.
  CBS copy = *contents;
  CBS sct_list;
  if (!CBS_get_u16_length_prefixed(&copy, &sct_list) ||
      CBS_len(&copy) != 0 ||
      CBS_len(&sct_list) == 0) {
    return 0;
  }

  while (CBS_len(&sct_list) > 0) {
    CBS sct;
    if (!CBS_get_u16_length_prefixed(&sct_list, &sct) ||
        CBS_len(&sct) == 0) {
      return 0;
    }
  }

  return 1;
}

}  // namespace bssl

using namespace bssl;

int SSL_early_callback_ctx_extension_get(const SSL_CLIENT_HELLO *client_hello,
                                         uint16_t extension_type,
                                         const uint8_t **out_data,
                                         size_t *out_len) {
  CBS cbs;
  if (!ssl_client_hello_get_extension(client_hello, &cbs, extension_type)) {
    return 0;
  }

  *out_data = CBS_data(&cbs);
  *out_len = CBS_len(&cbs);
  return 1;
}

void SSL_CTX_set_ed25519_enabled(SSL_CTX *ctx, int enabled) {
  ctx->ed25519_enabled = !!enabled;
}

int SSL_extension_supported(unsigned extension_value) {
  uint32_t index;
  return extension_value == TLSEXT_TYPE_padding ||
         tls_extension_find(&index, extension_value) != NULL;
}
