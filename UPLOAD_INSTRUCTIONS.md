# Zenodo Upload Instructions

This document walks through the steps to take this staging area to a published Zenodo record with a citable DOI.

**Estimated time**: 30 minutes (after `package.ps1` runs).

---

## Step 0 — Sandbox first (recommended)

Zenodo offers a sandbox at https://sandbox.zenodo.org that is fully separate from production. Test the upload there first to verify metadata, descriptions, and file inventory before committing to production (which assigns a permanent DOI on publish).

Sandbox account is separate from production; you'll need to create one if you don't already have it.

---

## Step 1 — Stage and hash

```powershell
cd C:\dev\aapf-validation
.\tools\package.ps1
```

This will:
- Copy patches from `C:\dev\libesedb-sys-patched\patches\` to `patches/`
- Copy `poneglyph.exe` from `C:\dev\Poneglyph\target\release\` to `poneglyph/`
- Copy all AAPF samples from `C:\dev\aapf-samples\<category>\` to `samples/`
- Copy `_validation/poneglyph-info-*.txt` outputs to `samples/_validation/`
- Regenerate `MANIFEST.md` with SHA-256 hashes for every file
- (Optional with `-Zip`) Create a single `aapf-validation-1.0.0.zip` for off-Zenodo backup

Expected result: about 730 MB total in `samples/` plus ~10 MB of patches, binaries, and docs.

---

## Step 2 — Pre-upload checklist

Replace all `XXXXXXX` / `TODO` placeholders before publishing:

- [ ] **`CITATION.cff`**: ORCID iDs, Zenodo DOI (after step 5), paper DOI (after acceptance)
- [ ] **`.zenodo.json`**: same as above; verify `related_identifiers` URLs are reachable
- [ ] **`docs/BADBLOOD_PROVENANCE.md`**: pin BadBlood / PSWindowsUpdate / Playwright / Atomic Red Team commit hashes and versions
- [ ] **`docs/PAPER.md`**: paper DOI placeholder, preprint URL (if any)
- [ ] **`README.md`**: DOI badge URL after publish
- [ ] **`CHANGELOG.md`**: confirm the release date and v1.0.0 entry

Spot-check three random files against `MANIFEST.md` SHA-256:

```powershell
Get-FileHash -Algorithm SHA256 .\poneglyph\poneglyph.exe
Get-FileHash -Algorithm SHA256 .\patches\fix-ws2025-itag-state.patch
Get-FileHash -Algorithm SHA256 .\samples\identity\2025\clean\ntds.dit
```

Compare against the values in `MANIFEST.md`. If any differ, re-run `package.ps1` (this should not happen but it's a fast verification).

---

## Step 3 — Create the Zenodo upload

1. Sign in at https://sandbox.zenodo.org (for testing) or https://zenodo.org (for production).
2. Click **New Upload**.
3. **Upload Type**: Dataset
4. **Files**: Drag and drop the contents of `C:\dev\aapf-validation\` excluding `tools/` and `UPLOAD_INSTRUCTIONS.md`.
   - You can drag the individual subdirectories (`patches/`, `poneglyph/`, `samples/`, `reproduction/`, `docs/`) and the top-level `.md` / `.cff` / `.json` files.
   - Zenodo flattens directory structure for download but preserves it in the displayed file list when you drag full folders.
   - Large samples may take 10–30 minutes to upload depending on your connection.

---

## Step 4 — Fill the Zenodo metadata form

The web form will ask for fields that match `.zenodo.json`. Fill them as follows (or use the API in Step 5 to skip this UI):

| Field | Value |
|---|---|
| Title | AAPF Validation Dataset: Cross-Page-Size ESE Format Changes in Windows Server 2025 |
| Publication date | 2026-06-14 |
| Resource type | Dataset |
| Creators | Hirose, Takayuki (Independent Researcher) |
| Description | Copy from `README.md` opening paragraphs |
| Keywords | digital forensics; Windows Server 2025; Extensible Storage Engine; ESE; NTDS.dit; DataStore.edb; SRUDB.dat; WebCacheV01.dat; libesedb; tool validation; cross-page-size format change; itagState; ISO/IEC 27042; AAPF |
| License | Creative Commons Attribution 4.0 International (CC-BY-4.0) |
| Access right | Open Access |
| Related identifiers | Add the libesedb #78 URL (`documents`), dissect.esedb PR #46 URL (`isDerivedFrom`), and Velociraptor #4606 URL (`documents`) |
| Communities | Optional: search for and join `dfrws` |

---

## Step 5 — Optional: upload via the Zenodo REST API

If you prefer to skip the web UI and upload via API (useful for re-uploads), the metadata in `.zenodo.json` is in the format Zenodo expects. Here is a minimal upload sequence:

```bash
ACCESS_TOKEN="<your token from https://zenodo.org/account/settings/applications/tokens/new/>"
ZENODO_URL="https://zenodo.org"   # or https://sandbox.zenodo.org

# 1. Create a new deposit
curl -i -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -X POST "$ZENODO_URL/api/deposit/depositions" \
     -d '{}'

# Response includes "id" (deposit ID) and "links.bucket" (upload URL)
# 2. Upload metadata
curl -i -H "Authorization: Bearer $ACCESS_TOKEN" \
     -H "Content-Type: application/json" \
     -X PUT "$ZENODO_URL/api/deposit/depositions/<DEPOSIT_ID>" \
     -d @.zenodo.json

# 3. Upload each file to the bucket
for f in $(find . -type f -not -path './tools/*' -not -name 'UPLOAD_INSTRUCTIONS.md'); do
  curl -i -H "Authorization: Bearer $ACCESS_TOKEN" \
       -X PUT "<BUCKET_URL>/$f" \
       --upload-file "$f"
done

# 4. Publish (assigns DOI)
curl -i -H "Authorization: Bearer $ACCESS_TOKEN" \
     -X POST "$ZENODO_URL/api/deposit/depositions/<DEPOSIT_ID>/actions/publish"
```

The response from publishing includes the assigned DOI under `doi`.

---

## Step 6 — Update the paper

Once you have the production Zenodo DOI:

1. Edit `main.tex` and replace the placeholder DOI in `\section{Availability}` (added separately in this revision; see `paper-ese-32k/main.tex`).
2. Edit `references.bib` to add a new `@misc{aapf-validation, ...}` entry pointing to the DOI.
3. Recompile `main.pdf`.

Approximate placeholder text in main.tex (will be added in the next step):

```latex
\section*{Availability}
The patches described in this paper are available at:\\
\url{https://github.com/libyal/libesedb/issues/78}\\
The full validation dataset (patches, Poneglyph binary, 14 ESE samples across three snapshot states, and reproduction scripts) is deposited at Zenodo:\\
\url{https://doi.org/10.5281/zenodo.XXXXXXX}\\
A pre-built reproducibility binary and ``expected outputs'' file are included; reviewers can verify Table~\ref{tab:aapf-matrix} in approximately five minutes on a modern Windows host.
```

---

## Step 7 — Post-publish

After publish:

- The DOI is permanent and citable. Update CITATION.cff, .zenodo.json, README.md, and docs/PAPER.md with the actual DOI and commit those changes to any source repository.
- If you publish a v1.1 (with the WS2025 Activity samples once obtained, or with the Resource × Locked samples), Zenodo assigns a new DOI in the same DOI series so both versions remain citable.
- Add a Zenodo DOI badge to any related GitHub repository:
  ```markdown
  [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.XXXXXXX.svg)](https://doi.org/10.5281/zenodo.XXXXXXX)
  ```

---

## Troubleshooting

**Q. The samples upload fails part-way through.**
A. Zenodo's bucket upload supports resume. Re-run the upload step; already-uploaded files are skipped.

**Q. I want to delete the record after upload.**
A. Pre-publish: you can delete the draft from your Zenodo deposit list. Post-publish: DOIs are permanent and Zenodo does not delete records; you can retract the record with an admin request, but the DOI remains as a tombstone.

**Q. I made an error in the metadata.**
A. Pre-publish: edit and re-submit. Post-publish: create a new version (Zenodo's "New version" button), edit, and publish. The new DOI is in the same conceptual series.

**Q. The Zenodo file picker doesn't accept directory uploads.**
A. Zenodo accepts file uploads via drag-drop or file picker. If you uploaded as a flat list, the directory structure is reconstructed when reviewers download the record. Alternatively use the API path described in Step 5.

**Q. Should I upload a .zip instead of individual files?**
A. Zenodo's recommendation is to upload files directly (so the file list is browsable in the web UI). A `.zip` is useful as an additional backup and convenience but is not the primary upload format. The `tools/package.ps1 -Zip` option produces one if you want it.
