# E2E Framework

`testing/e2e` is the central source of truth for the automatically inferred E2E system.

Goals:
- AST-based journey detection from existing code and documentation
- deterministic generation of reviewable journey and coverage artifacts
- real Android/iOS E2E execution through Patrol against local Supabase
- portable across other repositories where possible

## Struktur

```text
testing/e2e/
  README.md
  config/
    runtime_budget.env
  framework/
    pathing/
      generate_e2e_from_code.dart
      e2e_pathing.dart
      src/
  scripts/
    generate.sh
    run_exploration.sh
    run_domain_tests.sh
    run_journey_diff.sh
    run_local_supabase.sh
    verify_journey_coverage.sh
    verify_runtime_budget.sh
    extract_failed_tests.dart
  test/
    pathing/
```

## What intentionally stays outside

These paths stay outside `testing/e2e/` because Flutter or GitHub technically expect them in these locations:

- `patrol_test/explorer/**`
  - Patrol explorer entrypoint
- `patrol_test/domain_tests/**`
  - Patrol wrappers for bucket-C domain tests
- `.github/workflows/**`
  - CI entrypoints

## Standard commands

```bash
# AST inference + generation
bash ./testing/e2e/scripts/generate.sh --mode scoped
bash ./testing/e2e/scripts/generate.sh --mode full

# Patrol target against local Supabase
bash ./testing/e2e/scripts/run_local_supabase.sh \
  --mode full \
  --device emulator-5554 \
  --flavor dev \
  --dart-flavor dev \
  --target patrol_test/explorer/blind_explorer_e2e_test.dart

# Runtime explorer against an emulator plus report materialization
bash ./testing/e2e/scripts/run_exploration.sh \
  --mode full \
  --device emulator-5554 \
  --flavor dev \
  --dart-flavor dev

# Refresh the journey diff from ground truth and explorer results
bash ./testing/e2e/scripts/run_journey_diff.sh --mode full

# Validate adapter budget against journey classification
bash ./testing/e2e/scripts/verify_adapter_budget.sh --mode full

# Explorer, domain tests, and adapter budget as a local parallel check
bash ./testing/e2e/scripts/run_parallel_validation.sh \
  --mode full \
  --device emulator-5554 \
  --flavor dev \
  --dart-flavor dev

# Bucket-C domain tests, if present
bash ./testing/e2e/scripts/run_domain_tests.sh \
  --device emulator-5554 \
  --flavor dev \
  --dart-flavor dev

# Coverage gate for discovered executable journeys
bash ./testing/e2e/scripts/verify_journey_coverage.sh --mode full

# Runtime budget check for an existing run
bash ./testing/e2e/scripts/verify_runtime_budget.sh \
  --log .ciReport/nightly_e2e_android.log \
  --budget-file testing/e2e/config/runtime_budget.env
```

## Erzeugte Artefakte

- Reports:
- `.ciReport/e2e_pathing/analysis_model_<mode>.json`
- `.ciReport/e2e_pathing/ground_truth_<mode>.json`
- `.ciReport/e2e_pathing/journey_classification_<mode>.json`
- `.ciReport/e2e_pathing/journey_diff_<mode>.md`
- `.ciReport/e2e_pathing/adapter_budget_<mode>.md`
- `.ciReport/e2e_pathing/adapter_budget_<mode>.json`
- `.ciReport/e2e_pathing/parallel_validation_<mode>.md`
- `.ciReport/e2e_pathing/path_report_<mode>.md`
- `.ciReport/e2e_pathing/screen_audit_<mode>.md`
- `.ciReport/e2e_pathing/summary_<mode>.md`
- `.ciReport/e2e_pathing/exploration_result_<mode>.json`
- `.ciReport/e2e_pathing/coverage_gap_<mode>.json`
- `.ciReport/e2e_pathing/exploration_summary_<mode>.md`
- Patrol entrypoints:
  - `patrol_test/explorer/**`
  - `patrol_test/domain_tests/**`
  - `patrol_test/test_bundle.dart` is generated transiently by the Patrol CLI
    and is not maintained manually
- Run reports:
  - `.ciReport/*.log`
  - `.ciReport/*.json`
  - `.ciReport/*_failures.md`
  - `.ciReport/*_runtime_budget.md`


## Portability to other repositories

If you want to move the framework into another repository, copy this folder first:

- `testing/e2e/`

After that, you only need thin project-specific adapters:

1. Flutter runner adapter
- `./scripts/flutterw.sh` or an equivalent Flutter entrypoint

2. Patrol entrypoints
- by default `patrol_test/explorer/**` for generic exploration
- `patrol_test/domain_tests/**` for bucket-C wrappers
- the Patrol CLI also creates `patrol_test/test_bundle.dart` at runtime

3. Router and feature conventions
- AST inference expects Flutter feature structures, especially `lib/features/**/presentation/**`

4. Backend and seed integration
- local Supabase stack plus migration and seed reset

5. Project adapter
- `testing/e2e/framework/adapter/*.dart` is the place for app-specific login,
  seed, permission, and outcome-probe logic

6. Bucket-C domain tests
- journeys that cannot be validated generically belong under
  `patrol_test/domain_tests/**`

7. CI entrypoints
- workflows and hooks should call the framework folder directly

## Legacy-Status

The old distributed E2E structure has been removed.

There is no second development location anymore for:

- Generator
- journey gates
- runtime budget verification
- failure extraction
- framework tests

All further development happens exclusively under `testing/e2e/`.

## Review rule

If you work on the E2E system:
- change framework code only in `testing/e2e/`
- `patrol_test/explorer/**` and `patrol_test/domain_tests/**` are thin
  entrypoints; framework logic stays under `testing/e2e/`

## Patrol notes

- Native permission dialogs are handled through Patrol, not through plain
  `integration_test`.
- Explorer runs materialize runtime reports from the Patrol log:
  - `exploration_result_<mode>.json`
  - `coverage_gap_<mode>.json`
  - `journey_diff_<mode>.json`
  - `exploration_summary_<mode>.md`
- Parallel validation combines:
  - the explorer run
  - bucket-C domain tests
  - the adapter budget check
  - summarized in `parallel_validation_<mode>.md`
- `run_local_supabase.sh` performs Android preflight cleanup before every
  Patrol run:
  - uninstall the target app
  - uninstall the `*.test` package
  - remove `androidx.test.orchestrator` and `androidx.test.services`
  - delete additional test outputs
  - log the available `/data` storage
- Generated Patrol test names must stay short and CLI/JUnit-safe. The
  human-readable description therefore stays in the analysis model and the run
  log, while the actual Patrol test ID is kept technically stable.
