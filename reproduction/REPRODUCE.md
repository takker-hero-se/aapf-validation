# Reproducing the Empirical Results

This document maps each empirical claim in the paper to the artifact in this Zenodo record that reproduces it.

## Quick start (single command)

```powershell
cd path\to\extracted\zenodo\record
.\reproduction\verify_pagesize.ps1   # Reproduces Table footnotes on page sizes
.\reproduction\parse_all.ps1         # Reproduces Table 5 and Section 5.5.2
```

The two scripts together complete in approximately 5 minutes on a modern Windows host. Reviewer wall-clock is dominated by the page-table walks on the 75 MB WS2025 NTDS.dit; faster machines complete in under 2 minutes.

## What is reproduced by what

| Claim in paper | Reproduction | Expected output |
|---|---|---|
| Section 5.5 (Table 5) Schema Robustness × Clean axis | `parse_all.ps1` | `expected_outputs.txt` lines 1–32 |
| Section 5.5 (Table 5) Crashed column | `parse_all.ps1` | `expected_outputs.txt` lines 33–48 |
| Section 5.5 (Table 5) Locked column | `parse_all.ps1` | `expected_outputs.txt` lines 49–72 |
| Section 5.5.2 State Resilience asymmetry | `parse_all.ps1` (diff of identity/2025/locked vs identity/2025/clean) | `expected_outputs.txt` notes section |
| Section 2.2 / Table 1 page sizes (4 KiB / 8 KiB / 16 KiB / 32 KiB) | `verify_pagesize.ps1` | All databases report the page sizes documented in MANIFEST.md |
| Section 3.2 / Figure 2 `itagState = 0x109A` for NTDS.dit | Manual hex inspection at file offset `0x78000` of `samples/identity/2025/clean/ntds.dit` | Bytes 34–35 = `9A 10` (little-endian = `0x109A`) |
| Section 6.2 / Issue 3 root cause for 16 KiB DataStore.edb | Manual hex inspection at file offset `0xC000` of `samples/health/2025/clean/DataStore.edb` | Bytes 34–35 = `41 10` (little-endian = `0x1041`) |
| Section 7.2 / Issue 4 root cause for 4 KiB SRUDB.dat | Manual hex inspection at file offset `0x3000` of `samples/resource/2025/clean/SRUDB.dat` | Bytes 34–35 = `10 10` (little-endian = `0x1010`) |
| Section 5.1 backward compatibility (mathematical no-op on WS2019) | Build unpatched libesedb and patched libesedb (`patches/` + reference upstream); diff `parse_all.ps1` output | Byte-identical results on all WS2019 samples |
| Credential value fidelity (decrypted NT/LM hashes, not just record counts) | Run `poneglyph.exe hashes` (v0.2.3, `poneglyph/poneglyph.exe`) and Impacket `secretsdump.py` v0.13.1 on both NTDS.dit samples; compare NT hashes per RID | `hash_value_validation.txt` — 2{,}494/2{,}494 (WS2019) and 2{,}492/2{,}492 (WS2025) byte-for-byte matches, zero mismatches |
| Client-side applicability (the format change is not server-only) | Run `poneglyph.exe info` and the Impacket ESE probe on the synthetic Windows 11 24H2+ client samples under `samples/{resource,health,activity}/w11-25h2/` | `client_applicability.txt` — 4/16/32 KiB all at revision `0x012C`; Impacket v0.13.1 still fails on the 4 KiB `SRUDB.dat` while the patch recovers all 15 tables |

## Value fidelity and client applicability (poneglyph 0.2.3)

Two verification artifacts extend the count-based Table 5 checks. Both are
pre-computed and shipped in this directory; the commands below regenerate them.

- **`hash_value_validation.txt`** — the deposited `poneglyph.exe` (v0.2.3)
  decrypts NT/LM credential hashes whose *values* match Impacket
  `secretsdump.py` v0.13.1 byte-for-byte on both NTDS.dit samples
  (2{,}494/2{,}494 on WS2019, 2{,}492/2{,}492 on WS2025, zero mismatches):

  ```powershell
  .\poneglyph\poneglyph.exe hashes --ntds samples\identity\2019\clean\ntds.dit `
      --system samples\identity\2019\clean\SYSTEM --format pwdump
  # compare per-RID NT hashes against:
  #   python secretsdump.py -ntds samples\identity\2019\clean\ntds.dit `
  #       -system samples\identity\2019\clean\SYSTEM LOCAL
  ```

- **`client_applicability.txt`** — the format change is *not* server-only. A
  synthetic Windows 11 24H2+ (build 26200 / 25H2) client contributes the full
  4/16/32 KiB spectrum under `samples/{resource,health,activity}/w11-25h2/`,
  all at revision `0x012C`. The latest Impacket (v0.13.1) still aborts on the
  4 KiB client `SRUDB.dat` while the patch recovers all 15 tables:

  ```powershell
  .\poneglyph\poneglyph.exe info --ntds samples\resource\w11-25h2\clean\SRUDB.dat   # -> Tables: 15
  python -c "from impacket.ese import ESENT_DB; ESENT_DB(r'samples\resource\w11-25h2\clean\SRUDB.dat')"
  # -> unpack requires a buffer of 2 bytes  (itagState failure)
  ```

## Hex inspection convenience snippets

```powershell
# Section 3.2 — WS2025 NTDS.dit page 4
Get-Content samples/identity/2025/clean/ntds.dit -AsByteStream -ReadCount 0 |
  Select-Object -First 491562 |
  Select-Object -Skip 491520 |   # offset 0x78000
  Select-Object -First 40 |
  ForEach-Object { '{0:X2}' -f $_ }

# Or equivalently via a one-line PowerShell script (see reproduction/inspect_pages.ps1)
```

## What is NOT reproduced

- **The original lab build-out.** Regenerating the server samples from scratch requires the exGOAD lab definitions (see https://github.com/takker-hero-se/exGOAD); the samples in this record are the captured outputs. The **client** samples under `*/w11-25h2/` are regenerated by the exGOAD `win11-ese` extension on any Windows 11 build >= 26100 (24H2) guest: its `verify_build.ps1` enforces the build gate (only 24H2+ carries revision `0x012C`), `populate_ese.ps1` generates synthetic SRUM/Windows-Update/WebCache activity, and `snapshot_ese.ps1` captures the databases. All client activity is synthetic, so the databases are redistributable.
- **The `dissect.esedb` PR #46 baseline.** The PR is open-source at https://github.com/fox-it/dissect.esedb/pull/46 and you can verify its size-gated behavior independently. Our claim is that PR #46's gate leaves the WS2025 16 KiB and 4 KiB samples in this record unparseable; you can verify this by running unmodified `dissect.esedb` against `samples/health/2025/clean/DataStore.edb` and observing the catalog read failure at page 4.

## Tolerance and known sources of nondeterminism

- **Record counts may drift by ±1** between Locked snapshots taken at different VSS-trigger moments. The Locked samples in this record are the specific captures used for Table 5; reviewer-side regeneration of Locked samples from a different live DC will not byte-match, but the qualitative claim (5 catalog tables missing on WS2025 Locked) is invariant.
- **WS2025 schema deltas** (the +1 table, +11 MSysObjects records relative to WS2019) reflect Microsoft's WS2025 default-AD-object additions and are stable across BadBlood runs with identical population parameters.

## Where to file reproducibility issues

If `parse_all.ps1` does not reproduce `expected_outputs.txt` byte-for-byte on your host, please file an issue with the diff at the corresponding author's contact (see `../CITATION.cff`).
