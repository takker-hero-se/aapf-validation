# Reproducing the `poneglyph.exe` binary

The binary `poneglyph.exe` in this directory is provided as-is. If you want to reproduce or modify it, follow these steps.

## Prerequisites

- Windows 10/11 host (Linux/macOS not supported by this build path)
- MSYS2 with the following packages:
  ```
  pacman -S mingw-w64-x86_64-binutils mingw-w64-x86_64-gcc --noconfirm
  ```
- Rust toolchain via `rustup`:
  ```
  rustup toolchain install stable-x86_64-pc-windows-gnu
  rustup default stable-x86_64-pc-windows-gnu
  ```

## Step 1 — Patched `libesedb-sys`

Take the upstream `libesedb-sys` v0.2.1 source and apply the patches in the `patches/` sibling directory of this Zenodo record. The simplest path is to place a patched checkout at `C:\dev\libesedb-sys-patched\` and reference it from your Poneglyph `Cargo.toml`:

```toml
[patch.crates-io]
libesedb-sys = { path = "C:/dev/libesedb-sys-patched" }
```

Verify by running `cargo metadata` and confirming that `libesedb-sys` resolves to the local path.

## Step 2 — Poneglyph source

Clone Poneglyph from https://github.com/takker-hero-se/Poneglyph . Reference release: v0.2.3.

## Step 3 — Build

In a PowerShell session (not bash; bash has issues with the Japanese paths some Poneglyph workspaces have):

```powershell
$env:PATH = "C:\Users\<you>\.cargo\bin;C:\msys64\mingw64\bin;C:\msys64\usr\bin;" + $env:PATH
$env:CFLAGS = "-DHAVE_WINDOWS_H=1 -DWIN32_LEAN_AND_MEAN=1 -Wno-error=implicit-function-declaration -Wno-error=int-conversion"

cd path\to\Poneglyph
cargo build --release

Get-FileHash -Algorithm SHA256 target\release\poneglyph.exe
```

Compare the SHA-256 of your build with `../MANIFEST.md` to verify a faithful reproduction.

## CFLAGS rationale

- `-DHAVE_WINDOWS_H=1` — `libesedb-sys` v0.2.1's `build.rs` (lines 148–167) does not define `HAVE_WINDOWS_H` for the Windows code path, causing the Windows-API code paths in libesedb to be silently disabled.
- `-DWIN32_LEAN_AND_MEAN=1` — prevents `windows.h` from pulling in `x86intrin.h → immintrin.h → movrsintrin.h`, which collides with libesedb's include paths.
- `-Wno-error=implicit-function-declaration -Wno-error=int-conversion` — GCC 15 promoted these from warnings to errors in 2024; libesedb-20230824 contains pre-modern C constructs that need this relaxation.

## Build troubleshooting

If you encounter `dlltool.exe not found`, install `mingw-w64-x86_64-binutils` as documented in Prerequisites.

If you encounter `gcc.exe not found`, ensure your PATH includes `C:\msys64\mingw64\bin` before any other GCC installation.

If `cargo clean -p libesedb-sys` does not pick up your patch changes, also delete `target/release/build/libesedb-sys-*/` and rebuild.

## License

The Poneglyph source is LGPL-3.0-or-later. See https://github.com/takker-hero-se/Poneglyph for the source repository and full license terms.

## Fix 2 ablation builds

Two extra binaries accompany this record so the Fix 2 claim can be checked
rather than taken on trust:

| Binary | libesedb patches | Contains |
|---|---|---|
| `poneglyph-withfix2.exe` | 001-006 | Fix 1 (revision-gated `itagState` mask) **and** Fix 2 (B-tree `IS_LEAF` guard) |
| `poneglyph-nofix2.exe` | 001-005 | Fix 1 only; patch `006-ws2025-btree` removed |

Both were built on 2026-09-24 from one source tree (poneglyph 0.2.3), so the
only difference between them is Fix 2. Running both over every sample in
`samples/` gives identical table and record counts on all 22 of them, in every
acquisition state, on both server editions and on the Windows 11 client.

`reproduction/fix2_ablation.txt` records the per-sample output of that run
together with the SHA-256 of each binary. The conclusion it supports is narrow
and deliberately stated as such in the paper: Fix 2 is **inert on this corpus**.
Its triggering condition was observed once, in a dirty 32 KiB acquisition that
is not part of the deposit, so a reviewer cannot reproduce the abort it
prevents from these artifacts alone.

Note that `poneglyph.exe` (the 0.2.3 release binary shipped here) is a third,
earlier build and hashes differently from both; it is not one of the two
compared above.
