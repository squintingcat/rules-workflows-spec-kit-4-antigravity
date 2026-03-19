---
name: flutter-supabase-security-audit
description: >
  Security-Audit für Flutter/Dart + Supabase Projekte. Nutze diesen Skill, wenn du
  einen Full-Repo Security Scan (Frontend + Supabase Backend) willst, mit verifizierten
  Findings (wenig False Positives) und einem Markdown-Report unter reports/security/.
  NICHT verwenden für normales Feature-Dev oder allgemeines Code-Review.
---

# Flutter + Supabase Security Audit (Markdown Report)

## Ziel

- Finde realistisch ausnutzbare Sicherheitslücken (nicht nur Stil/Best-Practices).
- Verifiziere jedes Finding aktiv (Beweise sammeln UND versuchen zu widerlegen).
- Schreibe am Ende einen **Markdown Report** als Datei ins Repo.
- Standardmodus: **Report-only** (keine Code-Änderungen). Änderungen nur, wenn der User explizit "apply fixes" / "patch" verlangt.

## Eingaben (optional, aus der User-Nachricht parsen)

- scope: `full` (default) | `frontend` | `backend`
- output: Pfad zur Report-Datei (default siehe unten)
- mode: `report` (default) | `apply` (nur wenn explizit gewünscht)
- max_findings: default 50
Wenn nichts angegeben ist: scope=full, mode=report, max_findings=50.

## Default Output-Pfade

- Report-Datei: `reports/security/security-audit-YYYY-MM-DD-hhmmss.md`
- Zusätzlich (optional): `reports/security/latest.md` als Kopie derselben Inhalte.
- Bei Supabase-Remote-Checks zusätzlich JSON-Artefakte unter `reports/security/` ablegen:
  - `phase2_mcp_summary.json`
  - `phase2_supabase_db_lint_summary.json`
  - optional Rohdaten (`phase2_supabase_db_lint_linked_clean.json`, etc.)

Wenn Ordner fehlt: anlegen.

## Sicherheits-/Compliance-Regeln für den Scan

- Keine exploitbaren Payloads oder Schritt-für-Schritt-Angriffsanleitungen.
- Keine Secrets im Report ausgeben. Immer redaction: z.B. `sb_secret_abc…(redacted)` oder nur Prefix + Hash.
- Keine neuen Production-Dependencies als Fix ohne klare Begründung + explizite Zustimmung.
- Findings nur als “verifiziert” listen, wenn du konkrete Code-/Policy-Evidence hast.
  Unsichere Punkte kommen in "Needs manual verification".

---

## Workflow

## Phase 0 — Repo-Inventur (schnell, strukturiert)

1) Identifiziere Projektstruktur:
   - Flutter: `pubspec.yaml`, `lib/`, `android/`, `ios/`, `web/` (falls vorhanden)
   - Supabase: `supabase/` (migrations, seed, functions, config.toml, etc.)
2) Identifiziere Auth-Flow:
   - Wo wird Supabase Auth initialisiert?
   - Wo werden Sessions/Tokens gespeichert?
3) Identifiziere Data-Entry-Points:
   - Deep links / dynamic links
   - Push-notification payloads
   - User input → DB writes/updates
   - File uploads (Supabase Storage)
4) Lege Scope-Excludes fest (nicht scannen, außer relevant):
   - build outputs (`build/`, `.dart_tool/`, `ios/Pods/`, `android/.gradle/`, etc.)
   - generierte Dateien

## Phase A — Discovery Scan (breit)

### A1: Secrets & Key-Handling

- Suche nach Supabase Keys / Tokens / Secrets:
  - `service_role`, `sb_secret_`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET`, `JWT_SECRET`, private keys
- Prüfe `.env*`, `*.secrets*`, `config.*`, CI configs.
- Stelle sicher: Im Flutter Client darf maximal anon/publishable key liegen – niemals service_role/secret key.

### A2: Flutter/Dart Security Hotspots

Suche nach:

- Insecure TLS / Certificate-Bypass:
  - `HttpOverrides`, `badCertificateCallback`, custom `SecurityContext` ohne Pinning/Checks
- Token/Sensitive Storage:
  - Nutzung von `shared_preferences`, `hive`, `sqflite`, plain files für Tokens/PII
  - Logging von Tokens/Headers (`print`, `debugPrint`, logger)
- URL Handling / Deep Links:
  - `Uri.parse(...)` auf untrusted input
  - `url_launcher` / WebViews mit untrusted URLs
- Input → DB writes:
  - Validierung/Normalisierung vor `insert/update` (auch wenn DB RLS hat)

### A3: Supabase Backend Security Hotspots

#### RLS / Data API Exposure

- Prüfe SQL-Migrations und/oder schema definitions:
  - Ist RLS pro Tabelle/View/Function aktiviert?
  - Gibt es Policies für SELECT/INSERT/UPDATE/DELETE?
  - Gibt es auffällig permissive Policies (z.B. `USING (true)` oder `TO anon` ohne Einschränkungen)?
- Prüfe Funktionen (`SECURITY DEFINER`, dynamisches SQL, `EXECUTE`).

#### Storage

- Prüfe Policies auf `storage.objects`.
- Prüfe Buckets: private/public, und ob private Buckets korrekt über Policies geschützt werden.

#### Edge Functions (falls vorhanden)

- Prüfe `supabase/config.toml`:
  - `verify_jwt = false` nur für echte Webhooks/öffentliche Endpoints, dann muss es eine alternative Auth/Signature-Verification geben.
- Prüfe, ob service_role/secret key nur serverseitig genutzt wird (Deno env), nie hardcoded.

## Phase B — Verification (False-Positive Filter)

Für jedes potenzielle Finding:

1) Belege:
   - konkrete Datei + Zeile(n)
   - Datenfluss: Quelle (untrusted) → Sink (DB write / privileged op)
   - Für Supabase: betroffene Tabelle/Policy/Role
2) Widerlegungsversuch:
   - Gibt es bereits RLS/Policy die es verhindert?
   - Ist es nur in Debug builds aktiv?
   - Ist es unreachable code?
Nur wenn nach B2 weiterhin plausibel/real: als Finding aufnehmen.

## Phase C — Tooling/Remote-Checks (MCP-first, CLI fallback)

### C1: Lokale App-Checks (best effort)

- Flutter:
  - `dart analyze` oder `flutter analyze`
  - `flutter test`

### C2: Supabase MCP Checks (wenn Server verfügbar)

1) Prüfe MCP-Verfügbarkeit (`codex mcp list`) und nutze den `supabase` Server, wenn vorhanden.
2) Bei Auth-Fehlern/abgelaufener Session zuerst re-login:
   - `codex mcp login supabase`
3) Führe mindestens folgende MCP-Abfragen aus:
   - Security Advisors: `get_advisors(type=\"security\")`
   - Performance Advisors: `get_advisors(type=\"performance\")`
   - Edge Functions: `list_edge_functions` und für kritische Funktionen `get_edge_function`
   - Storage Buckets: `list_storage_buckets`
   - Optional für Findings-Validierung: `execute_sql` auf `pg_policies` / relevante Kataloge
4) Schreibe eine knappe JSON-Zusammenfassung nach `reports/security/phase2_mcp_summary.json`.

### C3: Supabase CLI Lint (zusätzlich oder fallback)

- Wenn CLI verfügbar und Projekt gelinkt:
  - `supabase db lint --linked --output json`
- Fasse Findings strukturiert in `reports/security/phase2_supabase_db_lint_summary.json` zusammen.
- Wenn nur Roh-JSON vorliegt, optional als `phase2_supabase_db_lint_linked_clean.json` ablegen.

Wenn Commands fehlschlagen: im Report dokumentieren (Grund + was stattdessen statisch geprüft wurde).

## Phase D — Report schreiben (Markdown-Datei)

Erzeuge/überschreibe die Report-Datei (Default oder `output=`).

### Report Struktur (verpflichtend)

1) Titel + Metadaten (Datum, scope, mode, ggf. commit hash)
2) Architecture & Trust Boundaries (Flutter ↔ Supabase)
3) Findings (max_findings, sortiert nach Severity):
   Für jedes Finding:
   - Title
   - Severity: Critical/High/Medium/Low
   - Confidence: 0.0–1.0
   - Component: Frontend | Supabase DB | Storage | Edge Functions
   - Affected locations: file:line
   - Evidence: verifizierter Pfad, warum ausnutzbar
   - Recommendation
   - Patch (Unified diff) **oder** “No safe auto-fix”
   - How to verify (konkrete Schritte/Commands)
4) Needs manual verification (falls vorhanden)
5) Discarded candidates (3–5 Beispiele + warum verworfen)
6) Commands & outputs (gekürzt, relevante Snippets), inkl. MCP/CLI-Evidence + Artefaktpfade

---

## Severity Leitplanken

- Critical: Datenabfluss/Account takeover/RCE/privilege escalation mit wenig Aufwand
- High: sensitive data exposure oder authz bypass, aber mit Einschränkungen
- Medium: brauchbarer Impact, aber schwieriger/kontextabhängig
- Low: hardening / defense-in-depth / best practice

## Standard: Keine Code-Änderungen

- Wenn mode=report: nur Report-Datei schreiben
- Wenn mode=apply: nur minimal-invasive Fixes + Tests laufen lassen; Änderungen als separate Commits/Checkpoints (falls Git verfügbar)
