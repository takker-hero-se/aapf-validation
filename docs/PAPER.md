# Companion Paper

This Zenodo record accompanies the following paper.

## Title

*Silent Evidence Loss in Windows Server 2025: Cross-Page-Size ESE Format Changes and Their Forensic Integrity Implications*

## Authors

- Takayuki Hirose (Independent Researcher, corresponding author: `takker0708@gmail.com`)
- Hiroshi Koide (Cybersecurity Information Systems Research Division, Research Institute for Information Technology, Kyushu University)

## Target venue

Forensic Science International: Digital Investigation (FSI:DI), Elsevier, Open Access (Gold OA).

## Status

Submitted 2026; under peer review at the time of this dataset release.

## Abstract (excerpt)

> Windows Server 2025 introduced multiple undocumented format changes to the Extensible Storage Engine (ESE), the embedded database engine underlying Active Directory (`NTDS.dit`), Windows Update history (`DataStore.edb`), the System Resource Usage Monitor (`SRUDB.dat`), and the Edge/IE web cache (`WebCacheV01.dat`). Although the most visible change is the new optional 32KiB page size for Active Directory, we empirically demonstrate---through an Automated Artifact Population Framework (AAPF) spanning four ESE-backed Windows artifacts in three shutdown states---that the underlying `itagState` bitfield reinterpretation applies *independently of page size*: 32KiB `NTDS.dit`, 16KiB `DataStore.edb`, and 4KiB `SRUDB.dat` all exhibit the identical `libesedb_page_read_tags: invalid number of page tags` failure at the catalog metadata page (page 4) on Windows Server 2025, while their byte-identical 4KiB/16KiB/32KiB counterparts on Windows Server 2019 parse without error. […]

## Mapping from paper sections to this Zenodo record

| Paper section | This record |
|---|---|
| §2 Background | `docs/BADBLOOD_PROVENANCE.md` (provenance of synthetic ESE artifacts) |
| §3 Issue 1 (itagState, 32 KiB) | `samples/identity/2025/clean/ntds.dit`; `reproduction/REPRODUCE.md` Section 3.2 row |
| §4 Issue 2 (B-tree zeroed page) | `samples/identity/2025/{clean,crashed,locked}/`; `patches/zzz-fix-ws2025-btree.patch` |
| §5 Universal fix | `patches/fix-ws2025-itag-state.patch`; `poneglyph/poneglyph.exe` |
| §6 Issue 3 (16 KiB DataStore) | `samples/health/2025/{clean,crashed,locked}/` |
| §7 Issue 4 (4 KiB SRUDB) | `samples/resource/2025/{clean,partial}/` |
| §8 Validation (AAPF) | `samples/`; `reproduction/parse_all.ps1`; `reproduction/expected_outputs.txt` |
| Table 1 (page sizes) | `reproduction/verify_pagesize.ps1` |
| Table 5 (AAPF matrix) | `reproduction/parse_all.ps1` against the full `samples/` tree |
| §5.5.2 (State Resilience asymmetry) | `samples/identity/{2019,2025}/locked/` diff against `clean/` |

## DOI

This dataset: `10.5281/zenodo.XXXXXXX` (assigned at upload; update CITATION.cff and the in-text references to this DOI before final paper submission).

Companion paper DOI: assigned by Elsevier on acceptance; add here when known.

## Preprint

If a preprint of the companion paper is available before the journal version, it will be linked here:

- TechRxiv: TODO (URL to be added)
- Or SSRN: TODO
- Or institutional repository: TODO

## License

This file is CC-BY-4.0.
