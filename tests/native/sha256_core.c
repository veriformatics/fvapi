/* Drives c/fvapi_sha256_core.c under ASan + UBSan, built with small ceilings
 * (FVAPI_SHA256_ONESHOT_MAX=100, FVAPI_SHA256_CHUNK=128) so short inputs take the chunk loop:
 * FIPS 180-2 vectors, then every length 0..1500 one-shot and as random block-aligned streams,
 * each against HACL's own one-shot composition (docs/contracts/U3-codecs.md S5). Each input sits
 * in an exact-size heap block, so a read past its end trips ASan. rc = 1 on any failure. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Hacl_Hash_SHA2.h"
#include "fvapi_sha256_core.h"

static int failures;

static uint64_t rng = 0x9e3779b97f4a7c15u;
static uint64_t next(void) {
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

static void hex(const uint8_t d[32], char out[65]) {
    for (int i = 0; i < 32; i++) {
        snprintf(out + 2 * i, 3, "%02x", d[i]);
    }
}

/* A heap copy of exactly `n` bytes (ASan's redzone starts at in + n). */
static uint8_t *exact(const uint8_t *src, size_t n) {
    uint8_t *p = malloc(n ? n : 1);
    if (!p) {
        abort();
    }
    if (n) {
        memcpy(p, src, n);
    }
    return p;
}

static void vector(const char *name, const uint8_t *src, size_t n, const char *want) {
    uint8_t d[32];
    char got[65];
    uint8_t *in = exact(src, n);
    if (fvapi_sha256_raw(d, in, n) != 0) {
        printf("FAIL %s: rejected\n", name);
        failures++;
    } else if (hex(d, got), strcmp(got, want) != 0) {
        printf("MISMATCH %s: %s != %s\n", name, got, want);
        failures++;
    }
    free(in);
}

/* Hashes `in[0, n)` as whole-block absorbs of random sizes, then the tail. */
static void stream(uint8_t d[32], const uint8_t *in, size_t n) {
    uint32_t st[8];
    size_t whole = n - n % 64, off = 0;
    fvapi_sha256_init_raw(st);
    while (off < whole) {
        size_t blocks = (whole - off) / 64, take = 64 * (1 + next() % blocks);
        uint8_t *piece = exact(in + off, take);
        fvapi_sha256_absorb_raw(st, piece, take);
        free(piece);
        off += take;
    }
    uint8_t *tail = exact(in + whole, n % 64);
    if (fvapi_sha256_squeeze_raw(st, tail, n % 64, n, d) != 0) {
        printf("FAIL stream n=%zu: rejected\n", n);
        failures++;
    }
    free(tail);
}

int main(void) {
    static uint8_t data[1501], million[1000000];
    int vectors = 0, lengths = 0, streams = 0;
    vector("abc", (const uint8_t *)"abc", 3,
           "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    vector("empty", (const uint8_t *)"", 0,
           "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    vector("448-bit", (const uint8_t *)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
           56, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    vector("896-bit",
           (const uint8_t *)"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
                            "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
           112, "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");
    memset(million, 'a', sizeof million);
    vector("million-a", million, sizeof million,
           "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
    vectors = 5;

    for (size_t i = 0; i < sizeof data; i++) {
        data[i] = (uint8_t)next();
    }
    for (size_t n = 0; n <= 1500; n++) {
        uint8_t want[32], got[32], streamed[32];
        uint8_t *in = exact(data, n);
        Hacl_Hash_SHA2_hash_256(want, in, (uint32_t)n);
        if (fvapi_sha256_raw(got, in, n) != 0 || memcmp(got, want, 32) != 0) {
            printf("MISMATCH one-shot n=%zu\n", n);
            failures++;
        }
        lengths++;
        stream(streamed, in, n);
        if (memcmp(streamed, want, 32) != 0) {
            printf("MISMATCH stream n=%zu\n", n);
            failures++;
        }
        streams++;
        free(in);
    }

    /* The 2^61-byte limit: rejected, the output untouched. */
    uint32_t st[8];
    uint8_t out[32], before[32];
    memset(out, 0xa5, sizeof out);
    memcpy(before, out, sizeof out);
    fvapi_sha256_init_raw(st);
    if (fvapi_sha256_squeeze_raw(st, data, 0, FVAPI_SHA256_TOTAL_MAX, out) == 0 ||
        memcmp(out, before, sizeof out) != 0) {
        printf("FAIL total limit: accepted or wrote output\n");
        failures++;
    }

    printf("sha256-core: vectors=%d lengths=%d streams=%d failures=%d\n", vectors, lengths, streams,
           failures);
    return failures ? 1 : 0;
}
