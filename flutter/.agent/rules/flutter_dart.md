---
trigger: always_on
---

# AI rules for Flutter & Dart (Antigravity)

You are an expert in Flutter and Dart development. Your goal is to build beautiful, performant, and maintainable applications following modern best practices. You have expert experience writing, testing, and running Flutter applications for mobile (Android/iOS), web, and desktop. In pre-freeze phases, visual iteration is encouraged. Once a UI contract is active, visual changes require explicit versioning.

## Interaction guidelines

- Assume the user understands programming fundamentals but may be new to Dart/Flutter details.
- When generating code, explain Dart-specific topics briefly when relevant (null safety, async/await, streams).
- If requirements are ambiguous, ask clarifying questions about expected behavior and the target platforms (Android/iOS/Web/Desktop).
- When proposing a new dependency from pub.dev, explain *why* it’s needed and what tradeoffs it has.
- Prefer minimal, incremental changes and provide a short plan before editing.

## Tooling & verification (must do)

- Before claiming something is fixed, run:
  - `flutter analyze`
  - `flutter test` (or the relevant subset)
- For test-relevant changes, quality-gate verification must use repository entrypoints by context:
  - local commit DoD (scoped): `bash ./scripts/verify_dod.sh`
  - local push CI (full without mutation): `bash ./scripts/run_local_ci.sh --skip-mutation`
  - remote pull request CI (full with mutation): `.github/workflows/flutter-ci.yml`
- For E2E-framework changes, use the centralized entrypoints under `testing/e2e/scripts/**` instead of ad-hoc commands:
  - `generate.sh`
  - `run_exploration.sh`
  - `run_journey_diff.sh`
  - `run_domain_tests.sh`
  - `verify_adapter_budget.sh`
  - `verify_journey_coverage.sh`
- Format code with `dart format` (or editor formatting) for touched files.
- Prefer automated fixes when available: `dart fix --apply` (only when safe and scoped; don’t mass-change the repo without asking).

## Project structure

- Assume a standard Flutter structure with `lib/main.dart` as entry point unless the repo indicates otherwise.
- The project structure follows the architecture contract defined in `architecture.md`.
- For separation of concerns within features, refer to the internal feature structure rules in the architecture contract.

## Flutter style guide

- Apply SOLID principles pragmatically.
- Write concise, modern, declarative Dart.
- Prefer composition over inheritance.
- Prefer immutability; widgets (esp. StatelessWidget) should be immutable.
- Separate ephemeral UI state from app/domain state.
- Do not introduce a new state-management library unless explicitly requested. Drift (local DB) and Supabase Flutter are approved exceptions.
- Keep widgets small and reusable; split large `build()` methods into private widget classes (prefer widgets over helper methods returning Widget).
- Use `const` constructors wherever possible.

## Code quality

- Avoid abbreviations; use descriptive names.
- Keep code straightforward (avoid clever/obscure patterns).
- Handle errors explicitly; don’t fail silently.
- **Zero-Print-Policy**: Any form of `print()`, `debugPrint()`, or `developer.log()` is prohibited in feature code.
- **LogService Mandatory**: The `LogService` MUST be used exclusively for logging.
  - Errors/Exceptions -> `LogService.feature.error('Message', error: e, stackTrace: st);`
  - Important Info -> `LogService.feature.info('Message');`
  - Debugging -> `LogService.feature.debug('Message');`
- Exception for test infrastructure: explorer runtime output that is intentionally machine-parsed may use the centralized explorer logger under `testing/e2e/framework/explorer/**`. Do not scatter raw `print()` calls outside that dedicated logger abstraction.
- Follow naming conventions:
  - PascalCase: classes
  - camelCase: members, variables, functions
  - snake_case: file names
- Aim for readable functions (single responsibility; keep them small).

### Supabase Database & Drift naming conventions

#### Drift Table Definitions

- **Column Getters**: Use `camelCase` (follows Dart naming conventions)

  ```dart
  TextColumn get modelName => text().nullable()();
  TextColumn get storageLocation => text().nullable()();
  ```

#### Supabase/PostgreSQL

- **Column Names**: Use `snake_case` (follows SQL/PostgreSQL conventions)

  ```sql
  CREATE TABLE equipment_items (
    model_name text,
    storage_location text
  );
  ```

#### Domain Entities (Cross-Platform Mapping)

- **Field Names**: Use `camelCase` (Dart standard)
- **Mapping**: Use `@JsonKey` annotation for database column mapping

  ```dart
  class EquipmentItem {
    @JsonKey(name: 'model_name') final String? modelName;
    @JsonKey(name: 'storage_location') final String? storageLocation;
  }
  ```

#### Rationale

- ✅ Respects **language-specific conventions** (Dart = camelCase, SQL = snake_case)
- ✅ Uses **idiomatic mapping patterns** (`@JsonKey` is standard in Flutter/Dart)
- ✅ Maintains **separation of concerns** (Drift layer follows Dart, DB layer follows SQL)
- ℹ️ Alternative: Drift could use snake_case for 1:1 alignment, but this **violates Dart naming conventions**

#### Rule Summary

**DO**:

- Use `camelCase` in Drift column getters
- Use `snake_case` in PostgreSQL/Supabase
- Use `@JsonKey` for mapping between the two

**DON'T**:

- Use `snake_case` in Dart code (except file names)
- Skip `@JsonKey` mapping when names differ
- Assume Drift and Supabase must use identical naming

## Language conventions (mandatory)

All code, database entities, and technical identifiers MUST use English.

**English ONLY for:**

- Variable names, function names, class names  
- Database table names, column names
- Database entity identifiers (e.g., slugs, enums, keys)
- File names
- Comments in code
- API endpoints
- Migration file names

**Localized (DE/EN) for:**

- User-facing text (via i18n/l10n only)
- UI labels, buttons, messages
- Help content
- Error messages shown to users

**Examples:**

✅ **CORRECT:**

```dart

// Code: English
class FavorDefinition {
  final String slug;  // e.g., 'blanket_on', 'blanket_off'
}

// Database: English
favor_definitions (
  slug: 'blanket_on',
  title_de: 'Eindecken',
  title_en: 'Put on blanket'
)

## Dart best practices
- Follow Effective Dart (https://dart.dev/effective-dart).
- Write sound null-safe code; avoid `!` unless guaranteed safe.
- Use async/await correctly with robust error handling.
- Use Streams for sequences of async events; Futures for single async results.
- Prefer exhaustive `switch` expressions where appropriate.

## Flutter best practices
- Avoid expensive work in `build()` (no network calls, heavy parsing, etc.).
- For long lists, use `ListView.builder` / `SliverList`.
- For expensive computations (e.g., JSON parsing), use `compute()`/isolates when justified.
- Ensure responsive layouts for web/desktop (breakpoints, adaptive widgets).
- Maintain accessibility basics (semantics labels, tap target sizes) where applicable.

## Navigation
- Prefer the existing routing approach in the repo.
- If adding routing to a new app and no approach exists, prefer `go_router` for declarative navigation and web support.
- Use plain `Navigator` for short-lived screens (dialogs, temporary flows) when deep-linking is not needed.

## Data handling & serialization
- Prefer typed models.
- If JSON serialization is needed, prefer `json_serializable` + `json_annotation` (only if the project already uses it or the user requests it).
- Prefer snake_case mapping when dealing with common backend JSON conventions.

## Code generation
- If the project uses code generation, ensure `build_runner` is configured.
- After changes affecting generated code, run:
  - `dart run build_runner build --delete-conflicting-outputs`
- Do not run broad codegen or large refactors without warning the user first.

## Testing
- Tests are mandatory for:
  - new implementations with user-visible or business-relevant behavior,
  - behavior changes,
  - bug fixes.
- Every behavior-relevant change must include automated test coverage for:
  - happy path,
  - relevant failure/error path,
  - at least one boundary/edge case when applicable.
- Test type selection is mandatory:
  - unit tests: domain/data/application logic
  - widget tests: UI components, presentation behavior, navigation interactions
- integration tests: critical cross-layer flows and end-to-end behavior when needed
- E2E strategy for this repository is:
  - generic explorer coverage for Bucket A journeys,
  - project-adapter-assisted explorer coverage for Bucket B journeys,
  - explicit Patrol domain tests for Bucket C journeys.
- Do not add new generated, app-specific E2E suites as the default path.
- When changing `testing/e2e/**`, keep app knowledge minimal and push it to adapter/domain-test layers instead of the generic core.
- Bug fixes must include a regression test that would fail without the fix.
- UI changes in `lib/**/presentation/**` or `lib/**/widgets/**` must include at least one `testWidgets` change in corresponding test scope.
- A pure "manual QA only" strategy is not accepted as the sole validation for changed behavior.
- Removing tests or weakening assertions is not allowed unless replaced by equal-or-stronger automated coverage in the same delivery.
- For the E2E framework, removing explorer coverage, journey-diff parity, or Bucket-C domain coverage is not allowed unless replaced by equal-or-stronger automated evidence in the same delivery.
- Test exceptions are allowed only with explicit user approval and must document:
  - reason,
  - risk,
  - owner,
  - follow-up due date.
- Agents must never add or broaden `ops/testing/test_exceptions.txt` entries without explicit user approval in the active conversation.
- Follow Arrange-Act-Assert (Given-When-Then).
- Prefer fakes/stubs over mocks; use mocks only when necessary.

### Test-scope governance (mandatory)
- Coverage baseline must only include testable production code. Scope is controlled centrally by:
  - `ops/testing/coverage_include_patterns.txt` (allow-list)
  - `ops/testing/coverage_exclude_patterns.txt` (deny-list)
- Branch coverage gate and ratchet apply to the unified scoped code (logic + UI) via LCOV `BRDA`.
- Scoped line coverage is informational only and must not block completion on its own.
- If a changed UI file is outside the unified coverage scope, the change is incomplete until one of the following is done in the same delivery:
  - add the file to unified coverage scope and provide widget tests,
  - or keep it outside unified scope but provide direct file-level widget tests in `test/.../<same_file>_test.dart`,
  - or add an approved `TEST_EXCEPTION` (`ui_scope_admission`) with reason, risk, owner, due date.
- Quality ratchet is mandatory: scoped quality must remain stable or improve over time.
- Generated files must stay excluded from scoped coverage (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, generated l10n artifacts).
- Files excluded as "not testable" are only allowed when they are integration/platform wiring and a stable unit seam is not practical.
- If the user requests a 10/10 test suite, run:
  - `bash ./scripts/run_local_ci.sh --ten-of-ten --skip-mutation`
  - `bash ./scripts/run_test_stability_matrix.sh` (or use the matrix run generated by local CI)
- Mutation testing scope must be maintained in:
  - `ops/testing/mutation_targets.txt` (target file + test command)
  - `ops/testing/mutation_exclude_mutants.txt` (line-level justified exclusions)
- Exclusions are exceptions, not defaults: each exclusion needs a concrete technical reason and must be revisited when code changes.
- Platform-specific behavior must be tested via abstractions/fakes where possible; unconditional platform skips are a last resort and must be documented in mutation exclusions.

## Safety / permissions (important)
- Never run destructive commands (deleting files, sweeping refactors, formatting entire repo) without asking first.
- Never modify platform folders (`android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/`) unless the user request requires it.
