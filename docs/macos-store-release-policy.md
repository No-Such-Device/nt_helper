# macOS App Store release policy

The Apple matrix in [production-release.yml](../.github/workflows/production-release.yml)
submits both iOS and macOS with `automatic_release: true`: Apple releases each
version automatically after App Review approval. Changing that default does not
update a version already submitted to App Store Connect.

## Inspect an existing macOS submission

Use the production workflow's isolated `macos-release-policy` mode. It checks
the candidate tag and successful candidate build, then reads the exact existing
macOS version, selected build, review state, and `releaseType`. It uses the same
protected production environment and Apple credential as production submission.

```bash
gh auth switch -u thorinside
gh workflow run production-release.yml --ref main \
  -f mode=macos-release-policy -f tag=v2.63.3 \
  -f apply_macos_release=false
```

Inspect the job's `before` and `after` JSON. If it already reports
`AFTER_APPROVAL`, the requested policy is verified. Otherwise, after confirming
the version/build and pending review state, dispatch the same command with
`-f apply_macos_release=true` to PATCH only `releaseType: AFTER_APPROVAL` and
verify it with a separate GET. An already-automatic version is left unchanged.

This mode performs no build, upload, review submission, review withdrawal,
Android/iOS mutation, or pricing/territory change. It refuses to change policy
outside `WAITING_FOR_REVIEW` / `IN_REVIEW`, and reports Apple API restrictions
verbatim. If Apple locks the setting, retain the existing review and report the
restriction for follow-up. Check the workflow run and its readback before
claiming the pending version has changed.
