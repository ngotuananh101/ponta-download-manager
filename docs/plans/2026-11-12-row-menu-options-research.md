# Research: row context-menu options (IDM reference) — 2026-11-12

## Status: RESEARCH DONE 2026-11-12, awaiting scope decision

## Source

Tuấn Anh sent a screenshot of IDM's per-row context menu
(`image-29.png`) and asked to research its options for PDM. 15
items, in menu order. "Set priority" is greyed out in the screenshot
(IDM disables it for rows where priority does not apply, e.g.
completed downloads).

Current PDM row menu (`⋮`): Pause / Resume / Retry / Cancel by state,
plus Delete (which now opens the delete dialog from
`2026-11-12-delete-dialog-missing-status.md`).

## Per-item findings

| # | Option | What it does (IDM) | PDM today | Work | Effort |
|---|--------|-------------------|-----------|------|--------|
| 1 | Open | Open the file with the default app | Nothing: no launcher package, no `xdg-open` call anywhere in `apps/desktop/lib` | `Process.run('xdg-open', [path])` on Linux / `start` on Windows, following the existing `DiskSpaceService` shell-out pattern; only for completed rows with the file present, snackbar when missing | S |
| 2 | Show in folder | Open the file manager at the file | Nothing (same as above) | Linux: `xdg-open <dir>` (selecting the file inside is file-manager-dependent, best-effort); Windows: `explorer /select,<file>` | S |
| 3 | Set priority | High / Normal / Low submenu | Engine `PdmEngine.setPriority` + IPC `download.setPriority` already exist; the UI only *displays* priority (details panel, `priorityLabel`) — there is no setter in the desktop chain | Submenu + plumb datasource/repository/actions; applies to queued/downloading/paused only, not completed | S |
| 4 | Rename file | Rename the finished file | No API (only internal sink renames + the conflict policy) | New engine method: rename on disk + update the record's `fileName` (destination is derived); target-exists conflict needs a rule; completed rows only | M |
| 5 | Move to... | Move the file to another folder | No API | New engine method: move on disk + update the record's `directory`; folder picker via `file_picker` (already a dependency); conflict handling as in Rename | M |
| 6 | Delete file | Delete only the file, keep the row (the row then shows as missing) | No such action: our Delete removes the row, the dialog asks about the file | New engine method: delete the finished file, keep the record; the UI re-maps the row to Missing (uses the M1 mapping) | S-M |
| 7 | Remove from list | Remove the row, keep the file | Exactly our Delete dialog's keep-file choice (`deleteFile: false`) | None if the dialog stays; as a separate item it would be delete-record-keep-file with no dialog | S or skip (see decision 1) |
| 8 | Add mirror | Add alternative URLs for the same file, fallback when the main link fails | Zero infrastructure: no mirror concept anywhere (`DownloadRecord` has a single `url`) | Multi-URL storage (DB migration), fallback in scheduler/transport, UI to add/list mirrors | L — defer |
| 9 | Copy link | Copy the download URL | Trivial: `Clipboard.setData` (`Clipboard.getData` is already used for the Add-dialog prefill) | One menu item, no engine work | XS |
| 10 | Check for update | Re-check the server for a newer version of the file | Probe exists (`transport.probe` → `ResourceInfo`: size, eTag, lastModified); the record stores `eTag` | Probe the URL, compare size/eTag with the stored record + on-disk file; report "up to date" or offer re-download (retry with fresh validators) | M |
| 11 | Export selected downloads | Export the selection to a file | Nothing in `apps/desktop/lib` | Write the selected rows to a file via a save dialog; format is an open decision (plain-text URLs is simplest; JSON with metadata is more useful) | S-M |
| 12 | File integrity | Verify the downloaded file | The `download_integrity` package is an **unimplemented stub** (its barrel file is a TODO pointing at architecture §14/§21); the design has `IntegrityVerifier` (validate final size + available checksums) | Implement the package: hash the file, compare size; a server checksum is rarely available, so v1 is size + a shown SHA-256 | M |
| 13 | Change URL | Replace the download's URL (e.g. expired link) and retry with it | No API; record update via `upsertDownload` exists internally | New engine method: update the record's URL (+ reset validators); dialog to input the new URL; failed/paused rows only | M |
| 14 | Perform virus check | Scan the file with the installed antivirus | Nothing; no AV dependency | Shell out to a local scanner (ClamAV `clamscan` on Linux if installed; Windows Defender `MpCmdRun` on Windows); report clean/infected/no-scanner-found; nothing is uploaded anywhere | M |
| 15 | Add tag | Tags/categories for downloads | No tag system at all: no field in `DownloadRecord`/`Download`, no DB column, no filter | DB migration + tag storage + assign UI + tag filter; belongs with Categories (M3) | L — defer |

## Proposed order

- **Batch 1 — quick wins:** Copy link, Open, Show in folder, Set
  priority, Delete file. No new engine API except the small
  delete-file method; everything else is UI + existing engine calls
  or `Process.run`.
- **Batch 2 — new engine methods:** Rename file, Move to...,
  Change URL, Check for update, Export selected downloads.
- **Batch 3 — decide later:** File integrity (implement the stub
  package), Perform virus check (needs a scanner installed),
  Add mirror, Add tag (both large; Tag belongs with M3 Categories).

## Decisions needed from Tuấn Anh

1. **Remove from list:** keep the delete dialog we just built and
   skip this item (the dialog's keep-file choice already does it),
   or split Delete into two menu items — Delete file (file only)
   and Remove from list (row only) — and drop the dialog?
   Recommendation: keep the dialog; the dialog is the only place
   bulk delete asks once for the whole selection.
2. **Where to start:** Batch 1 as a whole, or pick individual
   items?
3. **Export format** (if Batch 2): plain-text URLs, or JSON with
   metadata (file name, size, status)?
4. **Virus check** (if Batch 3): go with the local-scanner
   approach (ClamAV on Linux / Defender on Windows), or skip it?
