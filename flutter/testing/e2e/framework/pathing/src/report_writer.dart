import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class ReportWriter {
  ReportWriter({
    required this.repoRoot,
    this.outputDirectory = '.ciReport/e2e_pathing',
  });

  final String repoRoot;
  final String outputDirectory;

  Map<String, String> write(AnalysisModel model) {
    final outDir = Directory('$repoRoot/$outputDirectory');
    outDir.createSync(recursive: true);

    final modelFile =
        '$outputDirectory/analysis_model_${model.mode.value}.json';
    final pathReportFile =
        '$outputDirectory/path_report_${model.mode.value}.md';
    final summaryFile = '$outputDirectory/summary_${model.mode.value}.md';
    final screenAuditFile =
        '$outputDirectory/screen_audit_${model.mode.value}.md';
    final groundTruthFile =
        '$outputDirectory/ground_truth_${model.mode.value}.json';
    final journeyClassificationFile =
        '$outputDirectory/journey_classification_${model.mode.value}.json';
    final journeyDiffFile =
        '$outputDirectory/journey_diff_${model.mode.value}.md';

    _writeIfChanged(path: modelFile, content: model.toPrettyJson());
    _writeIfChanged(path: pathReportFile, content: _renderPathReport(model));
    _writeIfChanged(path: summaryFile, content: _renderSummary(model));
    _writeIfChanged(path: screenAuditFile, content: _renderScreenAudit(model));
    if (model.groundTruth != null) {
      _writeIfChanged(
        path: groundTruthFile,
        content: const JsonEncoder.withIndent(
          '  ',
        ).convert(model.groundTruth!.toJson()),
      );
    }
    _writeIfChanged(
      path: journeyClassificationFile,
      content: const JsonEncoder.withIndent('  ').convert(
        model.journeyClassifications.map((item) => item.toJson()).toList(),
      ),
    );
    if (model.journeyDiffReport != null) {
      _writeIfChanged(
        path: journeyDiffFile,
        content: _renderJourneyDiff(model.journeyDiffReport!),
      );
    }

    return <String, String>{
      'analysis_model': modelFile,
      'path_report': pathReportFile,
      'summary': summaryFile,
      'screen_audit': screenAuditFile,
      'ground_truth': groundTruthFile,
      'journey_classification': journeyClassificationFile,
      'journey_diff': journeyDiffFile,
    };
  }

  String _renderPathReport(AnalysisModel model) {
    final grouped = SplayTreeMap<String, List<UserPath>>();
    for (final path in model.userPaths) {
      grouped.putIfAbsent(path.moduleKey, () => <UserPath>[]).add(path);
    }

    final buffer = StringBuffer();
    buffer.writeln('# Generated User Path Report (${model.mode.value})');
    buffer.writeln();
    buffer.writeln('## Analysis Summary');
    buffer.writeln();
    buffer.writeln('- Mode: `${model.mode.value}`');
    buffer.writeln('- Analyzed files: `${model.analyzedFiles.length}`');
    buffer.writeln(
      '- Deleted files in scope: `${model.deletedFilesInScope.length}`',
    );
    buffer.writeln('- Recognized user paths: `${model.userPaths.length}`');
    buffer.writeln(
      '- Executable user paths: `${model.summary.executablePathCount}`',
    );
    buffer.writeln(
      '- Covered executable user paths: `${model.summary.coveredExecutablePathCount}`',
    );
    buffer.writeln(
      '- Uncovered executable user paths: `${model.summary.uncoveredExecutablePathCount}`',
    );
    buffer.writeln(
      '- Executable journey coverage: `${model.summary.journeyCoveragePercent.toStringAsFixed(2)}%`',
    );
    buffer.writeln('- Coverage references: `${model.coverageReferences.length}`');
    buffer.writeln(
      '- Blocked paths (not generated): `${model.blockedPathReasons.length}`',
    );
    buffer.writeln('- Scope hint: ${model.summary.scopeDiffHint}');
    buffer.writeln();

    if (model.summary.uncertainties.isNotEmpty) {
      buffer.writeln('## Open Uncertainties');
      buffer.writeln();
      for (final uncertainty in model.summary.uncertainties) {
        buffer.writeln('- $uncertainty');
      }
      buffer.writeln();
    }

    if (grouped.isEmpty) {
      buffer.writeln('## No Paths Detected');
      buffer.writeln();
      buffer.writeln(
        'No actionable user paths were detected for this scope. This can happen in scoped mode when no relevant `lib/**` file changed.',
      );
      buffer.writeln();
    }

    for (final entry in grouped.entries) {
      final moduleKey = entry.key;
      final paths = entry.value..sort((a, b) => a.pathId.compareTo(b.pathId));

      buffer.writeln('## Module: `$moduleKey`');
      buffer.writeln();

      for (final path in paths) {
        final linkedReferences =
            model.pathToCoverageReferences[path.pathId] ?? const <String>[];
        final blockedReasons =
            model.blockedPathReasons[path.pathId] ?? const <String>[];
        final isExecutable = blockedReasons.isEmpty;

        buffer.writeln('### ${path.pathId}');
        buffer.writeln();
        buffer.writeln('- Variant: `${path.variant}`');
        buffer.writeln('- Confidence: `${path.confidence}`');
        buffer.writeln('- Outcome class: `${path.outcomeClass}`');
        buffer.writeln('- Feature key: `${path.featureKey}`');
        buffer.writeln('- Description: ${path.description}');
        buffer.writeln('- Primary source file: `${path.primarySourceFile}`');
        buffer.writeln(
          '- Source files: ${path.sourceFiles.map((f) => '`$f`').join(', ')}',
        );
        buffer.writeln('- Guards: ${_asInlineList(path.guards)}');
        buffer.writeln('- Validations: ${_asInlineList(path.validations)}');
        buffer.writeln('- Error paths: ${_asInlineList(path.errors)}');
        buffer.writeln(
          '- Supabase interactions: ${_asInlineList(path.supabaseInteractions)}',
        );
        buffer.writeln('- Parity key: `${path.parityKey}`');
        buffer.writeln(
          '- Linked coverage references: ${_asInlineList(linkedReferences)}',
        );
        buffer.writeln(
          '- Executable coverage reference: `${isExecutable ? 'yes' : 'no'}`',
        );
        if (blockedReasons.isNotEmpty) {
          buffer.writeln('- Blocked reasons: ${_asInlineList(blockedReasons)}');
        }

        buffer.writeln('- Sequence / steps:');
        for (final step in path.steps) {
          final ref = step.sourceReference;
          buffer.writeln(
            '  - `${step.kind}` ${step.description} (${ref.file}:${ref.line}:${ref.column})',
          );
        }

        if (path.heuristicNotes.isNotEmpty) {
          buffer.writeln('- Heuristic notes:');
          for (final note in path.heuristicNotes) {
            buffer.writeln('  - $note');
          }
        }

        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  String _renderSummary(AnalysisModel model) {
    final buffer = StringBuffer();
    buffer.writeln('# E2E Path Generation Summary (${model.mode.value})');
    buffer.writeln();
    buffer.writeln('- Mode: `${model.mode.value}`');
    buffer.writeln('- Analyzed files: `${model.summary.analyzedFileCount}`');
    buffer.writeln('- Recognized paths: `${model.summary.pathCount}`');
    buffer.writeln(
      '- Executable paths: `${model.summary.executablePathCount}`',
    );
    buffer.writeln(
      '- Covered executable paths: `${model.summary.coveredExecutablePathCount}`',
    );
    buffer.writeln(
      '- Uncovered executable paths: `${model.summary.uncoveredExecutablePathCount}`',
    );
    buffer.writeln(
      '- Executable journey coverage: `${model.summary.journeyCoveragePercent.toStringAsFixed(2)}%`',
    );
    buffer.writeln('- Coverage references: `${model.summary.coverageReferenceCount}`');
    buffer.writeln('- Blocked paths: `${model.blockedPathReasons.length}`');
    buffer.writeln('- Scope difference note: ${model.summary.scopeDiffHint}');
    buffer.writeln();

    buffer.writeln('## By Module (Paths)');
    buffer.writeln();
    if (model.summary.modulePathCount.isEmpty) {
      buffer.writeln('- No module paths detected in this run.');
    } else {
      final modules = model.summary.modulePathCount.keys.toList()..sort();
      for (final module in modules) {
        buffer.writeln('- `$module`: ${model.summary.modulePathCount[module]}');
      }
    }
    buffer.writeln();

    buffer.writeln('## By Module (Coverage References)');
    buffer.writeln();
    if (model.summary.moduleReferenceCount.isEmpty) {
      buffer.writeln('- No coverage references produced in this run.');
    } else {
      final modules = model.summary.moduleReferenceCount.keys.toList()..sort();
      for (final module in modules) {
        buffer.writeln(
          '- `$module`: ${model.summary.moduleReferenceCount[module]}',
        );
      }
    }
    buffer.writeln();

    buffer.writeln('## Parity Mapping Snapshot');
    buffer.writeln();
    if (model.parityMapping.isEmpty) {
      buffer.writeln('- No parity mappings generated.');
    } else {
      final keys = model.parityMapping.keys.toList()..sort();
      for (final source in keys.take(20)) {
        final mapped = model.parityMapping[source] ?? '';
        buffer.writeln('- `$source` -> `$mapped`');
      }
      if (keys.length > 20) {
        buffer.writeln(
          '- ... ${keys.length - 20} additional mappings omitted in summary.',
        );
      }
    }
    buffer.writeln();

    if (model.summary.uncertainties.isNotEmpty) {
      buffer.writeln('## Uncertainties');
      buffer.writeln();
      for (final item in model.summary.uncertainties) {
        buffer.writeln('- $item');
      }
      buffer.writeln();
    }

    if (model.blockedPathReasons.isNotEmpty) {
      final reasonCounts = SplayTreeMap<String, int>();
      for (final reasons in model.blockedPathReasons.values) {
        for (final reason in reasons) {
          reasonCounts[reason] = (reasonCounts[reason] ?? 0) + 1;
        }
      }

      buffer.writeln('## Blocked Reason Distribution');
      buffer.writeln();
      for (final entry in reasonCounts.entries) {
        buffer.writeln('- `${entry.key}`: ${entry.value}');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _renderScreenAudit(AnalysisModel model) {
    final coveredCounts = <String, int>{};
    for (final path in model.userPaths) {
      coveredCounts[path.primarySourceFile] =
          (coveredCounts[path.primarySourceFile] ?? 0) + 1;
    }

    final routedClasses = model.routeBindings.keys.toSet();
    final routePathsByClass = model.routeBindings;
    final entries = <_ScreenAuditEntry>[];

    for (final signal in model.fileSignals) {
      final filePath = signal.filePath;
      if (!filePath.contains('/presentation/')) {
        continue;
      }
      if (!(filePath.endsWith('_screen.dart') ||
          filePath.endsWith('_view.dart') ||
          filePath.endsWith('_wizard.dart') ||
          filePath.endsWith('_dialog.dart'))) {
        continue;
      }

      final classes = <String>{...signal.screens, ...signal.widgets};
      final boundRoutes = <String>{
        for (final className in classes) ...?routePathsByClass[className],
      }.toList()..sort();

      final absoluteTransitions =
          signal.navigationTransitions
              .where((route) => route.startsWith('/'))
              .toList()
            ..sort();

      final coverageCount = coveredCounts[filePath] ?? 0;
      final isDirectRouteEntry = classes.any(routedClasses.contains);
      final needsReview =
          coverageCount == 0 &&
          (signal.uiActions.isNotEmpty || boundRoutes.isNotEmpty);

      entries.add(
        _ScreenAuditEntry(
          filePath: filePath,
          moduleKey: signal.moduleKey,
          routeBound: isDirectRouteEntry,
          routePaths: boundRoutes,
          pathCount: coverageCount,
          actionCount: signal.uiActions.length,
          absoluteTransitions: absoluteTransitions,
          reviewReason: _reviewReason(
            pathCount: coverageCount,
            routeBound: isDirectRouteEntry,
            signal: signal,
            absoluteTransitions: absoluteTransitions,
          ),
          needsReview: needsReview,
        ),
      );
    }

    entries.sort((a, b) => a.filePath.compareTo(b.filePath));

    final uncovered = entries.where((entry) => entry.pathCount == 0).toList();
    final review = entries.where((entry) => entry.needsReview).toList();

    final buffer = StringBuffer();
    buffer.writeln('# Screen Audit (${model.mode.value})');
    buffer.writeln();
    buffer.writeln('- Audited presentation files: `${entries.length}`');
    buffer.writeln(
      '- Covered by inferred paths: `${entries.where((e) => e.pathCount > 0).length}`',
    );
    buffer.writeln('- Uncovered presentation files: `${uncovered.length}`');
    buffer.writeln('- Needs manual/generator review: `${review.length}`');
    buffer.writeln();

    if (review.isNotEmpty) {
      buffer.writeln('## Review Queue');
      buffer.writeln();
      for (final entry in review) {
        buffer.writeln('- `${entry.filePath}` -> ${entry.reviewReason}');
      }
      buffer.writeln();
    }

    buffer.writeln('## Inventory');
    buffer.writeln();
    for (final entry in entries) {
      buffer.writeln('### `${entry.filePath}`');
      buffer.writeln();
      buffer.writeln('- Module: `${entry.moduleKey}`');
      buffer.writeln('- Route-bound: `${entry.routeBound ? 'yes' : 'no'}`');
      buffer.writeln('- Bound routes: ${_asInlineList(entry.routePaths)}');
      buffer.writeln('- Inferred paths: `${entry.pathCount}`');
      buffer.writeln('- UI actions: `${entry.actionCount}`');
      buffer.writeln(
        '- Absolute transitions: ${_asInlineList(entry.absoluteTransitions)}',
      );
      buffer.writeln('- Review reason: ${entry.reviewReason}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _renderJourneyDiff(JourneyDiffReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# Journey Diff Report');
    buffer.writeln();
    buffer.writeln('- Entries: `${report.entries.length}`');
    buffer.writeln(
      '- Old covered / new missed: `${report.oldCoveredNewMissed.length}`',
    );
    buffer.writeln(
      '- Contradictory outcomes: `${report.contradictory.length}`',
    );
    buffer.writeln(
      '- No-regression modules: ${report.noRegressionModules.map((item) => '`$item`').join(', ')}',
    );
    buffer.writeln();

    if (report.oldCoveredNewMissed.isNotEmpty) {
      buffer.writeln('## Old Covered, New Missed');
      buffer.writeln();
      for (final entry in report.oldCoveredNewMissed) {
        buffer.writeln(
          '- `${entry.journeyId}` bucket `${entry.bucket.value}` expected `${entry.expectedOutcome.name}`${entry.reason == null ? '' : ' - ${entry.reason}'}',
        );
      }
      buffer.writeln();
    }

    if (report.contradictory.isNotEmpty) {
      buffer.writeln('## Contradictory Outcomes');
      buffer.writeln();
      for (final entry in report.contradictory) {
        buffer.writeln(
          '- `${entry.journeyId}` expected `${entry.expectedOutcome.name}`${entry.reason == null ? '' : ' - ${entry.reason}'}',
        );
      }
      buffer.writeln();
    }

    if (report.oldCoveredNewMissed.isEmpty && report.contradictory.isEmpty) {
      buffer.writeln(
        'No regressions or contradictory outcomes were detected in the current journey diff snapshot.',
      );
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _reviewReason({
    required int pathCount,
    required bool routeBound,
    required FileSignals signal,
    required List<String> absoluteTransitions,
  }) {
    if (pathCount > 0) {
      return 'covered';
    }
    if (routeBound) {
      return 'route-bound screen without inferred journeys';
    }
    if (absoluteTransitions.isNotEmpty) {
      return 'reachable via screen/view action but not yet modeled as journey entry';
    }
    if (signal.uiActions.isNotEmpty) {
      return 'interactive presentation file without deterministic route binding';
    }
    return 'non-interactive or purely supporting presentation file';
  }

  String _asInlineList(List<String> values) {
    if (values.isEmpty) {
      return 'none';
    }
    return values.map((value) => '`$value`').join(', ');
  }

  void _writeIfChanged({required String path, required String content}) {
    final file = File('$repoRoot/$path');
    file.parent.createSync(recursive: true);
    if (file.existsSync()) {
      final current = file.readAsStringSync();
      if (current == content) {
        return;
      }
    }
    file.writeAsStringSync(content);
  }
}

class _ScreenAuditEntry {
  const _ScreenAuditEntry({
    required this.filePath,
    required this.moduleKey,
    required this.routeBound,
    required this.routePaths,
    required this.pathCount,
    required this.actionCount,
    required this.absoluteTransitions,
    required this.reviewReason,
    required this.needsReview,
  });

  final String filePath;
  final String moduleKey;
  final bool routeBound;
  final List<String> routePaths;
  final int pathCount;
  final int actionCount;
  final List<String> absoluteTransitions;
  final String reviewReason;
  final bool needsReview;
}
