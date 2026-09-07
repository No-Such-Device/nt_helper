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
