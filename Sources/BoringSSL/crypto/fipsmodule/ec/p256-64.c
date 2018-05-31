/* Copyright (c) 2015, Google Inc.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
 * OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE. */

// A 64-bit implementation of the NIST P-256 elliptic curve point
// multiplication
//
// OpenSSL integration was taken from Emilia Kasper's work in ecp_nistp224.c.
// Otherwise based on Emilia's P224 work, which was inspired by my curve25519
// work which got its smarts from Daniel J. Bernstein's work on the same.

#include <openssl/base.h>

#if defined(OPENSSL_64_BIT) && !defined(OPENSSL_WINDOWS)

#include <openssl/bn.h>
#include <openssl/ec.h>
#include <openssl/err.h>
#include <openssl/mem.h>

#include <string.h>

#include "../delocate.h"
#include "../../internal.h"
#include "internal.h"


// The underlying field. P256 operates over GF(2^256-2^224+2^192+2^96-1). We
// can serialise an element of this field into 32 bytes. We call this an
// felem_bytearray.
typedef uint8_t felem_bytearray[32];

// The representation of field elements.
// ------------------------------------
//
// We represent field elements with either four 128-bit values, eight 128-bit
// values, or four 64-bit values. The field element represented is:
//   v[0]*2^0 + v[1]*2^64 + v[2]*2^128 + v[3]*2^192  (mod p)
// or:
//   v[0]*2^0 + v[1]*2^64 + v[2]*2^128 + ... + v[8]*2^512  (mod p)
//
// 128-bit values are called 'limbs'. Since the limbs are spaced only 64 bits
// apart, but are 128-bits wide, the most significant bits of each limb overlap
// with the least significant bits of the next.
//
// A field element with four limbs is an 'felem'. One with eight limbs is a
// 'longfelem'
//
// A field element with four, 64-bit values is called a 'smallfelem'. Small
// values are used as intermediate values before multiplication.

#define NLIMBS 4

typedef uint128_t limb;
typedef limb felem[NLIMBS];
typedef limb longfelem[NLIMBS * 2];
typedef uint64_t smallfelem[NLIMBS];

// This is the value of the prime as four 64-bit words, little-endian.
static const uint64_t kPrime[4] = {0xfffffffffffffffful, 0xffffffff, 0,
                              0xffffffff00000001ul};
static const uint64_t bottom63bits = 0x7ffffffffffffffful;

static uint64_t load_u64(const uint8_t in[8]) {
  uint64_t ret;
  OPENSSL_memcpy(&ret, in, sizeof(ret));
  return ret;
}

static void store_u64(uint8_t out[8], uint64_t in) {
  OPENSSL_memcpy(out, &in, sizeof(in));
}

// bin32_to_felem takes a little-endian byte array and converts it into felem
// form. This assumes that the CPU is little-endian.
static void bin32_to_felem(felem out, const uint8_t in[32]) {
  out[0] = load_u64(&in[0]);
  out[1] = load_u64(&in[8]);
  out[2] = load_u64(&in[16]);
  out[3] = load_u64(&in[24]);
}

// smallfelem_to_bin32 takes a smallfelem and serialises into a little endian,
// 32 byte array. This assumes that the CPU is little-endian.
static void smallfelem_to_bin32(uint8_t out[32], const smallfelem in) {
  store_u64(&out[0], in[0]);
  store_u64(&out[8], in[1]);
  store_u64(&out[16], in[2]);
  store_u64(&out[24], in[3]);
}

// To preserve endianness when using BN_bn2bin and BN_bin2bn.
static void flip_endian(uint8_t *out, const uint8_t *in, size_t len) {
  for (size_t i = 0; i < len; ++i) {
    out[i] = in[len - 1 - i];
  }
}

// BN_to_felem converts an OpenSSL BIGNUM into an felem.
static int BN_to_felem(felem out, const BIGNUM *bn) {
  if (BN_is_negative(bn)) {
    OPENSSL_PUT_ERROR(EC, EC_R_BIGNUM_OUT_OF_RANGE);
    return 0;
  }

  felem_bytearray b_out;
  // BN_bn2bin eats leading zeroes
  OPENSSL_memset(b_out, 0, sizeof(b_out));
  size_t num_bytes = BN_num_bytes(bn);
  if (num_bytes > sizeof(b_out)) {
    OPENSSL_PUT_ERROR(EC, EC_R_BIGNUM_OUT_OF_RANGE);
    return 0;
  }

  felem_bytearray b_in;
  num_bytes = BN_bn2bin(bn, b_in);
  flip_endian(b_out, b_in, num_bytes);
  bin32_to_felem(out, b_out);
  return 1;
}

// felem_to_BN converts an felem into an OpenSSL BIGNUM.
static BIGNUM *smallfelem_to_BN(BIGNUM *out, const smallfelem in) {
  felem_bytearray b_in, b_out;
  smallfelem_to_bin32(b_in, in);
  flip_endian(b_out, b_in, sizeof(b_out));
  return BN_bin2bn(b_out, sizeof(b_out), out);
}

// Field operations.

static void felem_assign(felem out, const felem in) {
  out[0] = in[0];
  out[1] = in[1];
  out[2] = in[2];
  out[3] = in[3];
}

// felem_sum sets out = out + in.
static void felem_sum(felem out, const felem in) {
  out[0] += in[0];
  out[1] += in[1];
  out[2] += in[2];
  out[3] += in[3];
}

// felem_small_sum sets out = out + in.
static void felem_small_sum(felem out, const smallfelem in) {
  out[0] += in[0];
  out[1] += in[1];
  out[2] += in[2];
  out[3] += in[3];
}

// felem_scalar sets out = out * scalar
static void felem_scalar(felem out, const uint64_t scalar) {
  out[0] *= scalar;
  out[1] *= scalar;
  out[2] *= scalar;
  out[3] *= scalar;
}

// longfelem_scalar sets out = out * scalar
static void longfelem_scalar(longfelem out, const uint64_t scalar) {
  out[0] *= scalar;
  out[1] *= scalar;
  out[2] *= scalar;
  out[3] *= scalar;
  out[4] *= scalar;
  out[5] *= scalar;
  out[6] *= scalar;
  out[7] *= scalar;
}

#define two105m41m9 ((((limb)1) << 105) - (((limb)1) << 41) - (((limb)1) << 9))
#define two105 (((limb)1) << 105)
#define two105m41p9 ((((limb)1) << 105) - (((limb)1) << 41) + (((limb)1) << 9))

// zero105 is 0 mod p
static const felem zero105 = {two105m41m9, two105, two105m41p9, two105m41p9};

// smallfelem_neg sets |out| to |-small|
// On exit:
//   out[i] < out[i] + 2^105
static void smallfelem_neg(felem out, const smallfelem small) {
  // In order to prevent underflow, we subtract from 0 mod p.
  out[0] = zero105[0] - small[0];
  out[1] = zero105[1] - small[1];
  out[2] = zero105[2] - small[2];
  out[3] = zero105[3] - small[3];
}

// felem_diff subtracts |in| from |out|
// On entry:
//   in[i] < 2^104
// On exit:
//   out[i] < out[i] + 2^105.
static void felem_diff(felem out, const felem in) {
  // In order to prevent underflow, we add 0 mod p before subtracting.
  out[0] += zero105[0];
  out[1] += zero105[1];
  out[2] += zero105[2];
  out[3] += zero105[3];

  out[0] -= in[0];
  out[1] -= in[1];
  out[2] -= in[2];
  out[3] -= in[3];
}

#define two107m43m11 \
  ((((limb)1) << 107) - (((limb)1) << 43) - (((limb)1) << 11))
#define two107 (((limb)1) << 107)
#define two107m43p11 \
  ((((limb)1) << 107) - (((limb)1) << 43) + (((limb)1) << 11))

// zero107 is 0 mod p
static const felem zero107 = {two107m43m11, two107, two107m43p11, two107m43p11};

// An alternative felem_diff for larger inputs |in|
// felem_diff_zero107 subtracts |in| from |out|
// On entry:
//   in[i] < 2^106
// On exit:
//   out[i] < out[i] + 2^107.
static void felem_diff_zero107(felem out, const felem in) {
  // In order to prevent underflow, we add 0 mod p before subtracting.
  out[0] += zero107[0];
  out[1] += zero107[1];
  out[2] += zero107[2];
  out[3] += zero107[3];

  out[0] -= in[0];
  out[1] -= in[1];
  out[2] -= in[2];
  out[3] -= in[3];
}

// longfelem_diff subtracts |in| from |out|
// On entry:
//   in[i] < 7*2^67
// On exit:
//   out[i] < out[i] + 2^70 + 2^40.
static void longfelem_diff(longfelem out, const longfelem in) {
  static const limb two70m8p6 =
      (((limb)1) << 70) - (((limb)1) << 8) + (((limb)1) << 6);
  static const limb two70p40 = (((limb)1) << 70) + (((limb)1) << 40);
  static const limb two70 = (((limb)1) << 70);
  static const limb two70m40m38p6 = (((limb)1) << 70) - (((limb)1) << 40) -
                                    (((limb)1) << 38) + (((limb)1) << 6);
  static const limb two70m6 = (((limb)1) << 70) - (((limb)1) << 6);

  // add 0 mod p to avoid underflow
  out[0] += two70m8p6;
  out[1] += two70p40;
  out[2] += two70;
  out[3] += two70m40m38p6;
  out[4] += two70m6;
  out[5] += two70m6;
  out[6] += two70m6;
  out[7] += two70m6;

  // in[i] < 7*2^67 < 2^70 - 2^40 - 2^38 + 2^6
  out[0] -= in[0];
  out[1] -= in[1];
  out[2] -= in[2];
  out[3] -= in[3];
  out[4] -= in[4];
  out[5] -= in[5];
  out[6] -= in[6];
  out[7] -= in[7];
}

#define two64m0 ((((limb)1) << 64) - 1)
#define two110p32m0 ((((limb)1) << 110) + (((limb)1) << 32) - 1)
#define two64m46 ((((limb)1) << 64) - (((limb)1) << 46))
#define two64m32 ((((limb)1) << 64) - (((limb)1) << 32))

// zero110 is 0 mod p.
static const felem zero110 = {two64m0, two110p32m0, two64m46, two64m32};

// felem_shrink converts an felem into a smallfelem. The result isn't quite
// minimal as the value may be greater than p.
//
// On entry:
//   in[i] < 2^109
// On exit:
//   out[i] < 2^64.
static void felem_shrink(smallfelem out, const felem in) {
  felem tmp;
  uint64_t a, b, mask;
  int64_t high, low;
  static const uint64_t kPrime3Test =
      0x7fffffff00000001ul;  // 2^63 - 2^32 + 1

  // Carry 2->3
  tmp[3] = zero110[3] + in[3] + ((uint64_t)(in[2] >> 64));
  // tmp[3] < 2^110

  tmp[2] = zero110[2] + (uint64_t)in[2];
  tmp[0] = zero110[0] + in[0];
  tmp[1] = zero110[1] + in[1];
  // tmp[0] < 2**110, tmp[1] < 2^111, tmp[2] < 2**65

  // We perform two partial reductions where we eliminate the high-word of
  // tmp[3]. We don't update the other words till the end.
  a = tmp[3] >> 64;  // a < 2^46
  tmp[3] = (uint64_t)tmp[3];
  tmp[3] -= a;
  tmp[3] += ((limb)a) << 32;
  // tmp[3] < 2^79

  b = a;
  a = tmp[3] >> 64;  // a < 2^15
  b += a;            // b < 2^46 + 2^15 < 2^47
  tmp[3] = (uint64_t)tmp[3];
  tmp[3] -= a;
  tmp[3] += ((limb)a) << 32;
  // tmp[3] < 2^64 + 2^47

  // This adjusts the other two words to complete the two partial
  // reductions.
  tmp[0] += b;
  tmp[1] -= (((limb)b) << 32);

  // In order to make space in tmp[3] for the carry from 2 -> 3, we
  // conditionally subtract kPrime if tmp[3] is large enough.
  high = tmp[3] >> 64;
  // As tmp[3] < 2^65, high is either 1 or 0
  high = ~(high - 1);
  // high is:
  //   all ones   if the high word of tmp[3] is 1
  //   all zeros  if the high word of tmp[3] if 0
  low = tmp[3];
  mask = low >> 63;
  // mask is:
  //   all ones   if the MSB of low is 1
  //   all zeros  if the MSB of low if 0
  low &= bottom63bits;
  low -= kPrime3Test;
  // if low was greater than kPrime3Test then the MSB is zero
  low = ~low;
  low >>= 63;
  // low is:
  //   all ones   if low was > kPrime3Test
  //   all zeros  if low was <= kPrime3Test
  mask = (mask & low) | high;
  tmp[0] -= mask & kPrime[0];
  tmp[1] -= mask & kPrime[1];
  // kPrime[2] is zero, so omitted
  tmp[3] -= mask & kPrime[3];
  // tmp[3] < 2**64 - 2**32 + 1

  tmp[1] += ((uint64_t)(tmp[0] >> 64));
  tmp[0] = (uint64_t)tmp[0];
  tmp[2] += ((uint64_t)(tmp[1] >> 64));
  tmp[1] = (uint64_t)tmp[1];
  tmp[3] += ((uint64_t)(tmp[2] >> 64));
  tmp[2] = (uint64_t)tmp[2];
  // tmp[i] < 2^64

  out[0] = tmp[0];
  out[1] = tmp[1];
  out[2] = tmp[2];
  out[3] = tmp[3];
}

// smallfelem_expand converts a smallfelem to an felem
static void smallfelem_expand(felem out, const smallfelem in) {
  out[0] = in[0];
  out[1] = in[1];
  out[2] = in[2];
  out[3] = in[3];
}

// smallfelem_square sets |out| = |small|^2
// On entry:
//   small[i] < 2^64
// On exit:
//   out[i] < 7 * 2^64 < 2^67
static void smallfelem_square(longfelem out, const smallfelem small) {
  limb a;
  uint64_t high, low;

  a = ((uint128_t)small[0]) * small[0];
  low = a;
  high = a >> 64;
  out[0] = low;
  out[1] = high;

  a = ((uint128_t)small[0]) * small[1];
  low = a;
  high = a >> 64;
  out[1] += low;
  out[1] += low;
  out[2] = high;

  a = ((uint128_t)small[0]) * small[2];
  low = a;
  high = a >> 64;
  out[2] += low;
  out[2] *= 2;
  out[3] = high;

  a = ((uint128_t)small[0]) * small[3];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[4] = high;

  a = ((uint128_t)small[1]) * small[2];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[3] *= 2;
  out[4] += high;

  a = ((uint128_t)small[1]) * small[1];
  low = a;
  high = a >> 64;
  out[2] += low;
  out[3] += high;

  a = ((uint128_t)small[1]) * small[3];
  low = a;
  high = a >> 64;
  out[4] += low;
  out[4] *= 2;
  out[5] = high;

  a = ((uint128_t)small[2]) * small[3];
  low = a;
  high = a >> 64;
  out[5] += low;
  out[5] *= 2;
  out[6] = high;
  out[6] += high;

  a = ((uint128_t)small[2]) * small[2];
  low = a;
  high = a >> 64;
  out[4] += low;
  out[5] += high;

  a = ((uint128_t)small[3]) * small[3];
  low = a;
  high = a >> 64;
  out[6] += low;
  out[7] = high;
}

//felem_square sets |out| = |in|^2
// On entry:
//   in[i] < 2^109
// On exit:
//   out[i] < 7 * 2^64 < 2^67.
static void felem_square(longfelem out, const felem in) {
  uint64_t small[4];
  felem_shrink(small, in);
  smallfelem_square(out, small);
}

// smallfelem_mul sets |out| = |small1| * |small2|
// On entry:
//   small1[i] < 2^64
//   small2[i] < 2^64
// On exit:
//   out[i] < 7 * 2^64 < 2^67.
static void smallfelem_mul(longfelem out, const smallfelem small1,
                           const smallfelem small2) {
  limb a;
  uint64_t high, low;

  a = ((uint128_t)small1[0]) * small2[0];
  low = a;
  high = a >> 64;
  out[0] = low;
  out[1] = high;

  a = ((uint128_t)small1[0]) * small2[1];
  low = a;
  high = a >> 64;
  out[1] += low;
  out[2] = high;

  a = ((uint128_t)small1[1]) * small2[0];
  low = a;
  high = a >> 64;
  out[1] += low;
  out[2] += high;

  a = ((uint128_t)small1[0]) * small2[2];
  low = a;
  high = a >> 64;
  out[2] += low;
  out[3] = high;

  a = ((uint128_t)small1[1]) * small2[1];
  low = a;
  high = a >> 64;
  out[2] += low;
  out[3] += high;

  a = ((uint128_t)small1[2]) * small2[0];
  low = a;
  high = a >> 64;
  out[2] += low;
  out[3] += high;

  a = ((uint128_t)small1[0]) * small2[3];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[4] = high;

  a = ((uint128_t)small1[1]) * small2[2];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[4] += high;

  a = ((uint128_t)small1[2]) * small2[1];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[4] += high;

  a = ((uint128_t)small1[3]) * small2[0];
  low = a;
  high = a >> 64;
  out[3] += low;
  out[4] += high;

  a = ((uint128_t)small1[1]) * small2[3];
  low = a;
  high = a >> 64;
  out[4] += low;
  out[5] = high;

  a = ((uint128_t)small1[2]) * small2[2];
  low = a;
  high = a >> 64;
  out[4] += low;
  out[5] += high;

  a = ((uint128_t)small1[3]) * small2[1];
  low = a;
  high = a >> 64;
  out[4] += low;
  out[5] += high;

  a = ((uint128_t)small1[2]) * small2[3];
  low = a;
  high = a >> 64;
  out[5] += low;
  out[6] = high;

  a = ((uint128_t)small1[3]) * small2[2];
  low = a;
  high = a >> 64;
  out[5] += low;
  out[6] += high;

  a = ((uint128_t)small1[3]) * small2[3];
  low = a;
  high = a >> 64;
  out[6] += low;
  out[7] = high;
}

// felem_mul sets |out| = |in1| * |in2|
// On entry:
//   in1[i] < 2^109
//   in2[i] < 2^109
// On exit:
//   out[i] < 7 * 2^64 < 2^67
static void felem_mul(longfelem out, const felem in1, const felem in2) {
  smallfelem small1, small2;
  felem_shrink(small1, in1);
  felem_shrink(small2, in2);
  smallfelem_mul(out, small1, small2);
}

// felem_small_mul sets |out| = |small1| * |in2|
// On entry:
//   small1[i] < 2^64
//   in2[i] < 2^109
// On exit:
//   out[i] < 7 * 2^64 < 2^67
static void felem_small_mul(longfelem out, const smallfelem small1,
                            const felem in2) {
  smallfelem small2;
  felem_shrink(small2, in2);
  smallfelem_mul(out, small1, small2);
}

#define two100m36m4 ((((limb)1) << 100) - (((limb)1) << 36) - (((limb)1) << 4))
#define two100 (((limb)1) << 100)
#define two100m36p4 ((((limb)1) << 100) - (((limb)1) << 36) + (((limb)1) << 4))

// zero100 is 0 mod p
static const felem zero100 = {two100m36m4, two100, two100m36p4, two100m36p4};

// Internal function for the different flavours of felem_reduce.
// felem_reduce_ reduces the higher coefficients in[4]-in[7].
// On entry:
//   out[0] >= in[6] + 2^32*in[6] + in[7] + 2^32*in[7]
//   out[1] >= in[7] + 2^32*in[4]
//   out[2] >= in[5] + 2^32*in[5]
//   out[3] >= in[4] + 2^32*in[5] + 2^32*in[6]
// On exit:
//   out[0] <= out[0] + in[4] + 2^32*in[5]
//   out[1] <= out[1] + in[5] + 2^33*in[6]
//   out[2] <= out[2] + in[7] + 2*in[6] + 2^33*in[7]
//   out[3] <= out[3] + 2^32*in[4] + 3*in[7]
static void felem_reduce_(felem out, const longfelem in) {
  int128_t c;
  // combine common terms from below
  c = in[4] + (in[5] << 32);
  out[0] += c;
  out[3] -= c;

  c = in[5] - in[7];
  out[1] += c;
  out[2] -= c;

  // the remaining terms
  // 256: [(0,1),(96,-1),(192,-1),(224,1)]
  out[1] -= (in[4] << 32);
  out[3] += (in[4] << 32);

  // 320: [(32,1),(64,1),(128,-1),(160,-1),(224,-1)]
  out[2] -= (in[5] << 32);

  // 384: [(0,-1),(32,-1),(96,2),(128,2),(224,-1)]
  out[0] -= in[6];
  out[0] -= (in[6] << 32);
  out[1] += (in[6] << 33);
  out[2] += (in[6] * 2);
  out[3] -= (in[6] << 32);

  // 448: [(0,-1),(32,-1),(64,-1),(128,1),(160,2),(192,3)]
  out[0] -= in[7];
  out[0] -= (in[7] << 32);
  out[2] += (in[7] << 33);
  out[3] += (in[7] * 3);
}

// felem_reduce converts a longfelem into an felem.
// To be called directly after felem_square or felem_mul.
// On entry:
//   in[0] < 2^64, in[1] < 3*2^64, in[2] < 5*2^64, in[3] < 7*2^64
//   in[4] < 7*2^64, in[5] < 5*2^64, in[6] < 3*2^64, in[7] < 2*64
// On exit:
//   out[i] < 2^101
static void felem_reduce(felem out, const longfelem in) {
  out[0] = zero100[0] + in[0];
  out[1] = zero100[1] + in[1];
  out[2] = zero100[2] + in[2];
  out[3] = zero100[3] + in[3];

  felem_reduce_(out, in);

  // out[0] > 2^100 - 2^36 - 2^4 - 3*2^64 - 3*2^96 - 2^64 - 2^96 > 0
  // out[1] > 2^100 - 2^64 - 7*2^96 > 0
  // out[2] > 2^100 - 2^36 + 2^4 - 5*2^64 - 5*2^96 > 0
  // out[3] > 2^100 - 2^36 + 2^4 - 7*2^64 - 5*2^96 - 3*2^96 > 0
  //
  // out[0] < 2^100 + 2^64 + 7*2^64 + 5*2^96 < 2^101
  // out[1] < 2^100 + 3*2^64 + 5*2^64 + 3*2^97 < 2^101
  // out[2] < 2^100 + 5*2^64 + 2^64 + 3*2^65 + 2^97 < 2^101
  // out[3] < 2^100 + 7*2^64 + 7*2^96 + 3*2^64 < 2^101
}

// felem_reduce_zero105 converts a larger longfelem into an felem.
// On entry:
//   in[0] < 2^71
// On exit:
//   out[i] < 2^106
static void felem_reduce_zero105(felem out, const longfelem in) {
    out[0] = zero105[0] + in[0];
    out[1] = zero105[1] + in[1];
    out[2] = zero105[2] + in[2];
    out[3] = zero105[3] + in[3];

    felem_reduce_(out, in);

    // out[0] > 2^105 - 2^41 - 2^9 - 2^71 - 2^103 - 2^71 - 2^103 > 0
    // out[1] > 2^105 - 2^71 - 2^103 > 0
    // out[2] > 2^105 - 2^41 + 2^9 - 2^71 - 2^103 > 0
    // out[3] > 2^105 - 2^41 + 2^9 - 2^71 - 2^103 - 2^103 > 0
    //
    // out[0] < 2^105 + 2^71 + 2^71 + 2^103 < 2^106
    // out[1] < 2^105 + 2^71 + 2^71 + 2^103 < 2^106
    // out[2] < 2^105 + 2^71 + 2^71 + 2^71 + 2^103 < 2^106
    // out[3] < 2^105 + 2^71 + 2^103 + 2^71 < 2^106
}

// subtract_u64 sets *result = *result - v and *carry to one if the
// subtraction underflowed.
static void subtract_u64(uint64_t *result, uint64_t *carry, uint64_t v) {
  uint128_t r = *result;
  r -= v;
  *carry = (r >> 64) & 1;
  *result = (uint64_t)r;
}

// felem_contract converts |in| to its unique, minimal representation. On
// entry: in[i] < 2^109.
static void felem_contract(smallfelem out, const felem in) {
  uint64_t all_equal_so_far = 0, result = 0;

  felem_shrink(out, in);
  // small is minimal except that the value might be > p

  all_equal_so_far--;
  // We are doing a constant time test if out >= kPrime. We need to compare
  // each uint64_t, from most-significant to least significant. For each one, if
  // all words so far have been equal (m is all ones) then a non-equal
  // result is the answer. Otherwise we continue.
  for (size_t i = 3; i < 4; i--) {
    uint64_t equal;
    uint128_t a = ((uint128_t)kPrime[i]) - out[i];
    // if out[i] > kPrime[i] then a will underflow and the high 64-bits
    // will all be set.
    result |= all_equal_so_far & ((uint64_t)(a >> 64));

    // if kPrime[i] == out[i] then |equal| will be all zeros and the
    // decrement will make it all ones.
    equal = kPrime[i] ^ out[i];
    equal--;
    equal &= equal << 32;
    equal &= equal << 16;
    equal &= equal << 8;
    equal &= equal << 4;
    equal &= equal << 2;
    equal &= equal << 1;
    equal = ((int64_t)equal) >> 63;

    all_equal_so_far &= equal;
  }

  // if all_equal_so_far is still all ones then the two values are equal
  // and so out >= kPrime is true.
  result |= all_equal_so_far;

  // if out >= kPrime then we subtract kPrime.
  uint64_t carry;
  subtract_u64(&out[0], &carry, result & kPrime[0]);
  subtract_u64(&out[1], &carry, carry);
  subtract_u64(&out[2], &carry, carry);
  subtract_u64(&out[3], &carry, carry);

  subtract_u64(&out[1], &carry, result & kPrime[1]);
  subtract_u64(&out[2], &carry, carry);
  subtract_u64(&out[3], &carry, carry);

  subtract_u64(&out[2], &carry, result & kPrime[2]);
  subtract_u64(&out[3], &carry, carry);

  subtract_u64(&out[3], &carry, result & kPrime[3]);
}

// felem_is_zero returns a limb with all bits set if |in| == 0 (mod p) and 0
// otherwise.
// On entry:
//   small[i] < 2^64
static limb smallfelem_is_zero(const smallfelem small) {
  limb result;
  uint64_t is_p;

  uint64_t is_zero = small[0] | small[1] | small[2] | small[3];
  is_zero--;
  is_zero &= is_zero << 32;
  is_zero &= is_zero << 16;
  is_zero &= is_zero << 8;
  is_zero &= is_zero << 4;
  is_zero &= is_zero << 2;
  is_zero &= is_zero << 1;
  is_zero = ((int64_t)is_zero) >> 63;

  is_p = (small[0] ^ kPrime[0]) | (small[1] ^ kPrime[1]) |
         (small[2] ^ kPrime[2]) | (small[3] ^ kPrime[3]);
  is_p--;
  is_p &= is_p << 32;
  is_p &= is_p << 16;
  is_p &= is_p << 8;
  is_p &= is_p << 4;
  is_p &= is_p << 2;
  is_p &= is_p << 1;
  is_p = ((int64_t)is_p) >> 63;

  is_zero |= is_p;

  result = is_zero;
  result |= ((limb)is_zero) << 64;
  return result;
}

// felem_inv calculates |out| = |in|^{-1}
//
// Based on Fermat's Little Theorem:
//   a^p = a (mod p)
//   a^{p-1} = 1 (mod p)
//   a^{p-2} = a^{-1} (mod p)
static void felem_inv(felem out, const felem in) {
  felem ftmp, ftmp2;
  // each e_I will hold |in|^{2^I - 1}
  felem e2, e4, e8, e16, e32, e64;
  longfelem tmp;

  felem_square(tmp, in);
  felem_reduce(ftmp, tmp);  // 2^1
  felem_mul(tmp, in, ftmp);
  felem_reduce(ftmp, tmp);  // 2^2 - 2^0
  felem_assign(e2, ftmp);
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^3 - 2^1
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^4 - 2^2
  felem_mul(tmp, ftmp, e2);
  felem_reduce(ftmp, tmp);  // 2^4 - 2^0
  felem_assign(e4, ftmp);
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^5 - 2^1
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^6 - 2^2
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^7 - 2^3
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);  // 2^8 - 2^4
  felem_mul(tmp, ftmp, e4);
  felem_reduce(ftmp, tmp);  // 2^8 - 2^0
  felem_assign(e8, ftmp);
  for (size_t i = 0; i < 8; i++) {
    felem_square(tmp, ftmp);
    felem_reduce(ftmp, tmp);
  }  // 2^16 - 2^8
  felem_mul(tmp, ftmp, e8);
  felem_reduce(ftmp, tmp);  // 2^16 - 2^0
  felem_assign(e16, ftmp);
  for (size_t i = 0; i < 16; i++) {
    felem_square(tmp, ftmp);
    felem_reduce(ftmp, tmp);
  }  // 2^32 - 2^16
  felem_mul(tmp, ftmp, e16);
  felem_reduce(ftmp, tmp);  // 2^32 - 2^0
  felem_assign(e32, ftmp);
  for (size_t i = 0; i < 32; i++) {
    felem_square(tmp, ftmp);
    felem_reduce(ftmp, tmp);
  }  // 2^64 - 2^32
  felem_assign(e64, ftmp);
  felem_mul(tmp, ftmp, in);
  felem_reduce(ftmp, tmp);  // 2^64 - 2^32 + 2^0
  for (size_t i = 0; i < 192; i++) {
    felem_square(tmp, ftmp);
    felem_reduce(ftmp, tmp);
  }  // 2^256 - 2^224 + 2^192

  felem_mul(tmp, e64, e32);
  felem_reduce(ftmp2, tmp);  // 2^64 - 2^0
  for (size_t i = 0; i < 16; i++) {
    felem_square(tmp, ftmp2);
    felem_reduce(ftmp2, tmp);
  }  // 2^80 - 2^16
  felem_mul(tmp, ftmp2, e16);
  felem_reduce(ftmp2, tmp);  // 2^80 - 2^0
  for (size_t i = 0; i < 8; i++) {
    felem_square(tmp, ftmp2);
    felem_reduce(ftmp2, tmp);
  }  // 2^88 - 2^8
  felem_mul(tmp, ftmp2, e8);
  felem_reduce(ftmp2, tmp);  // 2^88 - 2^0
  for (size_t i = 0; i < 4; i++) {
    felem_square(tmp, ftmp2);
    felem_reduce(ftmp2, tmp);
  }  // 2^92 - 2^4
  felem_mul(tmp, ftmp2, e4);
  felem_reduce(ftmp2, tmp);  // 2^92 - 2^0
  felem_square(tmp, ftmp2);
  felem_reduce(ftmp2, tmp);  // 2^93 - 2^1
  felem_square(tmp, ftmp2);
  felem_reduce(ftmp2, tmp);  // 2^94 - 2^2
  felem_mul(tmp, ftmp2, e2);
  felem_reduce(ftmp2, tmp);  // 2^94 - 2^0
  felem_square(tmp, ftmp2);
  felem_reduce(ftmp2, tmp);  // 2^95 - 2^1
  felem_square(tmp, ftmp2);
  felem_reduce(ftmp2, tmp);  // 2^96 - 2^2
  felem_mul(tmp, ftmp2, in);
  felem_reduce(ftmp2, tmp);  // 2^96 - 3

  felem_mul(tmp, ftmp2, ftmp);
  felem_reduce(out, tmp);  // 2^256 - 2^224 + 2^192 + 2^96 - 3
}

// Group operations
// ----------------
//
// Building on top of the field operations we have the operations on the
// elliptic curve group itself. Points on the curve are represented in Jacobian
// coordinates.

// point_double calculates 2*(x_in, y_in, z_in)
//
// The method is taken from:
//   http://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-3.html#doubling-dbl-2001-b
//
// Outputs can equal corresponding inputs, i.e., x_out == x_in is allowed.
// while x_out == y_in is not (maybe this works, but it's not tested).
static void point_double(felem x_out, felem y_out, felem z_out,
                         const felem x_in, const felem y_in, const felem z_in) {
  longfelem tmp, tmp2;
  felem delta, gamma, beta, alpha, ftmp, ftmp2;
  smallfelem small1, small2;

  felem_assign(ftmp, x_in);
  // ftmp[i] < 2^106
  felem_assign(ftmp2, x_in);
  // ftmp2[i] < 2^106

  // delta = z^2
  felem_square(tmp, z_in);
  felem_reduce(delta, tmp);
  // delta[i] < 2^101

  // gamma = y^2
  felem_square(tmp, y_in);
  felem_reduce(gamma, tmp);
  // gamma[i] < 2^101
  felem_shrink(small1, gamma);

  // beta = x*gamma
  felem_small_mul(tmp, small1, x_in);
  felem_reduce(beta, tmp);
  // beta[i] < 2^101

  // alpha = 3*(x-delta)*(x+delta)
  felem_diff(ftmp, delta);
  // ftmp[i] < 2^105 + 2^106 < 2^107
  felem_sum(ftmp2, delta);
  // ftmp2[i] < 2^105 + 2^106 < 2^107
  felem_scalar(ftmp2, 3);
  // ftmp2[i] < 3 * 2^107 < 2^109
  felem_mul(tmp, ftmp, ftmp2);
  felem_reduce(alpha, tmp);
  // alpha[i] < 2^101
  felem_shrink(small2, alpha);

  // x' = alpha^2 - 8*beta
  smallfelem_square(tmp, small2);
  felem_reduce(x_out, tmp);
  felem_assign(ftmp, beta);
  felem_scalar(ftmp, 8);
  // ftmp[i] < 8 * 2^101 = 2^104
  felem_diff(x_out, ftmp);
  // x_out[i] < 2^105 + 2^101 < 2^106

  // z' = (y + z)^2 - gamma - delta
  felem_sum(delta, gamma);
  // delta[i] < 2^101 + 2^101 = 2^102
  felem_assign(ftmp, y_in);
  felem_sum(ftmp, z_in);
  // ftmp[i] < 2^106 + 2^106 = 2^107
  felem_square(tmp, ftmp);
  felem_reduce(z_out, tmp);
  felem_diff(z_out, delta);
  // z_out[i] < 2^105 + 2^101 < 2^106

  // y' = alpha*(4*beta - x') - 8*gamma^2
  felem_scalar(beta, 4);
  // beta[i] < 4 * 2^101 = 2^103
  felem_diff_zero107(beta, x_out);
  // beta[i] < 2^107 + 2^103 < 2^108
  felem_small_mul(tmp, small2, beta);
  // tmp[i] < 7 * 2^64 < 2^67
  smallfelem_square(tmp2, small1);
  // tmp2[i] < 7 * 2^64
  longfelem_scalar(tmp2, 8);
  // tmp2[i] < 8 * 7 * 2^64 = 7 * 2^67
  longfelem_diff(tmp, tmp2);
  // tmp[i] < 2^67 + 2^70 + 2^40 < 2^71
  felem_reduce_zero105(y_out, tmp);
  // y_out[i] < 2^106
}

// point_double_small is the same as point_double, except that it operates on
// smallfelems.
static void point_double_small(smallfelem x_out, smallfelem y_out,
                               smallfelem z_out, const smallfelem x_in,
                               const smallfelem y_in, const smallfelem z_in) {
  felem felem_x_out, felem_y_out, felem_z_out;
  felem felem_x_in, felem_y_in, felem_z_in;

  smallfelem_expand(felem_x_in, x_in);
  smallfelem_expand(felem_y_in, y_in);
  smallfelem_expand(felem_z_in, z_in);
  point_double(felem_x_out, felem_y_out, felem_z_out, felem_x_in, felem_y_in,
               felem_z_in);
  felem_shrink(x_out, felem_x_out);
  felem_shrink(y_out, felem_y_out);
  felem_shrink(z_out, felem_z_out);
}

// p256_copy_conditional copies in to out iff mask is all ones.
static void p256_copy_conditional(felem out, const felem in, limb mask) {
  for (size_t i = 0; i < NLIMBS; ++i) {
    const limb tmp = mask & (in[i] ^ out[i]);
    out[i] ^= tmp;
  }
}

// copy_small_conditional copies in to out iff mask is all ones.
static void copy_small_conditional(felem out, const smallfelem in, limb mask) {
  const uint64_t mask64 = mask;
  for (size_t i = 0; i < NLIMBS; ++i) {
    out[i] = ((limb)(in[i] & mask64)) | (out[i] & ~mask);
  }
}

// point_add calcuates (x1, y1, z1) + (x2, y2, z2)
//
// The method is taken from:
//   http://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-3.html#addition-add-2007-bl,
// adapted for mixed addition (z2 = 1, or z2 = 0 for the point at infinity).
//
// This function includes a branch for checking whether the two input points
// are equal, (while not equal to the point at infinity). This case never
// happens during single point multiplication, so there is no timing leak for
// ECDH or ECDSA signing.
static void point_add(felem x3, felem y3, felem z3, const felem x1,
                      const felem y1, const felem z1, const int mixed,
                      const smallfelem x2, const smallfelem y2,
                      const smallfelem z2) {
  felem ftmp, ftmp2, ftmp3, ftmp4, ftmp5, ftmp6, x_out, y_out, z_out;
  longfelem tmp, tmp2;
  smallfelem small1, small2, small3, small4, small5;
  limb x_equal, y_equal, z1_is_zero, z2_is_zero;

  felem_shrink(small3, z1);

  z1_is_zero = smallfelem_is_zero(small3);
  z2_is_zero = smallfelem_is_zero(z2);

  // ftmp = z1z1 = z1**2
  smallfelem_square(tmp, small3);
  felem_reduce(ftmp, tmp);
  // ftmp[i] < 2^101
  felem_shrink(small1, ftmp);

  if (!mixed) {
    // ftmp2 = z2z2 = z2**2
    smallfelem_square(tmp, z2);
    felem_reduce(ftmp2, tmp);
    // ftmp2[i] < 2^101
    felem_shrink(small2, ftmp2);

    felem_shrink(small5, x1);

    // u1 = ftmp3 = x1*z2z2
    smallfelem_mul(tmp, small5, small2);
    felem_reduce(ftmp3, tmp);
    // ftmp3[i] < 2^101

    // ftmp5 = z1 + z2
    felem_assign(ftmp5, z1);
    felem_small_sum(ftmp5, z2);
    // ftmp5[i] < 2^107

    // ftmp5 = (z1 + z2)**2 - (z1z1 + z2z2) = 2z1z2
    felem_square(tmp, ftmp5);
    felem_reduce(ftmp5, tmp);
    // ftmp2 = z2z2 + z1z1
    felem_sum(ftmp2, ftmp);
    // ftmp2[i] < 2^101 + 2^101 = 2^102
    felem_diff(ftmp5, ftmp2);
    // ftmp5[i] < 2^105 + 2^101 < 2^106

    // ftmp2 = z2 * z2z2
    smallfelem_mul(tmp, small2, z2);
    felem_reduce(ftmp2, tmp);

    // s1 = ftmp2 = y1 * z2**3
    felem_mul(tmp, y1, ftmp2);
    felem_reduce(ftmp6, tmp);
    // ftmp6[i] < 2^101
  } else {
    // We'll assume z2 = 1 (special case z2 = 0 is handled later).

    // u1 = ftmp3 = x1*z2z2
    felem_assign(ftmp3, x1);
    // ftmp3[i] < 2^106

    // ftmp5 = 2z1z2
    felem_assign(ftmp5, z1);
    felem_scalar(ftmp5, 2);
    // ftmp5[i] < 2*2^106 = 2^107

    // s1 = ftmp2 = y1 * z2**3
    felem_assign(ftmp6, y1);
    // ftmp6[i] < 2^106
  }

  // u2 = x2*z1z1
  smallfelem_mul(tmp, x2, small1);
  felem_reduce(ftmp4, tmp);

  // h = ftmp4 = u2 - u1
  felem_diff_zero107(ftmp4, ftmp3);
  // ftmp4[i] < 2^107 + 2^101 < 2^108
  felem_shrink(small4, ftmp4);

  x_equal = smallfelem_is_zero(small4);

  // z_out = ftmp5 * h
  felem_small_mul(tmp, small4, ftmp5);
  felem_reduce(z_out, tmp);
  // z_out[i] < 2^101

  // ftmp = z1 * z1z1
  smallfelem_mul(tmp, small1, small3);
  felem_reduce(ftmp, tmp);

  // s2 = tmp = y2 * z1**3
  felem_small_mul(tmp, y2, ftmp);
  felem_reduce(ftmp5, tmp);

  // r = ftmp5 = (s2 - s1)*2
  felem_diff_zero107(ftmp5, ftmp6);
  // ftmp5[i] < 2^107 + 2^107 = 2^108
  felem_scalar(ftmp5, 2);
  // ftmp5[i] < 2^109
  felem_shrink(small1, ftmp5);
  y_equal = smallfelem_is_zero(small1);

  if (x_equal && y_equal && !z1_is_zero && !z2_is_zero) {
    point_double(x3, y3, z3, x1, y1, z1);
    return;
  }

  // I = ftmp = (2h)**2
  felem_assign(ftmp, ftmp4);
  felem_scalar(ftmp, 2);
  // ftmp[i] < 2*2^108 = 2^109
  felem_square(tmp, ftmp);
  felem_reduce(ftmp, tmp);

  // J = ftmp2 = h * I
  felem_mul(tmp, ftmp4, ftmp);
  felem_reduce(ftmp2, tmp);

  // V = ftmp4 = U1 * I
  felem_mul(tmp, ftmp3, ftmp);
  felem_reduce(ftmp4, tmp);

  // x_out = r**2 - J - 2V
  smallfelem_square(tmp, small1);
  felem_reduce(x_out, tmp);
  felem_assign(ftmp3, ftmp4);
  felem_scalar(ftmp4, 2);
  felem_sum(ftmp4, ftmp2);
  // ftmp4[i] < 2*2^101 + 2^101 < 2^103
  felem_diff(x_out, ftmp4);
  // x_out[i] < 2^105 + 2^101

  // y_out = r(V-x_out) - 2 * s1 * J
  felem_diff_zero107(ftmp3, x_out);
  // ftmp3[i] < 2^107 + 2^101 < 2^108
  felem_small_mul(tmp, small1, ftmp3);
  felem_mul(tmp2, ftmp6, ftmp2);
  longfelem_scalar(tmp2, 2);
  // tmp2[i] < 2*2^67 = 2^68
  longfelem_diff(tmp, tmp2);
  // tmp[i] < 2^67 + 2^70 + 2^40 < 2^71
  felem_reduce_zero105(y_out, tmp);
  // y_out[i] < 2^106

  copy_small_conditional(x_out, x2, z1_is_zero);
  p256_copy_conditional(x_out, x1, z2_is_zero);
  copy_small_conditional(y_out, y2, z1_is_zero);
  p256_copy_conditional(y_out, y1, z2_is_zero);
  copy_small_conditional(z_out, z2, z1_is_zero);
  p256_copy_conditional(z_out, z1, z2_is_zero);
  felem_assign(x3, x_out);
  felem_assign(y3, y_out);
  felem_assign(z3, z_out);
}

// point_add_small is the same as point_add, except that it operates on
// smallfelems.
static void point_add_small(smallfelem x3, smallfelem y3, smallfelem z3,
                            smallfelem x1, smallfelem y1, smallfelem z1,
                            smallfelem x2, smallfelem y2, smallfelem z2) {
  felem felem_x3, felem_y3, felem_z3;
  felem felem_x1, felem_y1, felem_z1;
  smallfelem_expand(felem_x1, x1);
  smallfelem_expand(felem_y1, y1);
  smallfelem_expand(felem_z1, z1);
  point_add(felem_x3, felem_y3, felem_z3, felem_x1, felem_y1, felem_z1, 0, x2,
            y2, z2);
  felem_shrink(x3, felem_x3);
  felem_shrink(y3, felem_y3);
  felem_shrink(z3, felem_z3);
}

// Base point pre computation
// --------------------------
//
// Two different sorts of precomputed tables are used in the following code.
// Each contain various points on the curve, where each point is three field
// elements (x, y, z).
//
// For the base point table, z is usually 1 (0 for the point at infinity).
// This table has 2 * 16 elements, starting with the following:
// index | bits    | point
// ------+---------+------------------------------
//     0 | 0 0 0 0 | 0G
//     1 | 0 0 0 1 | 1G
//     2 | 0 0 1 0 | 2^64G
//     3 | 0 0 1 1 | (2^64 + 1)G
//     4 | 0 1 0 0 | 2^128G
//     5 | 0 1 0 1 | (2^128 + 1)G
//     6 | 0 1 1 0 | (2^128 + 2^64)G
//     7 | 0 1 1 1 | (2^128 + 2^64 + 1)G
//     8 | 1 0 0 0 | 2^192G
//     9 | 1 0 0 1 | (2^192 + 1)G
//    10 | 1 0 1 0 | (2^192 + 2^64)G
//    11 | 1 0 1 1 | (2^192 + 2^64 + 1)G
//    12 | 1 1 0 0 | (2^192 + 2^128)G
//    13 | 1 1 0 1 | (2^192 + 2^128 + 1)G
//    14 | 1 1 1 0 | (2^192 + 2^128 + 2^64)G
//    15 | 1 1 1 1 | (2^192 + 2^128 + 2^64 + 1)G
// followed by a copy of this with each element multiplied by 2^32.
//
// The reason for this is so that we can clock bits into four different
// locations when doing simple scalar multiplies against the base point,
// and then another four locations using the second 16 elements.
//
// Tables for other points have table[i] = iG for i in 0 .. 16.

// g_pre_comp is the table of precomputed base points
static const smallfelem g_pre_comp[2][16][3] = {
    {{{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}},
     {{0xf4a13945d898c296, 0x77037d812deb33a0, 0xf8bce6e563a440f2,
       0x6b17d1f2e12c4247},
      {0xcbb6406837bf51f5, 0x2bce33576b315ece, 0x8ee7eb4a7c0f9e16,
       0x4fe342e2fe1a7f9b},
      {1, 0, 0, 0}},
     {{0x90e75cb48e14db63, 0x29493baaad651f7e, 0x8492592e326e25de,
       0x0fa822bc2811aaa5},
      {0xe41124545f462ee7, 0x34b1a65050fe82f5, 0x6f4ad4bcb3df188b,
       0xbff44ae8f5dba80d},
      {1, 0, 0, 0}},
     {{0x93391ce2097992af, 0xe96c98fd0d35f1fa, 0xb257c0de95e02789,
       0x300a4bbc89d6726f},
      {0xaa54a291c08127a0, 0x5bb1eeada9d806a5, 0x7f1ddb25ff1e3c6f,
       0x72aac7e0d09b4644},
      {1, 0, 0, 0}},
     {{0x57c84fc9d789bd85, 0xfc35ff7dc297eac3, 0xfb982fd588c6766e,
       0x447d739beedb5e67},
      {0x0c7e33c972e25b32, 0x3d349b95a7fae500, 0xe12e9d953a4aaff7,
       0x2d4825ab834131ee},
      {1, 0, 0, 0}},
     {{0x13949c932a1d367f, 0xef7fbd2b1a0a11b7, 0xddc6068bb91dfc60,
       0xef9519328a9c72ff},
      {0x196035a77376d8a8, 0x23183b0895ca1740, 0xc1ee9807022c219c,
       0x611e9fc37dbb2c9b},
      {1, 0, 0, 0}},
     {{0xcae2b1920b57f4bc, 0x2936df5ec6c9bc36, 0x7dea6482e11238bf,
       0x550663797b51f5d8},
      {0x44ffe216348a964c, 0x9fb3d576dbdefbe1, 0x0afa40018d9d50e5,
       0x157164848aecb851},
      {1, 0, 0, 0}},
     {{0xe48ecafffc5cde01, 0x7ccd84e70d715f26, 0xa2e8f483f43e4391,
       0xeb5d7745b21141ea},
      {0xcac917e2731a3479, 0x85f22cfe2844b645, 0x0990e6a158006cee,
       0xeafd72ebdbecc17b},
      {1, 0, 0, 0}},
     {{0x6cf20ffb313728be, 0x96439591a3c6b94a, 0x2736ff8344315fc5,
       0xa6d39677a7849276},
      {0xf2bab833c357f5f4, 0x824a920c2284059b, 0x66b8babd2d27ecdf,
       0x674f84749b0b8816},
      {1, 0, 0, 0}},
     {{0x2df48c04677c8a3e, 0x74e02f080203a56b, 0x31855f7db8c7fedb,
       0x4e769e7672c9ddad},
      {0xa4c36165b824bbb0, 0xfb9ae16f3b9122a5, 0x1ec0057206947281,
       0x42b99082de830663},
      {1, 0, 0, 0}},
     {{0x6ef95150dda868b9, 0xd1f89e799c0ce131, 0x7fdc1ca008a1c478,
       0x78878ef61c6ce04d},
      {0x9c62b9121fe0d976, 0x6ace570ebde08d4f, 0xde53142c12309def,
       0xb6cb3f5d7b72c321},
      {1, 0, 0, 0}},
     {{0x7f991ed2c31a3573, 0x5b82dd5bd54fb496, 0x595c5220812ffcae,
       0x0c88bc4d716b1287},
      {0x3a57bf635f48aca8, 0x7c8181f4df2564f3, 0x18d1b5b39c04e6aa,
       0xdd5ddea3f3901dc6},
      {1, 0, 0, 0}},
     {{0xe96a79fb3e72ad0c, 0x43a0a28c42ba792f, 0xefe0a423083e49f3,
       0x68f344af6b317466},
      {0xcdfe17db3fb24d4a, 0x668bfc2271f5c626, 0x604ed93c24d67ff3,
       0x31b9c405f8540a20},
      {1, 0, 0, 0}},
     {{0xd36b4789a2582e7f, 0x0d1a10144ec39c28, 0x663c62c3edbad7a0,
       0x4052bf4b6f461db9},
      {0x235a27c3188d25eb, 0xe724f33999bfcc5b, 0x862be6bd71d70cc8,
       0xfecf4d5190b0fc61},
      {1, 0, 0, 0}},
     {{0x74346c10a1d4cfac, 0xafdf5cc08526a7a4, 0x123202a8f62bff7a,
       0x1eddbae2c802e41a},
      {0x8fa0af2dd603f844, 0x36e06b7e4c701917, 0x0c45f45273db33a0,
       0x43104d86560ebcfc},
      {1, 0, 0, 0}},
     {{0x9615b5110d1d78e5, 0x66b0de3225c4744b, 0x0a4a46fb6aaf363a,
       0xb48e26b484f7a21c},
      {0x06ebb0f621a01b2d, 0xc004e4048b7b0f98, 0x64131bcdfed6f668,
       0xfac015404d4d3dab},
      {1, 0, 0, 0}}},
    {{{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}},
     {{0x3a5a9e22185a5943, 0x1ab919365c65dfb6, 0x21656b32262c71da,
       0x7fe36b40af22af89},
      {0xd50d152c699ca101, 0x74b3d5867b8af212, 0x9f09f40407dca6f1,
       0xe697d45825b63624},
      {1, 0, 0, 0}},
     {{0xa84aa9397512218e, 0xe9a521b074ca0141, 0x57880b3a18a2e902,
       0x4a5b506612a677a6},
      {0x0beada7a4c4f3840, 0x626db15419e26d9d, 0xc42604fbe1627d40,
       0xeb13461ceac089f1},
      {1, 0, 0, 0}},
     {{0xf9faed0927a43281, 0x5e52c4144103ecbc, 0xc342967aa815c857,
       0x0781b8291c6a220a},
      {0x5a8343ceeac55f80, 0x88f80eeee54a05e3, 0x97b2a14f12916434,
       0x690cde8df0151593},
      {1, 0, 0, 0}},
     {{0xaee9c75df7f82f2a, 0x9e4c35874afdf43a, 0xf5622df437371326,
       0x8a535f566ec73617},
      {0xc5f9a0ac223094b7, 0xcde533864c8c7669, 0x37e02819085a92bf,
       0x0455c08468b08bd7},
      {1, 0, 0, 0}},
     {{0x0c0a6e2c9477b5d9, 0xf9a4bf62876dc444, 0x5050a949b6cdc279,
       0x06bada7ab77f8276},
      {0xc8b4aed1ea48dac9, 0xdebd8a4b7ea1070f, 0x427d49101366eb70,
       0x5b476dfd0e6cb18a},
      {1, 0, 0, 0}},
     {{0x7c5c3e44278c340a, 0x4d54606812d66f3b, 0x29a751b1ae23c5d8,
       0x3e29864e8a2ec908},
      {0x142d2a6626dbb850, 0xad1744c4765bd780, 0x1f150e68e322d1ed,
       0x239b90ea3dc31e7e},
      {1, 0, 0, 0}},
     {{0x78c416527a53322a, 0x305dde6709776f8e, 0xdbcab759f8862ed4,
       0x820f4dd949f72ff7},
      {0x6cc544a62b5debd4, 0x75be5d937b4e8cc4, 0x1b481b1b215c14d3,
       0x140406ec783a05ec},
      {1, 0, 0, 0}},
     {{0x6a703f10e895df07, 0xfd75f3fa01876bd8, 0xeb5b06e70ce08ffe,
       0x68f6b8542783dfee},
      {0x90c76f8a78712655, 0xcf5293d2f310bf7f, 0xfbc8044dfda45028,
       0xcbe1feba92e40ce6},
      {1, 0, 0, 0}},
     {{0xe998ceea4396e4c1, 0xfc82ef0b6acea274, 0x230f729f2250e927,
       0xd0b2f94d2f420109},
      {0x4305adddb38d4966, 0x10b838f8624c3b45, 0x7db2636658954e7a,
       0x971459828b0719e5},
      {1, 0, 0, 0}},
     {{0x4bd6b72623369fc9, 0x57f2929e53d0b876, 0xc2d5cba4f2340687,
       0x961610004a866aba},
      {0x49997bcd2e407a5e, 0x69ab197d92ddcb24, 0x2cf1f2438fe5131c,
       0x7acb9fadcee75e44},
      {1, 0, 0, 0}},
     {{0x254e839423d2d4c0, 0xf57f0c917aea685b, 0xa60d880f6f75aaea,
       0x24eb9acca333bf5b},
      {0xe3de4ccb1cda5dea, 0xfeef9341c51a6b4f, 0x743125f88bac4c4d,
       0x69f891c5acd079cc},
      {1, 0, 0, 0}},
     {{0xeee44b35702476b5, 0x7ed031a0e45c2258, 0xb422d1e7bd6f8514,
       0xe51f547c5972a107},
      {0xa25bcd6fc9cf343d, 0x8ca922ee097c184e, 0xa62f98b3a9fe9a06,
       0x1c309a2b25bb1387},
      {1, 0, 0, 0}},
     {{0x9295dbeb1967c459, 0xb00148833472c98e, 0xc504977708011828,
       0x20b87b8aa2c4e503},
      {0x3063175de057c277, 0x1bd539338fe582dd, 0x0d11adef5f69a044,
       0xf5c6fa49919776be},
      {1, 0, 0, 0}},
     {{0x8c944e760fd59e11, 0x3876cba1102fad5f, 0xa454c3fad83faa56,
       0x1ed7d1b9332010b9},
      {0xa1011a270024b889, 0x05e4d0dcac0cd344, 0x52b520f0eb6a2a24,
       0x3a2b03f03217257a},
      {1, 0, 0, 0}},
     {{0xf20fc2afdf1d043d, 0xf330240db58d5a62, 0xfc7d229ca0058c3b,
       0x15fee545c78dd9f6},
      {0x501e82885bc98cda, 0x41ef80e5d046ac04, 0x557d9f49461210fb,
       0x4ab5b6b2b8753f81},
      {1, 0, 0, 0}}}};

// select_point selects the |idx|th point from a precomputation table and
// copies it to out.
static void select_point(const uint64_t idx, size_t size,
                         const smallfelem pre_comp[/*size*/][3],
                         smallfelem out[3]) {
  uint64_t *outlimbs = &out[0][0];
  OPENSSL_memset(outlimbs, 0, 3 * sizeof(smallfelem));

  for (size_t i = 0; i < size; i++) {
    const uint64_t *inlimbs = (const uint64_t *)&pre_comp[i][0][0];
    uint64_t mask = i ^ idx;
    mask |= mask >> 4;
    mask |= mask >> 2;
    mask |= mask >> 1;
    mask &= 1;
    mask--;
    for (size_t j = 0; j < NLIMBS * 3; j++) {
      outlimbs[j] |= inlimbs[j] & mask;
    }
  }
}

// get_bit returns the |i|th bit in |in|
static char get_bit(const felem_bytearray in, int i) {
  if (i < 0 || i >= 256) {
    return 0;
  }
  return (in[i >> 3] >> (i & 7)) & 1;
}

// Interleaved point multiplication using precomputed point multiples: The
// small point multiples 0*P, 1*P, ..., 17*P are in p_pre_comp, the scalar
// in p_scalar, if non-NULL. If g_scalar is non-NULL, we also add this multiple
// of the generator, using certain (large) precomputed multiples in g_pre_comp.
// Output point (X, Y, Z) is stored in x_out, y_out, z_out.
static void batch_mul(felem x_out, felem y_out, felem z_out,
                      const uint8_t *p_scalar, const uint8_t *g_scalar,
                      const smallfelem p_pre_comp[17][3]) {
  felem nq[3], ftmp;
  smallfelem tmp[3];
  uint64_t bits;
  uint8_t sign, digit;

  // set nq to the point at infinity
  OPENSSL_memset(nq, 0, 3 * sizeof(felem));

  // Loop over both scalars msb-to-lsb, interleaving additions of multiples
  // of the generator (two in each of the last 32 rounds) and additions of p
  // (every 5th round).

  int skip = 1;  // save two point operations in the first round
  size_t i = p_scalar != NULL ? 255 : 31;
  for (;;) {
    // double
    if (!skip) {
      point_double(nq[0], nq[1], nq[2], nq[0], nq[1], nq[2]);
    }

    // add multiples of the generator
    if (g_scalar != NULL && i <= 31) {
      // first, look 32 bits upwards
      bits = get_bit(g_scalar, i + 224) << 3;
      bits |= get_bit(g_scalar, i + 160) << 2;
      bits |= get_bit(g_scalar, i + 96) << 1;
      bits |= get_bit(g_scalar, i + 32);
      // select the point to add, in constant time
      select_point(bits, 16, g_pre_comp[1], tmp);

      if (!skip) {
        point_add(nq[0], nq[1], nq[2], nq[0], nq[1], nq[2], 1 /* mixed */,
                  tmp[0], tmp[1], tmp[2]);
      } else {
        smallfelem_expand(nq[0], tmp[0]);
        smallfelem_expand(nq[1], tmp[1]);
        smallfelem_expand(nq[2], tmp[2]);
        skip = 0;
      }

      // second, look at the current position
      bits = get_bit(g_scalar, i + 192) << 3;
      bits |= get_bit(g_scalar, i + 128) << 2;
      bits |= get_bit(g_scalar, i + 64) << 1;
      bits |= get_bit(g_scalar, i);
      // select the point to add, in constant time
      select_point(bits, 16, g_pre_comp[0], tmp);
      point_add(nq[0], nq[1], nq[2], nq[0], nq[1], nq[2], 1 /* mixed */, tmp[0],
                tmp[1], tmp[2]);
    }

    // do other additions every 5 doublings
    if (p_scalar != NULL && i % 5 == 0) {
      bits = get_bit(p_scalar, i + 4) << 5;
      bits |= get_bit(p_scalar, i + 3) << 4;
      bits |= get_bit(p_scalar, i + 2) << 3;
      bits |= get_bit(p_scalar, i + 1) << 2;
      bits |= get_bit(p_scalar, i) << 1;
      bits |= get_bit(p_scalar, i - 1);
      ec_GFp_nistp_recode_scalar_bits(&sign, &digit, bits);

      // select the point to add or subtract, in constant time.
      select_point(digit, 17, p_pre_comp, tmp);
      smallfelem_neg(ftmp, tmp[1]);  // (X, -Y, Z) is the negative
                                     // point
      copy_small_conditional(ftmp, tmp[1], (((limb)sign) - 1));
      felem_contract(tmp[1], ftmp);

      if (!skip) {
        point_add(nq[0], nq[1], nq[2], nq[0], nq[1], nq[2], 0 /* mixed */,
                  tmp[0], tmp[1], tmp[2]);
      } else {
        smallfelem_expand(nq[0], tmp[0]);
        smallfelem_expand(nq[1], tmp[1]);
        smallfelem_expand(nq[2], tmp[2]);
        skip = 0;
      }
    }

    if (i == 0) {
      break;
    }
    --i;
  }
  felem_assign(x_out, nq[0]);
  felem_assign(y_out, nq[1]);
  felem_assign(z_out, nq[2]);
}

// OPENSSL EC_METHOD FUNCTIONS

// Takes the Jacobian coordinates (X, Y, Z) of a point and returns (X', Y') =
// (X/Z^2, Y/Z^3).
static int ec_GFp_nistp256_point_get_affine_coordinates(const EC_GROUP *group,
                                                        const EC_POINT *point,
                                                        BIGNUM *x, BIGNUM *y,
                                                        BN_CTX *ctx) {
  felem z1, z2, x_in, y_in;
  smallfelem x_out, y_out;
  longfelem tmp;

  if (EC_POINT_is_at_infinity(group, point)) {
    OPENSSL_PUT_ERROR(EC, EC_R_POINT_AT_INFINITY);
    return 0;
  }
  if (!BN_to_felem(x_in, &point->X) ||
      !BN_to_felem(y_in, &point->Y) ||
      !BN_to_felem(z1, &point->Z)) {
    return 0;
  }
  felem_inv(z2, z1);
  felem_square(tmp, z2);
  felem_reduce(z1, tmp);

  if (x != NULL) {
    felem_mul(tmp, x_in, z1);
    felem_reduce(x_in, tmp);
    felem_contract(x_out, x_in);
    if (!smallfelem_to_BN(x, x_out)) {
      OPENSSL_PUT_ERROR(EC, ERR_R_BN_LIB);
      return 0;
    }
  }

  if (y != NULL) {
    felem_mul(tmp, z1, z2);
    felem_reduce(z1, tmp);
    felem_mul(tmp, y_in, z1);
    felem_reduce(y_in, tmp);
    felem_contract(y_out, y_in);
    if (!smallfelem_to_BN(y, y_out)) {
      OPENSSL_PUT_ERROR(EC, ERR_R_BN_LIB);
      return 0;
    }
  }

  return 1;
}

static int ec_GFp_nistp256_points_mul(const EC_GROUP *group, EC_POINT *r,
                                      const EC_SCALAR *g_scalar,
                                      const EC_POINT *p,
                                      const EC_SCALAR *p_scalar, BN_CTX *ctx) {
  int ret = 0;
  BN_CTX *new_ctx = NULL;
  BIGNUM *x, *y, *z, *tmp_scalar;
  smallfelem p_pre_comp[17][3];
  smallfelem x_in, y_in, z_in;
  felem x_out, y_out, z_out;

  if (ctx == NULL) {
    ctx = new_ctx = BN_CTX_new();
    if (ctx == NULL) {
      return 0;
    }
  }

  BN_CTX_start(ctx);
  if ((x = BN_CTX_get(ctx)) == NULL ||
      (y = BN_CTX_get(ctx)) == NULL ||
      (z = BN_CTX_get(ctx)) == NULL ||
      (tmp_scalar = BN_CTX_get(ctx)) == NULL) {
    goto err;
  }

  if (p != NULL && p_scalar != NULL) {
    // We treat NULL scalars as 0, and NULL points as points at infinity, i.e.,
    // they contribute nothing to the linear combination.
    OPENSSL_memset(&p_pre_comp, 0, sizeof(p_pre_comp));
    // Precompute multiples.
    if (!BN_to_felem(x_out, &p->X) ||
        !BN_to_felem(y_out, &p->Y) ||
        !BN_to_felem(z_out, &p->Z)) {
      goto err;
    }
    felem_shrink(p_pre_comp[1][0], x_out);
    felem_shrink(p_pre_comp[1][1], y_out);
    felem_shrink(p_pre_comp[1][2], z_out);
    for (size_t j = 2; j <= 16; ++j) {
      if (j & 1) {
        point_add_small(p_pre_comp[j][0], p_pre_comp[j][1],
                        p_pre_comp[j][2], p_pre_comp[1][0],
                        p_pre_comp[1][1], p_pre_comp[1][2],
                        p_pre_comp[j - 1][0], p_pre_comp[j - 1][1],
                        p_pre_comp[j - 1][2]);
      } else {
        point_double_small(p_pre_comp[j][0], p_pre_comp[j][1],
                           p_pre_comp[j][2], p_pre_comp[j / 2][0],
                           p_pre_comp[j / 2][1], p_pre_comp[j / 2][2]);
      }
    }
  }

  batch_mul(x_out, y_out, z_out,
            (p != NULL && p_scalar != NULL) ? p_scalar->bytes : NULL,
            g_scalar != NULL ? g_scalar->bytes : NULL,
            (const smallfelem(*)[3]) & p_pre_comp);

  // reduce the output to its unique minimal representation
  felem_contract(x_in, x_out);
  felem_contract(y_in, y_out);
  felem_contract(z_in, z_out);
  if (!smallfelem_to_BN(x, x_in) ||
      !smallfelem_to_BN(y, y_in) ||
      !smallfelem_to_BN(z, z_in)) {
    OPENSSL_PUT_ERROR(EC, ERR_R_BN_LIB);
    goto err;
  }
  ret = ec_point_set_Jprojective_coordinates_GFp(group, r, x, y, z, ctx);

err:
  BN_CTX_end(ctx);
  BN_CTX_free(new_ctx);
  return ret;
}

DEFINE_METHOD_FUNCTION(EC_METHOD, EC_GFp_nistp256_method) {
  out->group_init = ec_GFp_simple_group_init;
  out->group_finish = ec_GFp_simple_group_finish;
  out->group_set_curve = ec_GFp_simple_group_set_curve;
  out->point_get_affine_coordinates =
      ec_GFp_nistp256_point_get_affine_coordinates;
  out->mul = ec_GFp_nistp256_points_mul;
  out->field_mul = ec_GFp_simple_field_mul;
  out->field_sqr = ec_GFp_simple_field_sqr;
  out->field_encode = NULL;
  out->field_decode = NULL;
};

#endif  // 64_BIT && !WINDOWS
