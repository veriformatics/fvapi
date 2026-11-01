/* Lean FFI glue over c/fvapi_sha256_core.c (docs/contracts/U3-codecs.md S3): Lean objects in,
 * Lean objects out. An invariant the Lean side keeps aborts when violated, never a wrong digest;
 * nothing allocates except Lean result arrays. */
#include <lean/lean.h>

#include "fvapi_sha256_core.h"

static void require(int ok, const char *what) {
    if (!ok) {
        lean_internal_panic(what);
    }
}

static void load_state(b_lean_obj_arg h, uint32_t st[8]) {
    require(lean_sarray_size(h) == 32, "fvapi_sha256: state is not 32 bytes");
    __builtin_memcpy(st, lean_sarray_cptr(h), 32);
}

/* sha256 : @& ByteArray → ByteArray */
LEAN_EXPORT lean_obj_res fvapi_sha256(b_lean_obj_arg input) {
    lean_object *out = lean_alloc_sarray(1, 32, 32);
    require(fvapi_sha256_raw(lean_sarray_cptr(out), lean_sarray_cptr(input),
                             lean_sarray_size(input)) == 0,
            "fvapi_sha256: input of 2^61 bytes or more");
    return out;
}

/* Sha256.initState : Unit → ByteArray (HACL's eight chaining words) */
LEAN_EXPORT lean_obj_res fvapi_sha256_init(lean_obj_arg unit) {
    (void)unit;
    uint32_t st[8];
    lean_object *h = lean_alloc_sarray(1, 32, 32);
    fvapi_sha256_init_raw(st);
    __builtin_memcpy(lean_sarray_cptr(h), st, 32);
    return h;
}

/* Sha256.absorb : ByteArray → @& ByteArray → USize → USize → ByteArray: hashes the whole blocks
 * `data[off, off + len)` (`len` a multiple of 64) into a copy of the state (in place when the
 * state is unshared). */
LEAN_EXPORT lean_obj_res fvapi_sha256_absorb(lean_obj_arg h, b_lean_obj_arg data, size_t off,
                                             size_t len) {
    size_t size = lean_sarray_size(data);
    uint32_t st[8];
    require(off <= size && len <= size - off && len % 64 == 0,
            "fvapi_sha256: absorb span outside the data or not whole blocks");
    load_state(h, st);
    fvapi_sha256_absorb_raw(st, lean_sarray_cptr(data) + off, len);
    if (!lean_is_exclusive(h)) {
        lean_dec_ref(h);
        h = lean_alloc_sarray(1, 32, 32);
    }
    __builtin_memcpy(lean_sarray_cptr(h), st, 32);
    return h;
}

/* Sha256.squeeze : @& ByteArray → @& ByteArray → UInt64 → ByteArray: the digest from a state, the
 * < 64 bytes not yet hashed (`total` ≡ their count mod 64) and every byte fed. */
LEAN_EXPORT lean_obj_res fvapi_sha256_squeeze(b_lean_obj_arg h, b_lean_obj_arg tail,
                                              uint64_t total) {
    uint32_t st[8];
    size_t tail_len = lean_sarray_size(tail);
    require(tail_len < 64 && total % 64 == tail_len,
            "fvapi_sha256: squeeze tail or total inconsistent");
    load_state(h, st);
    lean_object *out = lean_alloc_sarray(1, 32, 32);
    require(fvapi_sha256_squeeze_raw(st, lean_sarray_cptr(tail), tail_len, total,
                                     lean_sarray_cptr(out)) == 0,
            "fvapi_sha256: input of 2^61 bytes or more");
    return out;
}
