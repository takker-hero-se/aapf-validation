# GitHub repository setup — step-by-step

This document walks through the one-time setup of the GitHub repository that mirrors this directory and links it to the Zenodo record via the GitHub-Zenodo integration.

**Estimated time**: 30 minutes.

---

## Architecture (target end state)

```
┌──────────────────────────────────────────────────────────────┐
│ GitHub: takker-hero-se/aapf-validation       (public, LGPL-3.0)│
│   ├── patches/         (6 .patch + README.md)                  │
│   ├── poneglyph/       (README.md, BUILD.md; no binary)        │
│   ├── reproduction/    (2 .ps1 + REPRODUCE.md + expected.txt)  │
│   ├── docs/            (BADBLOOD_PROVENANCE, PAPER.md)         │
│   ├── tools/           (package.ps1)                           │
│   ├── samples/         (.gitkeep with Zenodo DOI link only)    │
│   ├── README.md, ETHICAL_USE.md, CITATION.cff, LICENSE.md, …   │
│   └── ~5 MB total                                              │
└──────────────────────────────────────────────────────────────┘
                       ↕  GitHub-Zenodo integration
┌──────────────────────────────────────────────────────────────┐
│ Zenodo: 10.5281/zenodo.XXXXXXX     (CC-BY-4.0 / CC0 / LGPL-3.0)│
│   ├── GitHub auto-archived zip (on every Release)              │
│   ├── poneglyph/poneglyph.exe   (manually added, ~7 MB)        │
│   ├── samples/                  (manually added, ~730 MB)      │
│   └── ~733 MB total                                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Step 1 — Create the GitHub repository (5 min)

1. Sign in to GitHub as `takker-hero-se` (or the corresponding author's chosen account).
2. **New repository**:
   - Name: **`aapf-validation`** (recommended) or `ws2025-ese-validation` / `ese-32k-aapf`.
   - Description: "AAPF validation patches, scripts, and documentation for Cross-Page-Size ESE Format Changes in Windows Server 2025."
   - Visibility: **Public**.
   - License preset: **None** (this directory already contains `LICENSE.md` with the per-component breakdown).
   - Do NOT initialize with README/license/.gitignore. The directory already has all of those.
3. Click **Create repository** and note the clone URL.

---

## Step 2 — Initialize and push from this directory (10 min)

Open PowerShell in `C:\dev\aapf-validation\` and run:

```powershell
cd C:\dev\aapf-validation

# Sanity check — make sure samples/ is ignored
git init
git status

# Verify that samples/ is not staged (it should appear in the ignore list)
git check-ignore -v samples/identity/2025/clean/ntds.dit
# Expected: a line like  .gitignore:5:samples/    samples/identity/2025/clean/ntds.dit

# Add everything except ignored files
git add .

# Spot-check the staged set should be small (no samples, no .exe)
git status --short | Measure-Object | Select-Object -ExpandProperty Count
# Expected: 18-20 files

# First commit
git commit -m "Initial commit: AAPF validation patches, scripts, and documentation

Companion artifacts for 'Silent Evidence Loss in Windows Server 2025:
Cross-Page-Size ESE Format Changes and Their Forensic Integrity Implications'
(FSI:DI 2026).

Patches:
- fix-ws2025-itag-state.patch: universal & 0x0FFF mask on itagState
- zzz-fix-ws2025-btree.patch: IS_LEAF page-flag check in B-tree walks
- 4 quality-of-life build-system patches

Documentation:
- README.md, ETHICAL_USE.md, LICENSE.md, CITATION.cff
- patches/README.md, poneglyph/README.md + BUILD.md
- reproduction/REPRODUCE.md + verify_pagesize.ps1 + parse_all.ps1
- docs/BADBLOOD_PROVENANCE.md, docs/PAPER.md

Not in this commit (distributed via Zenodo only):
- 14 ESE database samples (730 MB across 4 categories)
- poneglyph/poneglyph.exe (rebuild via poneglyph/BUILD.md)"

# Add the remote and push
git branch -M main
git remote add origin https://github.com/takker-hero-se/aapf-validation.git
git push -u origin main
```

---

## Step 3 — Enable the GitHub-Zenodo integration (5 min)

1. Sign in to **Zenodo** (https://zenodo.org) — production, not sandbox.
2. Top-right user menu → **Settings** → **Linked accounts**.
3. Connect GitHub. Authorize Zenodo to read your repositories.
4. Top-right user menu → **GitHub** (now visible).
5. Find `takker-hero-se/aapf-validation` in the list, toggle the switch to **ON**.

This tells Zenodo: "Watch this repo; when a release is created, archive it and assign a DOI."

---

## Step 4 — Create the first GitHub Release (5 min)

On GitHub:

1. Navigate to https://github.com/takker-hero-se/aapf-validation/releases/new
2. **Tag**: `v1.0.0`
3. **Release title**: `v1.0.0 — Initial release accompanying FSI:DI submission`
4. **Description**:
   ```markdown
   First public release of the AAPF Validation Dataset, accompanying the paper
   *Silent Evidence Loss in Windows Server 2025: Cross-Page-Size ESE Format Changes
   and Their Forensic Integrity Implications* (Forensic Science International:
   Digital Investigation, 2026).

   ## Highlights
   - **Universal `& 0x0FFF` patch** for libesedb resolving WS2025 itagState
     reinterpretation failures across 4 KiB / 16 KiB / 32 KiB pages
     (`patches/fix-ws2025-itag-state.patch`).
   - **B-tree `IS_LEAF` validation** for the secondary zeroed-page failure
     in 32 KiB NTDS.dit (`patches/zzz-fix-ws2025-btree.patch`).
   - **Reproduction scripts** (`reproduction/verify_pagesize.ps1`,
     `reproduction/parse_all.ps1`) with pre-computed expected outputs.

   ## Full archive (including samples and Poneglyph binary)
   The full ~730 MB AAPF validation archive is deposited at Zenodo:
   https://doi.org/10.5281/zenodo.XXXXXXX

   ## Citation
   See `CITATION.cff` for the recommended dataset citation.
   ```
5. Click **Publish release**.

Zenodo will automatically detect the release within 1–2 minutes, archive the zip, and assign a DOI.

---

## Step 5 — Add Poneglyph binary and samples to the Zenodo record (~30 min)

The GitHub-Zenodo integration archives only what's in the Git repo. The samples and the prebuilt binary still need to be uploaded directly to Zenodo:

1. Wait for Zenodo to finish the auto-archive (the new record appears in your Zenodo "Uploads" with status **Done**).
2. Click into the record → **Edit** (top-right).
3. Drag and drop:
   - `C:\dev\aapf-validation\poneglyph\poneglyph.exe`
   - `C:\dev\aapf-validation\samples\` (entire directory; ~730 MB)
4. Confirm metadata (it should match the auto-detected GitHub repo metadata; adjust as needed).
5. **Save** → **Publish**.

The DOI is now assigned and permanent.

---

## Step 6 — Replace DOI placeholders (5 min)

After publish, Zenodo shows the assigned DOI (e.g., `10.5281/zenodo.12345678`).

On your local workspace (the *paper*, not this repo):

```powershell
$doi = "10.5281/zenodo.12345678"  # ← replace with your actual DOI
cd "C:\Users\takke\OneDrive\ドキュメント\workspace\docs\paper-ese-32k"
(Get-Content main.tex)       -replace '10.5281/zenodo.XXXXXXX', $doi | Set-Content main.tex
(Get-Content references.bib) -replace '10.5281/zenodo.XXXXXXX', $doi | Set-Content references.bib
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```

On this GitHub repo:

```powershell
cd C:\dev\aapf-validation
# Replace DOI placeholders in all GitHub-tracked text files
Get-ChildItem -Recurse -File -Include *.md, *.cff, *.json |
    Where-Object { (git check-ignore $_.FullName 2>$null) -eq $null } |
    ForEach-Object {
        (Get-Content $_.FullName) -replace '10\.5281/zenodo\.XXXXXXX', $doi |
            Set-Content $_.FullName
    }

git add .
git commit -m "docs: replace Zenodo DOI placeholders with assigned DOI ($doi)"
git push
```

---

## Step 7 — Optional: Add Zenodo DOI badge to other repositories

If you have related GitHub repos (Poneglyph, exGOAD, etc.), add a "related dataset" badge to their READMEs:

```markdown
**Related dataset**: AAPF Validation [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
```

---

## Troubleshooting

### "Zenodo doesn't see my repo in the GitHub list"

- Make sure the repo is **public**. Private repos are honoured but the toggle only appears after the visibility settles.
- Reload the Zenodo GitHub page after a minute.
- The webhook is added on the first repo toggle-on; this may briefly redirect you through GitHub OAuth again.

### "samples/ got staged by mistake"

Inspect `.gitignore`:

```powershell
Get-Content .gitignore
git check-ignore -v samples/identity/2025/clean/ntds.dit
```

The first ignore line should be `samples/`. If you accidentally staged something:

```powershell
git rm -r --cached samples/
git commit -m "Untrack samples/ (Zenodo-only)"
```

### "GitHub Release is huge"

If the auto-archive exceeds 100 MB, GitHub refuses to host it. This shouldn't happen with our `.gitignore` (target is ~5 MB), but if it does, the cause is usually a stray binary or a forgotten samples directory. Inspect with:

```powershell
git ls-files | ForEach-Object {
    [PSCustomObject]@{ Path = $_; SizeKB = [Math]::Round((Get-Item $_).Length / 1KB, 1) }
} | Sort-Object SizeKB -Descending | Select-Object -First 10
```

---

## What this setup achieves

| Goal | Mechanism |
|---|---|
| Citable software | Zenodo concept DOI (always-latest) + version DOI (per release) |
| Reproducible code | Git-tracked patches and scripts in `takker-hero-se/aapf-validation` |
| Community contribution | GitHub Issues, Pull Requests, Discussions |
| Permanent archive of samples | Zenodo manual upload (730 MB) |
| Reviewer convenience | Single-DOI citation in `main.tex` `\section{Availability}` |
| Long-term preservation | CERN-backed Zenodo + GitHub Archive Program (Arctic Code Vault) |
