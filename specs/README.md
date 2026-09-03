# Decision-free spec programs

Decision-free executor programs are temporary delivery material. Each active
program has a `spec.md` containing resolved architecture and a `plan.md`
containing ordered mechanical steps. Use the `decision-free-specs` skill to
create or extend one.

The executing model makes no architectural decisions: paths, interfaces,
behavior, tests, and commit boundaries are settled before execution. Unexpected
conditions use the plan's recovery rule instead of an improvised redesign.

## Active program

| Folder | Purpose | Steps |
|---|---|---|
| `specification-aware-offline-metadata/` | Infer adjacent-repeat grammars, bundle them beside a flat shape, and expand requested shapes offline | 6 |

## Lifecycle

1. Keep an active program while any step, verification, hardware acceptance, or
   consuming worktree remains unfinished.
2. After delivery, verify every planned commit and the program-level gate.
3. Remove the completed program. Preserve only non-derivable rationale in an
   ADR and keep behavior contracts in maintained tests.
4. Apply the same rule to one-off dated specs: they are not permanent history
   once implementation and verification own their contract.

## Executor contract

The executor reads `conventions.md`, then the active program's `plan.md`. It
executes one step per fresh-context session, touches only named files, uses the
specified commit message, and runs that step's verification. The planning model
checks the complete commit sequence and program-level gate before cleanup.
