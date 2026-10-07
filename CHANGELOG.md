# Changelog

All notable changes to this Zenodo record are documented here. Versioning follows [Semantic Versioning](https://semver.org/) for the dataset; patch releases denote corrections that do not change the contents (e.g., documentation typo fixes).

## [1.1.0] — 2026-10-04

Second Zenodo version. Everything below was in the repository after the
v1.0.0 record (2026-06-22) and is now in the record.

### Added

- **Eight more acquisitions**, bringing the sample set to **22**: Identity 6,
  Health 7, Activity 4, Resource 5, across Windows Server 2019, Windows Server
  2025 and a synthetic Windows 11 25H2 client. Resource now includes the
  `partial` state (the DPS-held `SRUDB.dat` captured live).
- **Fix 2 ablation pair** under `poneglyph/`: `poneglyph-withfix2.exe` and
  `poneglyph-nofix2.exe`, built from one source tree differing only in the
  Fix 2 patch, with the record showing identical counts on all 22 samples.
- **Three-parser agreement** section in the reproduction docs (patched
  libesedb vs `impacket.ese` vs `dissect.esedb` on both `ntds.dit` samples).
- **Tag-count bound scan** (`reproduction/tag_bound_scan.ps1`): derives the
  maximum number of tags a 32 KiB page can carry from the engine's own node
  accounting and reads the tag array of every 32 KiB page in three samples.
  Shows that no real record type can push a legacy page past the 12-bit
  count (table leaf ≤ 3,268 lines; densest deposited page 2,514).
- **ESE format-revision survey** (`survey_ese_revisions.ps1`) and its result
  from the pinned client sandbox.

- **Synthetic Windows 11 client axis** under `samples/*/w11-25h2/clean/`:
  `SRUDB.dat` (4 KiB), `DataStore.edb` (16 KiB) and `WebCacheV01.dat` (32 KiB),
  all at format revision `0x012C`, so the page-size spectrum is covered on a
  client OS as well as on a server.
- **Self-recording verification sandbox** under `reproduction/sandbox/`: one
  `vagrant up` builds a disposable, network-isolated Windows VM, re-derives the
  paper's numbers as pass/fail assertions, and screen-records the run.
- **Vendored toolchain** under `vendor/` (Python installer, `ffmpeg.exe`,
  Impacket 0.13.1 wheels): provisioning needs no network, so the sandbox stays
  isolated and its tool versions stay pinned.

### Changed

- The sandbox now runs **69 assertions** rather than the original 32. The added
  sections are three negative controls that must trip, the client axis, a
  credential value-fidelity cross-check that re-derives the Poneglyph/Impacket
  agreement on every run instead of citing
  `reproduction/hash_value_validation.txt`, and three-parser record-count
  agreement.
- `reproduction/verification-evidence/` now holds the 69-assertion run recorded
  on 2026-09-23 (69 PASS / 0 FAIL). It replaces the 32-assertion run of
  2026-09-04, which the documentation had outgrown.
- The companion paper's title is now "Silent Evidence Loss in Modern Windows: A Detectable Class of Version-Gated Format Change and Its ESE Instance"; the dataset title gains "and
  Windows 11" to match the client axis. Hiroshi Koide (Kyushu University) is
  a co-author of the paper; the dataset creator is unchanged.
- "Previously unreported" is no longer claimed: Microsoft's open-source engine
  headers define the itagState split, and the dissect.esedb and Impacket
  threads reported the 4 KiB and 32 KiB cases first. The paper's claim is the
  controlled attribution to the format revision.

## [1.0.0] — 2026-06-14 (published 2026-06-22)

Initial public release accompanying paper submission.

### Corrections during staging (pre-upload)

- **Poneglyph `poneglyph.exe` bumped 0.2.2 → 0.2.3.** Fixed the AES (`CRYPTED_HASHW16`)
  per-account hash-decryption offset: the ciphertext begins at byte 28, after the 4-byte
  `Unknown` field, not byte 24 (the legacy RC4 `CRYPTED_HASH` layout). The previous binary
  decrypted the correct *number* of hashes but produced corrupted *values* on all
  AES-format (Windows 2016+) databases. Record/user/membership counts are unaffected. The
  0.2.3 binary's NT/LM output is now byte-for-byte identical to impacket `secretsdump.py`
  (2494/2494 WS2019, 2492/2492 WS2025); see `reproduction/hash_value_validation.txt`.
- **Upstream `libesedb` adopted the revision-gated fix.** After the defect was reported
  (issue #78, PR #79), the `libesedb` maintainer incorporated an equivalent
  format-revision-gated fix (`format_revision >= 0x0122`, commit `768a0474`) and released it
  in **release 20260704** (2026-07-04). These patches reproduce the paper's pinned
  `libesedb-sys` 0.2.1 build; on current upstream the equivalent fix is already present.
  Page-size-gated tools (Impacket, `dissect.esedb`) still miss the 4 KiB case.

### Includes

- Universal `& 0x0FFF` patch for `libesedb_page_header.c` (cross-page-size scope)
- B-tree `IS_LEAF` validation patch for `libesedb_page_tree.c`
- 4 quality-of-life / build-system patches
- Poneglyph Windows binary (`poneglyph.exe`) v0.2.3, Rust 1.78, GCC 15
- 14 sample acquisitions across Identity, Health, Activity, Resource categories
- Client axis: synthetic Windows 11 24H2+ (build 26200 / 25H2) samples --- 4 KiB `SRUDB.dat` and 16 KiB `DataStore.edb` at ESE format revision `0x012C`, demonstrating that the change reaches client Windows and is not server-only. The latest Impacket (v0.13.1) still fails on the 4 KiB client `SRUDB.dat`; see `reproduction/client_applicability.txt`. Generated by the exGOAD `win11-ese` extension from synthetic activity (redistributable, unlike a real user's SRUM).
- Reproduction scripts (`verify_pagesize.ps1`, `parse_all.ps1`)
- Pre-computed expected outputs (`expected_outputs.txt`)
- Provenance documentation (BadBlood, PSWindowsUpdate, Playwright, Atomic Red Team)
- Ethical use statement
- Per-component license summary

### Known gaps

- WS2025 Activity (WebCacheV01.dat) samples are not included; see `ETHICAL_USE.md` and `docs/BADBLOOD_PROVENANCE.md` for the documented-unobtainable rationale.
- Resource × Locked samples are not included; capture timing characterization is in progress.
- Data Integrity per-field axis (SIDs, hashes, URLs, timestamps) for Health / Activity / Resource categories is not yet populated; planned for v1.1.

### Pending pre-upload TODOs (see in-document TODO markers)

- Pin tool versions in `docs/BADBLOOD_PROVENANCE.md`
- Replace `XXXXXXX` Zenodo DOI placeholders in `CITATION.cff`, `.zenodo.json`, `README.md`, and `docs/PAPER.md`
- Add ORCID iDs in `CITATION.cff` and `.zenodo.json`
- Compute and record SHA-256 hashes for every file in `MANIFEST.md` (use `tools/package.ps1`)
