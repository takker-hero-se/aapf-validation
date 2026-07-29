# AAPF Validation Dataset: Cross-Page-Size ESE Format Changes in Windows Server 2025

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20789636.svg)](https://doi.org/10.5281/zenodo.20789636)
[![License: LGPL-3.0](https://img.shields.io/badge/License-LGPL--3.0-blue.svg)](LICENSE.md)
[![Patches: 7](https://img.shields.io/badge/patches-7-success.svg)](patches/)
[![AAPF samples: 14](https://img.shields.io/badge/samples-14%20acquisitions-informational.svg)](https://doi.org/10.5281/zenodo.20789636)

**Companion artifacts** for the paper *"Silent Evidence Loss in Windows Server 2025: Cross-Page-Size ESE Format Changes and Their Forensic Integrity Implications"* (Forensic Science International: Digital Investigation, 2026).

> **Code on GitHub, full archive on Zenodo.** This repository hosts the patches, reproduction scripts, and documentation. The 730 MB of ESE database samples is distributed via Zenodo (DOI above) and intentionally not in Git. After cloning, run `tools/package.ps1` to stage from a local AAPF samples tree, or download the samples directly from Zenodo.

This Zenodo record contains:

- **Patches** — minimal source-level patches for `libesedb` (the most widely deployed open-source Extensible Storage Engine parser) that resolve a previously unreported family of WS2025 `itagState` reinterpretation failures spanning 4 KiB, 16 KiB, and 32 KiB pages.
- **Poneglyph binary** — a Rust-based NTDS.dit analysis tool incorporating the universal patch, used as the reference parser in the paper's empirical validation.
- **AAPF samples** — Extensible Storage Engine database files (`ntds.dit`, `DataStore.edb`, `WebCacheV01.dat`, `SRUDB.dat`) acquired from isolated lab environments populated by `BadBlood`, `PSWindowsUpdate`, `Playwright`, and `Atomic Red Team`. Captured in three snapshot states (Clean, Crashed, Locked) per database, on both Windows Server 2019 and Windows Server 2025, for a total of 14 sample acquisitions.
- **Reproduction scripts** — batch verification helpers (`esentutl /mh` page-size verification; Poneglyph parse verification) and a reproducibility checklist tied to the manuscript's Tables 1, 4, 5, and 6.

The record is structured so that an examiner reviewing the paper can independently reproduce every empirical claim by running two batch scripts against the deposited samples and the deposited patched binary.

---

## Quick start

```powershell
# 1. Verify page sizes
.\reproduction\verify_pagesize.ps1

# 2. Reproduce parse outputs (Table 5)
.\reproduction\parse_all.ps1

# 3. Compare against expected outputs
diff (.\reproduction\parse_all.ps1) .\reproduction\expected_outputs.txt
```

A pre-computed `expected_outputs.txt` is included so reviewers can verify their reproduction without running the full pipeline.

---

## Contents

```
.
├── README.md                              # This file
├── CITATION.cff                           # How to cite this record
├── LICENSE.md                             # License summary (per-component)
├── ETHICAL_USE.md                         # Data origin & intended use; read first
├── MANIFEST.md                            # Detailed inventory & SHA-256 hashes
├── CHANGELOG.md                           # Version history
├── patches/
│   ├── README.md
│   ├── fix-ws2025-itag-state.patch        # ← key universal patch
│   ├── zzz-fix-ws2025-btree.patch
│   ├── fix-multi_value_guard.patch
│   ├── fix-max_leaf_pages.patch
│   ├── qol-leaf_pages.patch
│   └── fix-xwin.patch
├── poneglyph/
│   ├── README.md
│   ├── BUILD.md
│   └── poneglyph.exe                      # universal-patched Windows binary
├── samples/
│   ├── identity/                          # 8 KiB (WS2019) and 32 KiB (WS2025) NTDS.dit
│   │   ├── 2019/{clean,crashed,locked}/
│   │   └── 2025/{clean,crashed,locked}/
│   ├── health/                            # 16 KiB DataStore.edb
│   │   ├── 2019/{clean,crashed,locked}/
│   │   └── 2025/{clean,crashed,locked}/
│   ├── activity/                          # 32 KiB WebCacheV01.dat
│   │   └── 2019/{clean,crashed,locked}/   # (WS2025 not obtainable — see docs/)
│   └── resource/                          # 4 KiB SRUDB.dat
│       ├── 2019/{clean,partial}/
│       └── 2025/{clean,partial}/
├── reproduction/
│   ├── REPRODUCE.md
│   ├── verify_pagesize.ps1
│   ├── parse_all.ps1
│   └── expected_outputs.txt
└── docs/
    ├── BADBLOOD_PROVENANCE.md             # Synthetic-data generation details
    └── PAPER.md                           # Paper metadata & FSI:DI DOI (added on accept)
```

---

## Notable findings reproducible from this record

1. **Universal patch validation** — applying `patches/fix-ws2025-itag-state.patch` unconditionally (without a `page_size >= 32768` gate) resolves WS2025 16 KiB `DataStore.edb` and 4 KiB `SRUDB.dat` parsing failures that prior community fixes (e.g., dissect.esedb PR #46) leave unaddressed.

2. **Cross-page-size scope of the `itagState` reinterpretation** — the upper 4 bits of `itagState` (`ctagReserved`) are observed to be `0x0` on every WS2019 sample in the record and `0x1` on every WS2025 sample inspected, across 4 KiB, 16 KiB, and 32 KiB pages alike. The format change is *not* page-size-induced; it is OS-version-induced.

3. **State Resilience asymmetry** — the WS2025 NTDS.dit Locked sample (32 KiB, VSS snapshot of a running DC; `esentutl /mh` reports Dirty Shutdown) exhibits a partial-parse failure (catalog metadata and `datatable` missing) absent from its 8 KiB WS2019 counterpart. The pattern is documented in `samples/identity/2025/locked/` and `samples/identity/2019/locked/`.

4. **Backward compatibility** — applying the universal patch to WS2019 databases of any page size produces byte-identical results to the unpatched parser, because the upper 4 bits of `itagState` are zero in every WS2019 sample inspected.

---

## Citation

If you use this dataset, please cite both the paper and the dataset.

For the dataset, use the BibTeX in `CITATION.cff` or simply:

> Hirose, T. (2026). *AAPF Validation Dataset: Cross-Page-Size ESE Format Changes in Windows Server 2025* [Data set]. Zenodo. https://doi.org/10.5281/zenodo.20789636

For the paper, see `docs/PAPER.md`.

---

## License

- Patches (`patches/*.patch`) are derivative works of `libesedb` (LGPL-3.0) and are released under LGPL-3.0.
- Poneglyph binary (`poneglyph/poneglyph.exe`) is built from sources released under LGPL-3.0 with statically linked LGPL components.
- Documentation, reproduction scripts, and `MANIFEST.md` are released under **CC-BY-4.0**.
- Sample databases (`samples/`) are released under **CC0-1.0** as factual outputs of automated tools applied to isolated lab environments; see `ETHICAL_USE.md` for the intended-use statement and `docs/BADBLOOD_PROVENANCE.md` for the generation provenance.

See `LICENSE.md` for the full per-component breakdown.

---

## Ethical use statement

This dataset contains synthetic Active Directory databases. Although NT hashes for the synthetic accounts can in principle be extracted from `samples/identity/`, the underlying data is generated by [`BadBlood`](https://github.com/davidprowe/BadBlood) in isolated lab environments and contains no real personally identifiable information, real user accounts, or real credentials.

The intended use of this dataset is the validation and regression testing of open-source ESE forensic parsers. Use against production systems, or to attack real Active Directory deployments, is **not** an intended use.

See `ETHICAL_USE.md` for the full statement.

---

## Authors and contact

- **Takayuki Hirose** — Independent Researcher

Corresponding author: Takayuki Hirose, `takker0708@gmail.com`

---

## Related work

- Fox-IT's [`dissect.esedb`](https://github.com/fox-it/dissect.esedb) PR [#46](https://github.com/fox-it/dissect.esedb/pull/46) (Schamper, April 2025) addressed the 32 KiB case for the Python parser; this dataset documents the previously unreported 16 KiB and 4 KiB cases and the universal one-line patch.
- libesedb issue [#78](https://github.com/libyal/libesedb/issues/78) is the corresponding upstream report for the C library.
- Velociraptor issue [#4606](https://github.com/Velocidex/velociraptor/issues/4606) corroborates the WebCache failure (independent confirmation from Mike Cohen).
