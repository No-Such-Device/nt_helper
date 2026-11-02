# Regression-test classification

The test suite uses the `regression` tag for tests that protect a distinct
regression, explicit bug fix, wire/protocol contract, migration, persistence
boundary, race or concurrency issue, platform-specific failure,
accessibility/layout requirement, or another behavior with a credible
recurrence risk.

Tests without this tag are behavior tests: they primarily demonstrate routine
current behavior, construction, existence, simple mapping, or a generic happy
path.

Classification used the Substrate `buildability-classifier` on complete
individual test invocations. A test was tagged when the classifier's
regression probability was at least **0.70**. This threshold was chosen to
favor precision: CI should run only tests with strong evidence of regression
value. Classifier scores are advisory; wire, race, persistence, migration,
accessibility, layout, and platform-specific tests were retained when their
source showed a distinct failure mode even if the score was below the cutoff.

The CI workflow runs only tagged tests:

```sh
flutter test --no-pub --tags regression
```

The extraction helper used for repeatable source-grounded classification is
`tool/extract_dart_tests.py`.
