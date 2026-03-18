# Domain E2E Tests

Bucket-C journeys live here.

These tests are intentionally app-specific Patrol tests for flows that the generic explorer cannot verify structurally, for example:

- sensor-backed ride recording validation
- multi-entity integrity checks
- offline/online conflict resolution
- permission-denied recovery flows

They remain part of CI even after explorer migration.
