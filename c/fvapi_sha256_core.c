#include "fvapi_sha256_core.h"

#include "Hacl_Hash_SHA2.h"
#include "internal/Hacl_Hash_SHA2.h"

_Static_assert(FVAPI_SHA256_CHUNK % 64 == 0, "chunks hand HACL whole blocks");
_Static_assert(FVAPI_SHA256_CHUNK <= UINT32_MAX && FVAPI_SHA256_ONESHOT_MAX <= UINT32_MAX,
               "HACL lengths are uint32_t");

void fvapi_sha256_init_raw(uint32_t st[8]) { Hacl_Hash_SHA2_sha256_init(st); }

void fvapi_sha256_absorb_raw(uint32_t st[8], const uint8_t *in, size_t len) {
    for (size_t off = 0; off < len;) {
        size_t n = len - off < FVAPI_SHA256_CHUNK ? len - off : FVAPI_SHA256_CHUNK;
        Hacl_Hash_SHA2_sha256_update_nblocks((uint32_t)n, (uint8_t *)in + off, st);
        off += n;
    }
}

int fvapi_sha256_squeeze_raw(uint32_t st[8], const uint8_t *tail, size_t tail_len,
                             uint64_t total, uint8_t out[32]) {
    if (total >= FVAPI_SHA256_TOTAL_MAX) {
        return 1;
    }
    Hacl_Hash_SHA2_sha256_update_last(total, (uint32_t)tail_len, (uint8_t *)tail, st);
    Hacl_Hash_SHA2_sha256_finish(st, out);
    return 0;
}

int fvapi_sha256_raw(uint8_t out[32], const uint8_t *in, size_t n) {
    if ((uint64_t)n >= FVAPI_SHA256_TOTAL_MAX) {
        return 1;
    }
    if (n <= FVAPI_SHA256_ONESHOT_MAX) {
        Hacl_Hash_SHA2_hash_256(out, (uint8_t *)in, (uint32_t)n);
        return 0;
    }
    uint32_t st[8] = {0};
    size_t whole = n - n % 64;
    fvapi_sha256_init_raw(st);
    fvapi_sha256_absorb_raw(st, in, whole);
    return fvapi_sha256_squeeze_raw(st, in + whole, n % 64, (uint64_t)n, out);
}
