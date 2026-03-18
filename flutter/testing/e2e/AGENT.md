# E2E Agent Guide

This folder is the source of truth for the E2E framework.

## Editing rule

- New E2E framework logic is developed exclusively here.
- `patrol_test/explorer/**` and `patrol_test/domain_tests/**` are only thin
  Patrol entrypoints.

## Key entrypoints

- Generation: `testing/e2e/scripts/generate.sh`
- Local device run: `testing/e2e/scripts/run_local_supabase.sh`
- Journey gate: `testing/e2e/scripts/verify_journey_coverage.sh`
- Runtime budget: `testing/e2e/scripts/verify_runtime_budget.sh`
- Failure summary: `testing/e2e/scripts/extract_failed_tests.dart`

## Portability rule

If the framework is moved into another repository, copy `testing/e2e/` first.
After that, only add project-specific adapters for Flutter, routing, seeds,
and CI.
