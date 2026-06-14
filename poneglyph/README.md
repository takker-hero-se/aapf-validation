# Poneglyph — NTDS.dit Analysis Tool with Universal Patch

`poneglyph.exe` is a Rust-based command-line tool for NTDS.dit and (more generally) ESE database analysis, statically built against the universal-patched `libesedb-sys`. The binary in this directory is the exact build used to produce the empirical results in the companion paper's Section 5 (Validation: AAPF) and Section 6/7 (Issues 3 and 4).

## Quick start

```powershell
# Display database information (page size, tables, record counts)
.\poneglyph.exe info --ntds "path\to\ntds.dit"

# Other subcommands (NTDS.dit-specific, require SYSTEM hive for credential extraction)
.\poneglyph.exe users   --ntds path\to\ntds.dit
.\poneglyph.exe hashes  --ntds path\to\ntds.dit --system path\to\SYSTEM
.\poneglyph.exe dump    --ntds path\to\ntds.dit --system path\to\SYSTEM --output-dir out
```

For non-NTDS databases (`DataStore.edb`, `SRUDB.dat`, `WebCacheV01.dat`), only the `info` subcommand is meaningful; the credential-specific subcommands are NTDS.dit-only by design.

## What this binary contains

- Universal `& 0x0FFF` patch on the `available_page_tag` field (`patches/fix-ws2025-itag-state.patch`)
- B-tree `IS_LEAF` validation patch (`patches/zzz-fix-ws2025-btree.patch`)
- All other patches in the `patches/` sibling directory

Verify by re-parsing any sample from `samples/` and comparing to `samples/**/_validation/poneglyph-info-*.txt`.

## Build provenance

- Toolchain: `stable-x86_64-pc-windows-gnu` (Rust 1.78+)
- C compiler: MinGW-w64 GCC 15 (MSYS2 distribution)
- CFLAGS: `-DHAVE_WINDOWS_H=1 -DWIN32_LEAN_AND_MEAN=1 -Wno-error=implicit-function-declaration -Wno-error=int-conversion`
- Build command: `cargo build --release`
- Build host: Windows 11 24H2

See `BUILD.md` for full reproducibility instructions including the `libesedb-sys` patch source and the CFLAGS rationale.

## License

LGPL-3.0-or-later. The binary statically links libesedb (LGPL-3.0); see `../LICENSE.md`.

Poneglyph source: https://github.com/takker-hero-se/Poneglyph
