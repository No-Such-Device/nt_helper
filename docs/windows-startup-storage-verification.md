# Windows startup storage verification

Verified on 2026-09-07 using the `nt-helper-windows-x64` VM.

## Failure and correction

The second Windows report failed while creating `Documents/nt_helper/.migrated`.
v2.51.0 handled Documents lookup and directory-creation failures, but marker
creation happened outside that fallback handler. A directory can exist while
Windows rejects creation of files inside it.

The correction also falls back on marker-creation filesystem errors when the
Documents app directory contains neither the database nor gallery cache. If
migration has already moved data there, the error remains visible rather than
opening an empty fallback and hiding that data. Migration failures and failure
to initialize the fallback itself also remain visible.

## Evidence

- A Dart regression reproduces the reporter's `PathNotFoundException`, error 2,
  at the exact marker-creation call. It fails on v2.51.0 and passes with the fix.
- The native v2.51.0 Windows binary fails at the same call when its redirected
  Documents app directory exists but an ACL denies `CreateFiles`. Windows
  reports `PathAccessException`, error 5, in this fixture.
- The corrected Windows release build renders its first frame and creates a
  non-empty SQLite database plus `.migrated` under Application Support.
- After removing the ACL restriction, a second app launch renders its first
  frame and keeps the same fallback database; no Documents store is created.
- All 23 directory tests pass on Windows. Local analysis is clean and all
  3,666 Flutter tests pass.

This reproduces the failing filesystem boundary, not the reporter's OneDrive
configuration. OneDrive redirection or availability remains a possible cause;
the VM test does not establish that OneDrive itself caused the error.

## Repeat the native test

Use a Windows test VM with nt_helper closed:

```powershell
.\scripts\windows-startup-storage-smoke.ps1 -ExecutablePath C:\app\nt_helper.exe
```

For the old binary, add `-ExpectedOutcome marker-failure`. The script redirects
only the test user's Documents and Roaming AppData into fresh directories,
denies file creation in the test Documents app folder, and restores the registry
values and ACL in `finally`. It leaves logs and the registry backup under
`%LOCALAPPDATA%\nt-helper-marker-repro-*`. Do not run it against an everyday
user profile or interrupt it while the folder redirection is active.

The GitHub runner checkout is not changed. The fixed test build and generated
files were created separately under the VM user's
`AppData\Local\nt-helper-marker-fixed` directory. The app processes started by
the smoke test were stopped afterward; the runner service remained running.

## Exact errno 2 reproduced with Controlled Folder Access

The follow-up investigation on 2026-09-07 reproduced the screenshot's exact
`PathNotFoundException: Cannot create file ... .migrated ... errno = 2` using
**Microsoft Defender Controlled Folder Access (CFA)**. No ACL denial, missing
folder, IO override, or OneDrive sync was involved in this experiment. The VM's
OneDrive displayed its sign-in screen; each fixture was an ordinary local
folder with `Directory` attributes, outside a configured OneDrive sync root.

The test used the downloaded public Windows packages, not a rebuilt approximation:

| Package | ZIP SHA-256 |
| --- | --- |
| v2.51.0 / 2.51.0+332 | `fc8670502a99289089d89d5946a787afbc89b45f4dc120bf23aab03e043e771f` |
| v2.51.1 / 2.51.1+333 | `977c8df1c334cfe0c7b87801d55f2f456970501dbd108a947db603f69e76e6e8` |

Each case started with a fresh empty Documents app directory and application
support directory. Defender real-time protection remained enabled throughout.

| Binary / policy | Actual result |
| --- | --- |
| v2.51.0, CFA off | First frame rendered; database created in Documents. |
| v2.51.0, CFA on, test Documents protected | Exact `.migrated` / `PathNotFoundException` / errno 2; no first frame; Defender event 1123 names the executable and protected folder. |
| v2.51.0, CFA still on, only old executable explicitly allowed | First frame rendered; database created in Documents. |
| v2.51.1, CFA on, no explicit app allowance | First frame rendered; Defender event 1123 still records the blocked Documents access; one 3,203,072-byte database created in Application Support. |
| v2.51.1, second fresh protected fixture | Same successful fallback and Defender block event. |

This establishes CFA as a sufficient cause of the **exact** reported failure,
and verifies that the published v2.51.1 handles that cause for a fresh store
without disabling protection or allowing the application through CFA. It does
**not** establish that the reporter has CFA enabled: confirmation on that PC is
still pending. Existing-data migration and arbitrary security products are not
covered by this experiment. The original ACL test above separately verifies
retaining fallback storage after Documents becomes writable.

### Reproduction and retained evidence

Run `scripts/windows-startup-cfa-smoke.ps1` elevated in the test VM, with extracted
old and fixed public packages supplied as `-OldExecutable` and `-FixedExecutable`.
The app processes inherit the test's elevated token; this experiment specifically
shows that elevation alone does not bypass CFA. The test changes no ACLs and
restores the original known-folder registry entries and Defender settings in
`finally`. It refuses a VM where CFA is already enabled or either executable is
explicitly allowed. Do not run it in an everyday user profile.

The successful investigation run retained its startup logs, Defender XML events,
per-case result JSON, and original/restored configuration in the VM at:

```text
C:\Users\runner\AppData\Local\nt-helper-cfa-causal-989694ebba534a4b941b7bbf28c7eeee
```

The first exact failure was independently reproduced in the preceding run
`nt-helper-cfa-causal-33dfd332592d42fc9072baa15d6a3467`. Its assertion initially
missed the asynchronously published Defender event; event 1123 arrived several
seconds later. The committed test waits up to 28 seconds for an event matching
both the executable and the current fixture, so an unrelated block cannot make
it pass.

### Reporter confirmation

The startup log is outside Documents, at
`%LOCALAPPDATA%\nt_helper\logs\nt_helper_startup.log`; it was successfully written
in every CFA reproduction, including the failed old-version launch. The error
screen names the file whose creation failed (`.migrated`), not a failed log write.

To establish the cause on the reporter's PC, correlate the failed launch with
Windows Security's Protection History, or event **1123** in **Event Viewer >
Applications and Services Logs > Microsoft > Windows > Windows Defender >
Operational**, naming `nt_helper.exe` and the affected Documents folder. A startup
log with errno 2 alone does not identify which filesystem filter rejected the write.

Microsoft documents [event 1123 as a CFA block](https://learn.microsoft.com/en-us/defender-endpoint/controlled-folder-access-monitor)
and [per-executable CFA allowances](https://learn.microsoft.com/en-us/defender-endpoint/controlled-folder-access-configure).
The [DeployMaster vendor manual](https://www.deploymaster.com/manual/DeployMaster.pdf)
(page numbered 23, PDF page 25) also describes Win32 `CreateFile` returning
`ERROR_FILE_NOT_FOUND` when CFA rejects a new file in an existing directory.
If the reporter confirms this cause, v2.51.1 has now passed that exact condition;
for an existing Documents data store, allowing the installed executable through
CFA is a targeted workaround that preserves the data location and keeps CFA on.

The final repository script was then run successfully against both public
packages again. Its evidence is at
`C:\Users\runner\AppData\Local\nt-helper-cfa-causal-e9449619f49b4601a38777293693bcc5`.
Defender event 1123 record IDs are **683** (old failure), **686** (fixed startup),
and **687** (second fresh fixed startup). An independent post-run check compared
Defender's before/after snapshots and every saved known-folder registry value
and type: all matched. CFA was restored to off, real-time antivirus protection
remained on, no nt_helper process remained, and the runner service was running.
