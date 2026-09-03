# Accessibility status

The 75 findings from the February 2026 accessibility audit were addressed and
their per-finding working documents have been retired. Current accessibility
requirements live in [`../../AGENTS.md`](../../AGENTS.md), and maintained
regression coverage lives in `test/ui/accessibility/`.

This status is not a claim that accessibility work is finished. Use the
retained documents below for the remaining product and coverage work:

- [`blind-coverage-checklist.md`](blind-coverage-checklist.md) records known
  gaps in keyboard-only workflows, focus restoration, and non-visual step
  editing.
- [`keyboard-navigation-scheme.md`](keyboard-navigation-scheme.md) is the
  intended keyboard interaction design. Verify each shortcut against current
  code and tests before describing it as implemented.

When a new issue is found, prefer a regression test plus a focused issue or
active plan. Remove temporary working documents after delivery, while retaining
non-derivable interaction decisions here or in an ADR.
