# `libesedb` Patches — AAPF Validation Dataset

This directory contains source-level patches against the `libesedb-20230824` upstream release of [`libesedb`](https://github.com/libyal/libesedb) by Joachim Metz.

## Apply order

Apply in the lexicographic order of the filenames (the `qol-` and `zzz-` prefixes are chosen so this ordering is correct):

1. `fix-max_leaf_pages.patch`
2. `fix-multi_value_guard.patch`
3. `fix-ws2025-itag-state.patch` — **key universal patch**, see below
4. `fix-xwin.patch`
5. `qol-leaf_pages.patch`
6. `zzz-fix-ws2025-btree.patch` — B-tree leaf-chain `IS_LEAF` validation

## Patch summaries

### `fix-ws2025-itag-state.patch` (universal `itagState` mask)

The core patch of the paper. Modifies `libesedb/libesedb_page_header.c` to mask the `available_page_tag` field with `0x0FFF` immediately after reading it, **unconditionally** (i.e., without gating on `io_handle->page_size >= 32768`).

The unconditional application is required to resolve the WS2025 16 KiB `DataStore.edb` and 4 KiB `SRUDB.dat` failures reported in Sections 6 and 7 of the companion paper. The earlier size-gated formulation (which appears in Fox-IT's `dissect.esedb` PR #46 in a semantically equivalent form) leaves these failures unaddressed.

Backward compatibility on WS2019 databases is preserved as a mathematical no-op: the upper 4 bits of `itagState` are zero on every WS2019 page in our AAPF samples, so `x & 0x0FFF == x` whenever the unpatched parser would have read the field.

### `zzz-fix-ws2025-btree.patch` (B-tree `IS_LEAF` validation)

Modifies `libesedb/libesedb_page_tree.c` to validate the `IS_LEAF` page flag during both the backward walk in `libesedb_page_tree_get_first_leaf_page_number()` and the forward walk in `libesedb_page_tree_get_number_of_leaf_values()`. If a page returned from the link chain lacks the `IS_LEAF` flag, the walk is broken cleanly rather than continuing into the zeroed page.

Triggered by the page-847 case documented in Section 4 of the paper (`link_table` in WS2025 NTDS.dit). On WS2019 8 KiB databases this check never triggers because the chain contains only leaf pages.

### `fix-max_leaf_pages.patch`, `qol-leaf_pages.patch`

Quality-of-life increases to the upper bound on the number of leaf pages that the parser will walk. Originated from upstream and are reapplied here for completeness.

### `fix-multi_value_guard.patch`

Defensive guard around multi-value attribute extraction. Required for some BadBlood-generated DCs that produce unusually long attribute value lists.

### `fix-xwin.patch`

Cross-Windows build-system fix (MinGW-w64 GCC 15 compatibility). Originated from libesedb-sys but reapplied here for the standalone build path.

## How to apply

If you're using `libesedb-sys` from `Cargo.toml`:

```toml
[patch.crates-io]
libesedb-sys = { path = "path/to/libesedb-sys-patched" }
```

If you're applying to a vanilla libesedb checkout:

```bash
git clone https://github.com/libyal/libesedb.git
cd libesedb
git checkout libesedb-20230824   # or the equivalent tag
for p in /path/to/this/patches/*.patch; do
  patch -p0 < "$p"
done
./synclibs.sh && ./autogen.sh && ./configure && make
```

## Reference

The patches are also tracked in the upstream issue [libesedb #78](https://github.com/libyal/libesedb/issues/78). The version distributed here is the snapshot used for the paper's empirical validation. As the issue progresses (potentially toward an upstream pull request), the canonical version may move to a maintained branch; check the issue URL for the latest state.

## License

These patches are derivative works of `libesedb` and inherit its LGPL-3.0-or-later license terms. See `../LICENSE.md`.
