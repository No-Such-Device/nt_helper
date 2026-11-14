# App-wide snackbar policy audit

The user explicitly requires **zero affirmative/success snackbars**, not just in
file browsing. Worktree `AGENTS.md` now states the strict rule: errors,
exceptional warnings and invalid-action recovery only; no routine success or
progress snackbars and no replacement toasts.

## Scope and changes

Audited every `SnackBar`/`showSnackBar` constructor/call under `lib/` and the
callers of dynamic feedback helpers (routing, cleanup, video, chat attachment,
file parameters, notes and slot/controller fallback). No global messenger filter
silences notifications blindly.

- Removed **29 direct/helper success or routine progress calls**: browser download,
  upload (both paths), create, rename and delete; screenshot/video/debug/PowerShell
  clipboard copies; routing canvas/viewport/node copies and sharing; plugin-load
  and algorithm refresh/rescan progress; SD-remount/reboot command acknowledgments
  and checkpoint creation.
- Four mixed/conditional paths were narrowed or converted: performance-page
  assignment/removal success is silent; checkpoint restore only reports failure;
  successful duplicate-plugin cleanup is silent while failure/uncertainty remains;
  bus assignment no longer emits a Connected/Disconnected success snackbar.
  Its Undo remains available in an always-reserved canvas control, not a toast.
- Hardened the algorithm-node feedback helper against non-error calls and named
  the remaining routing feedback helper explicitly for exceptions.
- Kept normal inline/cubit state and screen-reader announcements. No success
  snackbar was substituted with another popup notification.

## Preserved exceptional categories

Read/write/load/install/backup/reboot/copy failures; unavailable documentation or
unsupported firmware/platform operations; invalid input/drops; empty clipboard,
missing selection/device/source preventing an action; uncertain/deferred cleanup;
unavailable offline algorithms and preserved-data warnings; startup/database,
remote-video, routing validation and controller-fallback errors; preference and
storage failures. Routine progress is not classified as an exception.

`test/policies/snackbar_policy_test.dart` parses source ASTs to guard affirmative
literals in snackbar constructors and feedback callers throughout `lib/`.
`analyzer` is now an explicit dev dependency at its already-locked version (no
package upgrade). Dynamic cleanup and bus-assignment widget regressions verify
success stays silent, exceptional warnings remain, and Undo remains functional
without geometry movement. Browser success/error regressions cover rename and
folder creation. This is a scoped audit plus regression guard, not a claim that
arbitrary future dynamic message text can be semantically classified by syntax.
