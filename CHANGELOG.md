# Changelog

All notable changes to this Zenodo record are documented here. Versioning follows [Semantic Versioning](https://semver.org/) for the dataset; patch releases denote corrections that do not change the contents (e.g., documentation typo fixes).

## [1.0.0] — 2026-06-14 (planned)

Initial public release accompanying paper submission.

### Corrections during staging (pre-upload)

- **Poneglyph `poneglyph.exe` bumped 0.2.2 → 0.2.3.** Fixed the AES (`CRYPTED_HASHW16`)
  per-account hash-decryption offset: the ciphertext begins at byte 28, after the 4-byte
  `Unknown` field, not byte 24 (the legacy RC4 `CRYPTED_HASH` layout). The previous binary
  decrypted the correct *number* of hashes but produced corrupted *values* on all
  AES-format (Windows 2016+) databases. Record/user/membership counts are unaffected. The
  0.2.3 binary's NT/LM output is now byte-for-byte identical to impacket `secretsdump.py`
  (2494/2494 WS2019, 2492/2492 WS2025); see `reproduction/hash_value_validation.txt`.

### Includes

- Universal `& 0x0FFF` patch for `libesedb_page_header.c` (cross-page-size scope)
- B-tree `IS_LEAF` validation patch for `libesedb_page_tree.c`
- 4 quality-of-life / build-system patches
- Poneglyph Windows binary (`poneglyph.exe`) v0.2.3, Rust 1.78, GCC 15
- 14 sample acquisitions across Identity, Health, Activity, Resource categories
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
