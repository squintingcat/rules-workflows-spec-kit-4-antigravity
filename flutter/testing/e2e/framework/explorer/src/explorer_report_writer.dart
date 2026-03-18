import 'dart:convert';
import 'dart:io';

import '../../pathing/src/models.dart';

class ExplorerReportWriter {
  ExplorerReportWriter({required this.repoRoot, required this.outputDirectory});

  final String repoRoot;
  final String outputDirectory;

  Map<String, String> write({
    required GroundTruthModel groundTruth,
    required ExplorationResult explorationResult,
    required CoverageGap coverageGap,
    required JourneyDiffReport journeyDiffReport,
    required List<JourneyClassification> journeyClassifications,
    required AnalysisMode mode,
  }) {
    final outDir = Directory('$repoRoot/$outputDirectory');
    outDir.createSync(recursive: true);

    final groundTruthFile = '$outputDirectory/ground_truth_${mode.value}.json';
    final explorationFile =
        '$outputDirectory/exploration_result_${mode.value}.json';
    final gapFile = '$outputDirectory/coverage_gap_${mode.value}.json';
    final classificationFile =
        '$outputDirectory/journey_classification_${mode.value}.json';
    final diffFile = '$outputDirectory/journey_diff_${mode.value}.json';
    final diffMarkdownFile = '$outputDirectory/journey_diff_${mode.value}.md';
    final summaryFile = '$outputDirectory/exploration_summary_${mode.value}.md';

    _write(
      groundTruthFile,
      const JsonEncoder.withIndent('  ').convert(groundTruth.toJson()),
    );
    _write(
      explorationFile,
      const JsonEncoder.withIndent('  ').convert(explorationResult.toJson()),
    );
    _write(
      gapFile,
      const JsonEncoder.withIndent('  ').convert(coverageGap.toJson()),
    );
    _write(
      classificationFile,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(journeyClassifications.map((item) => item.toJson()).toList()),
    );
    _write(
      diffFile,
      const JsonEncoder.withIndent('  ').convert(journeyDiffReport.toJson()),
    );
    _write(diffMarkdownFile, _renderJourneyDiff(journeyDiffReport));
    _write(
      summaryFile,
      _renderSummary(
        mode: mode,
        groundTruth: groundTruth,
        explorationResult: explorationResult,
        coverageGap: coverageGap,
        journeyDiffReport: journeyDiffReport,
      ),
    );

    return <String, String>{
      'ground_truth': groundTruthFile,
      'exploration_result': explorationFile,
      'coverage_gap': gapFile,
      'journey_classification': classificationFile,
      'journey_diff': diffFile,
      'journey_diff_markdown': diffMarkdownFile,
      'exploration_summary': summaryFile,
    };
  }

  void _write(String relativePath, String content) {
    final file = File('$repoRoot/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String _renderSummary({
    required AnalysisMode mode,
    required GroundTruthModel groundTruth,
    required ExplorationResult explorationResult,
    required CoverageGap coverageGap,
    required JourneyDiffReport journeyDiffReport,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# Explorer Summary (${mode.value})');
    buffer.writeln();
    buffer.writeln(
      '- Visited routes: `${explorationResult.visitedRoutes.length}`',
    );
    buffer.writeln(
      '- Interactions: `${explorationResult.interactions.length}`',
    );
    buffer.writeln(
      '- Passed assertions: `${explorationResult.passedAssertions}`',
    );
    buffer.writeln(
      '- Behavior violations: `${explorationResult.behaviorViolationCount}`',
    );
    buffer.writeln('- Crashes: `${explorationResult.crashCount}`');
    buffer.writeln('- Timeouts: `${explorationResult.timeoutCount}`');
    buffer.writeln(
      '- Route coverage: `${(coverageGap.routeCoverage * 100).toStringAsFixed(2)}%`',
    );
    buffer.writeln(
      '- Form coverage: `${(coverageGap.formCoverage * 100).toStringAsFixed(2)}%`',
    );
    buffer.writeln(
      '- Guard coverage: `${(coverageGap.guardCoverage * 100).toStringAsFixed(2)}%`',
    );
    buffer.writeln('- Ground-truth routes: `${groundTruth.totalRoutes}`');
    buffer.writeln(
      '- Old covered / new missed: `${journeyDiffReport.oldCoveredNewMissed.length}`',
    );
    buffer.writeln(
      '- Contradictory outcomes: `${journeyDiffReport.contradictory.length}`',
    );
    buffer.writeln();

    if (coverageGap.missedRoutes.isNotEmpty) {
      buffer.writeln('## Missed Routes');
      buffer.writeln();
      for (final route in coverageGap.missedRoutes) {
        buffer.writeln('- `$route`');
      }
      buffer.writeln();
    }

    if (journeyDiffReport.contradictory.isNotEmpty) {
      buffer.writeln('## Contradictory Journeys');
      buffer.writeln();
      for (final entry in journeyDiffReport.contradictory) {
        buffer.writeln(
          '- `${entry.journeyId}` expected `${entry.expectedOutcome.name}`',
        );
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _renderJourneyDiff(JourneyDiffReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# Journey Diff');
    buffer.writeln();
    buffer.writeln('- Entries: `${report.entries.length}`');
    buffer.writeln(
      '- Old covered / new missed: `${report.oldCoveredNewMissed.length}`',
    );
    buffer.writeln(
      '- Contradictory outcomes: `${report.contradictory.length}`',
    );
    buffer.writeln();

    for (final entry in report.entries) {
      buffer.writeln('## ${entry.journeyId}');
      buffer.writeln();
      buffer.writeln('- Bucket: `${entry.bucket.value}`');
      buffer.writeln('- Expected outcome: `${entry.expectedOutcome.name}`');
      buffer.writeln('- Old covered: `${entry.oldCovered}`');
      buffer.writeln('- New covered: `${entry.newCovered}`');
      buffer.writeln('- Outcome parity: `${entry.outcomeParity}`');
      if (entry.reason != null) {
        buffer.writeln('- Reason: ${entry.reason}');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}
