/* SHA-256 over HACL*'s verified C, free of the Lean runtime so a sanitizer harness can drive it
 * (docs/contracts/U3-codecs.md S3, S5). The Lean glue is c/fvapi_sha256.c. */
#ifndef FVAPI_SHA256_CORE_H
#define FVAPI_SHA256_CORE_H

#include <stddef.h>
#include <stdint.h>

/* Every HACL length is a uint32_t: below the one-shot limit an input takes HACL's own
 * composition (Hacl_Hash_SHA2_hash_256), above it block-aligned chunks below 2^32 bytes. Test
 * builds lower both limits to drive the chunk loop with small inputs. */
#ifndef FVAPI_SHA256_ONESHOT_MAX
#define FVAPI_SHA256_ONESHOT_MAX ((size_t)UINT32_MAX)
#endif
#ifndef FVAPI_SHA256_CHUNK
#define FVAPI_SHA256_CHUNK ((size_t)UINT32_MAX - 63) /* largest multiple of 64 below 2^32 */
#endif

/* HACL's update_last takes the total in bytes; its bit count must fit 64 bits. */
#define FVAPI_SHA256_TOTAL_MAX ((uint64_t)1 << 61)

void fvapi_sha256_init_raw(uint32_t st[8]);

/* Hashes `len` bytes of whole blocks (`len` a multiple of 64) into the chaining state. */
void fvapi_sha256_absorb_raw(uint32_t st[8], const uint8_t *in, size_t len);

/* Digest from the state, the `tail_len` < 64 bytes not yet hashed and the total byte count;
 * nonzero (out untouched) when `total` ≥ FVAPI_SHA256_TOTAL_MAX. */
int fvapi_sha256_squeeze_raw(uint32_t st[8], const uint8_t *tail, size_t tail_len,
                             uint64_t total, uint8_t out[32]);

/* SHA-256 of `in[0, n)`; nonzero (out untouched) when `n` ≥ FVAPI_SHA256_TOTAL_MAX. */
int fvapi_sha256_raw(uint8_t out[32], const uint8_t *in, size_t n);

#endif
