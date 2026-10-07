# Firmware Back candidate evidence

Project `8dc43218-a73a-421a-9dae-90ab08d87ea5`; delivery ticket
`d7aeffbb-e85c-4009-97cb-2e296a660f6f` (REQ-005/REQ-006, AC-006–AC-008).
Approved Spec reference: `ae7b1113-9e2b-457f-8556-b232cb539c37`, SHA-256
`004977f537d6701100b594bdd5052d3ab587027f8846742a35f6d13654fe6a4a`.

Durable Substrate artifacts, readable by `get_reference`/`get_artifact`:

- Completion report, exact candidate identity, command results and complete log
  references: `52babede-49c5-48e5-9e28-6a87e184ccd3`.
- Independent implementation review and disposition:
  `ad8214b9-40ab-4d75-bceb-29abaf92c56e`.
- Retained upstream source traces, AC-001–AC-005 evidence and focused logs:
  `e8230ff8-4d32-42ca-8004-268aff82616d`.

The report and review record their own completion status; this index alone is
not a passing result, implementation review, administrator approval, or final
verifiedBranch reconciliation. The exact final head must be recorded in those
artifacts after this documentation-only commit. Production implementation is
unchanged from `ffd464c29107d6206c9e4f3eeab06bb23c9e764e`.

The regression is exercised against unchanged `v2.56.0` production source
(`bbe0887dd9a6ec98a1c12dba96f0fd0afb6d1ca5`) in an isolated build-directory
export with the candidate navigation test, then against the final candidate.
Logs distinguish mocked transport proof from source reasoning. Physical
UI/transport checks, real bootloader commands/flashing, remote publication,
release builds, updater redesign and the unrelated Windows post-flash MidiSrv
lockup are excluded. Only this local delivery worktree is written; independent
review is read-only. Final acceptance reconciliation belongs to the next ticket.
