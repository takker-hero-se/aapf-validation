# Contributing

Thank you for your interest in contributing to the AAPF Validation project. This document covers the practical mechanics of filing issues and pull requests against this repository.

## Scope

This repository is the companion artifact for the FSI:DI 2026 paper *Silent Evidence Loss in Windows Server 2025: Cross-Page-Size ESE Format Changes and Their Forensic Integrity Implications*. Contributions are most valuable when they:

1. **Extend AAPF coverage** — additional ESE artifacts (Windows Search `Windows.edb`, Exchange `priv.edb`, Lync archives), additional OS versions, additional snapshot states.
2. **Improve reproduction** — port `reproduction/*.ps1` to bash for Linux examiners, add Jupyter notebooks for visual inspection, add Docker images for reproducibility.
3. **Strengthen the patches** — alternative formulations of `fix-ws2025-itag-state.patch` (e.g., format-revision-based discrimination instead of unconditional mask), bug fixes, performance improvements.
4. **Document related findings** — additional ESE format changes you have identified in WS2025, WS2026, or future Microsoft releases.
5. **Translate documentation** — Japanese, Korean, Chinese translations of the README and reproduction guides are especially welcome.

Contributions **out of scope** for this repository:

- Generic libesedb improvements unrelated to WS2025 — please file those upstream at https://github.com/libyal/libesedb.
- Active Directory hardening / detection rules — those belong in their respective project ecosystems.
- Sample re-generation infrastructure (BadBlood, exGOAD) — please contribute upstream to those projects.

## Issue triage

When filing an issue, please:

1. **Search existing issues first** to avoid duplicates.
2. **Include the sample category and OS version** ("WS2025 16 KiB DataStore.edb Locked", "WS2019 4 KiB SRUDB.dat", etc.).
3. **Cite specific commits or files** where relevant.
4. **For reproduction-failure reports**, include:
   - The output of `reproduction/verify_pagesize.ps1` and `reproduction/parse_all.ps1` on your host.
   - The SHA-256 of `poneglyph/poneglyph.exe` (compare to `MANIFEST.md`).
   - The Windows version and PowerShell version.

For security-sensitive findings (e.g., new parser failure modes in production tools), please **email the corresponding author directly** (`takker0708@gmail.com`) rather than opening a public issue. We will coordinate responsible disclosure as documented in `ETHICAL_USE.md`.

## Pull-request mechanics

1. Fork the repository and create a topic branch named `<your-handle>/<short-description>`.
2. Make focused commits with conventional-commit-style messages (`fix:`, `feat:`, `docs:`, `test:`, etc.).
3. **For new patches**, place them in `patches/` with a filename that lexicographically sorts to the correct application order. Update `patches/README.md` with the new patch description.
4. **For reproduction-script changes**, update `reproduction/expected_outputs.txt` if the output format changes.
5. **For documentation changes**, run a markdown linter if you have one handy; otherwise we'll fix nits in review.
6. Open the pull request against `main` with a clear title and description. Reference any related issue.

We aim to review PRs within one week. PRs that include reproduction evidence on the affected samples are reviewed faster than ones that ask the maintainers to verify on their own samples.

## Citation responsibility

If you publish work that depends on these patches or this dataset, please cite both the paper and the dataset, per `CITATION.cff`. We will gladly add a "Used by" section to the README listing downstream publications and tools — please drop a link in an issue.

## Code of conduct

Be kind. Disagreements about technical content are expected and welcomed; disagreements about people are not. The maintainers reserve the right to remove comments and contributions that violate basic norms of academic-community engagement.

## Licensing of contributions

By submitting a pull request you agree that your contribution will be licensed under the same terms as the corresponding component in this repository:

- Contributions to `patches/` → LGPL-3.0-or-later.
- Contributions to documentation, scripts, and metadata → CC-BY-4.0.

See `LICENSE.md` for the per-component breakdown.

## Maintainers

- **Takayuki Hirose** (`takker0708@gmail.com`, corresponding author)
- **Hiroshi Koide** (Kyushu University)

For questions about scope, scheduling, or whether a specific contribution would be welcomed, please open a Discussion or contact the corresponding author directly.
