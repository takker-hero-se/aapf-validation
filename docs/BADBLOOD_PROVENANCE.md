# BadBlood and Companion Tool Provenance

This document records the exact versions, configurations, and execution parameters used to generate the samples in this Zenodo record. It is the reproducibility companion to `ETHICAL_USE.md`.

## Sample regeneration overview

The samples in `samples/` were captured from labs deployed via [exGOAD](https://github.com/takker-hero-se/exGOAD) on Microsoft Azure. The lab definitions used were:

| Lab name | OS | Population tool | Sample category |
|---|---|---|---|
| `BadBlood` | Windows Server 2019 Datacenter | BadBlood | Identity |
| `BadBlood2025` | Windows Server 2025 Datacenter | BadBlood + 32K Pages feature | Identity |
| `PSWindowsUpdate` / `PSWindowsUpdate2025` | WS2019 / WS2025 | PSWindowsUpdate iterations | Health |
| `Playwright` | WS2019 | Playwright automated browsing | Activity |
| `AtomicRedTeam` / `AtomicRedTeam2025` | WS2019 / WS2025 | Atomic Red Team Discovery tests | Resource |

The full lab definitions, including Terraform-provider configs and Ansible playbooks, are available in the exGOAD repository.

## Identity (NTDS.dit + SYSTEM)

### Population

- **BadBlood**: https://github.com/davidprowe/BadBlood
- **Commit**: TODO: pin commit hash before Zenodo upload (suggested: `git rev-parse HEAD` in the repository at the time of capture)
- **Default parameters**: `Invoke-BadBlood.ps1` with no per-flag overrides
- **Approximate population scale**: 1,700–1,711 MSysObjects records; 7,000–7,024 datatable records; 13,688–13,936 link_table records (link counts vary by ACL randomization)

### WS2025 32 KiB conversion

The WS2025 DC's 32 KiB feature was enabled in-place after BadBlood population using:

```powershell
Enable-ADOptionalFeature -Identity "Database 32k pages" `
    -Scope ForestOrConfigurationSet -Target <forest FQDN>
Restart-Computer -Force
```

This conversion is irreversible. The resulting `cbDbPage = 32768` is verified via `esentutl /mh samples/identity/2025/clean/ntds.dit`.

### Acquisition (three states per OS)

- **Clean**: `Stop-Service NTDS` (graceful), copy `ntds.dit` + `edb.chk` + `edb.log`, `Start-Service NTDS`. The graceful Stop-Service performs a clean shutdown; `esentutl /mh` reports "Clean Shutdown".
- **Crashed**: `Stop-Service NTDS -Force`, copy immediately. **Note**: NTDS responds to `-Force` by still completing a clean shutdown sequence; the resulting database is bit-identical to a Clean acquisition. This is documented in the paper as a control experiment for Section 5.5.2 (the B-tree zeroed-page failure is observed even under provably-clean shutdown, rebutting the R2-W3 hypothesis that the failure is a dirty-shutdown artifact).
- **Locked**: VSS snapshot of the live DC's volume, then copy the snapshot's `ntds.dit`. `esentutl /mh` reports "Dirty Shutdown".

The SYSTEM hive (required for credential extraction tests) is acquired alongside `ntds.dit` from the same snapshot.

## Health (DataStore.edb)

### Population

- **PSWindowsUpdate**: https://www.powershellgallery.com/packages/PSWindowsUpdate
- **Version**: TODO: pin from `Get-Module -ListAvailable PSWindowsUpdate`
- **Population script**: `for ($i=0; $i -lt 20; $i++) { Get-WindowsUpdate; Start-Sleep -Seconds 30 }`. Iterations populate scan history without applying updates; this avoids unwanted patches changing the OS during capture.

### Acquisition

Same Clean / Crashed / Locked semantics, but the Stop-Service is performed against `wuauserv` and `usosvc`. As noted in MANIFEST, WU services clean-detach the database during graceful stop; Locked is the only meaningfully Dirty state.

## Activity (WebCacheV01.dat)

### Population

- **Playwright**: https://playwright.dev/
- **Browser**: Microsoft Edge Chromium channel
- **Population script**: Iterates a fixed list of 30+ public URLs (Microsoft Learn, GitHub, Wikipedia, etc.) across multiple sessions to populate `WebCacheV01.dat` with history entries, cookies, and DOM cache fragments.

### Acquisition

WebCacheV01.dat cannot be cleanly stopped while the running browser holds it open; the database is therefore always in Dirty state on the running OS. Clean / Crashed / Locked are best-effort distinctions:

- **Clean**: close all Edge sessions, then copy. `esentutl /mh` still reports Dirty because the WebCache subsystem holds the database for the user profile.
- **Crashed**: kill Edge processes immediately, copy.
- **Locked**: VSS snapshot, copy from snapshot.

### WS2025 unobtainable

Microsoft Edge runs under user profiles; on a Server Core or headless WS2025 DC the WebCache subsystem does not initialize even when Edge is invoked headless. WS2025 Activity samples are therefore omitted from this dataset. Client-OS replication (Win11 24H2 with Edge populated) is reserved for future work; see `ETHICAL_USE.md`.

## Resource (SRUDB.dat)

### Population

- **Atomic Red Team**: https://github.com/redcanaryco/atomic-red-team
- **Tests executed**: T1082 (System Information Discovery), T1016 (System Network Configuration Discovery), T1033 (System Owner/User Discovery), T1057 (Process Discovery), T1018 (Remote System Discovery), T1087 (Account Discovery). All chosen for low side-effects and clearly Discovery-tactic categorization.
- **Population schedule**: scheduled task running the tests every 30 minutes for 24 hours.
- **No Persistence, Defense Evasion, or Credential Access tests were executed.**

### Acquisition

- **Clean**: `Stop-Service DPS` (Diagnostic Policy Service), copy.
- **Partial**: scheduled-task-interrupted capture; included as a comparison point.
- **Locked** (not included for SRUDB in this release): VSS-based capture is straightforward but the database content is sensitive to acquisition timing; we omit it from this dataset pending more rigorous reproducibility characterization.

## File-system layout convention

For each (category, OS, state) triple, the leaf directory contains:

- The primary ESE database file (`ntds.dit`, `DataStore.edb`, `WebCacheV01.dat`, or `SRUDB.dat`)
- The corresponding transaction log (`edb.log`, `V01.log`, `SRU*.log`, etc.)
- The checkpoint file (`edb.chk`, `V01.chk`)
- Any reserved log files (`edbres0000*.jrs`, `V01res0000*.jrs`)
- For Identity, additionally the `SYSTEM` registry hive

The exact file inventory per leaf directory is documented in `../MANIFEST.md`.

## Why these samples and not others?

The four categories were chosen to systematically probe Microsoft's use of ESE across the WS2025 ecosystem:

- **Identity (NTDS.dit)** is the highest-stakes forensic artifact and the most-cited prior parser-failure case.
- **Health (DataStore.edb)** at 16 KiB page size revealed the first cross-page-size failure (Issue 3 of the paper).
- **Activity (WebCacheV01.dat)** at 32 KiB demonstrates that 32 KiB is not WS2025-specific (WS2019 already used 32 KiB for this artifact).
- **Resource (SRUDB.dat)** at 4 KiB revealed the second cross-page-size failure (Issue 4) and confirms the OS-version-level (not page-size-induced) nature of the format change.

Other ESE databases (Windows Search `Windows.edb`, Internet Explorer 8–10 `WebCacheV01.dat` legacy formats, Exchange `priv.edb` / `pub.edb`) are out of scope but candidate targets for follow-up AAPF-style validation work.

## TODOs before Zenodo upload

- Pin BadBlood commit hash.
- Pin PSWindowsUpdate version.
- Pin Playwright version and browser channel build number.
- Pin Atomic Red Team commit hash.
- Record Azure VM image SKU (e.g., `MicrosoftWindowsServer:WindowsServer:2019-Datacenter:17763.<patch>.<date>`).
