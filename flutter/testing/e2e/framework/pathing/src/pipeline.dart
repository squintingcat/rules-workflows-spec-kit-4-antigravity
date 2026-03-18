import 'dart:collection';

import '../../explorer/src/coverage_feedback.dart';
import 'dart_project_analyzer.dart';
import 'documentation_analyzer.dart';
import 'ground_truth_builder.dart';
import 'journey_classifier.dart';
import 'journey_diff_builder.dart';
import 'coverage_reference_builder.dart';
import 'models.dart';
import 'path_inference.dart';
import 'path_utils.dart';
import 'report_writer.dart';
import 'router_analyzer.dart';
import 'scope_resolver.dart';

class PipelineResult {
  PipelineResult({
    required this.model,
    required this.reportFiles,
    required this.emittedTargets,
  });

  final AnalysisModel model;
  final Map<String, String> reportFiles;
  final List<String> emittedTargets;
}

class E2EPathingPipeline {
  E2EPathingPipeline({
    required this.repoRoot,
    this.reportOutputDirectory = '.ciReport/e2e_pathing',
  });

  final String repoRoot;
  final String reportOutputDirectory;

  PipelineResult run({
    required AnalysisMode mode,
    Map<String, JourneyClassification> journeyOverrides = const {},
  }) {
    final scope = ScopeResolver(repoRoot: repoRoot).resolve(mode);

    final moduleKeys = scope.productionFiles.map(moduleKeyFromPath).toSet();
    final fullDocFiles = <String>{
      ...scope.documentationFiles,
      if (scope.mode == AnalysisMode.full) ...<String>{'README.md'},
    };

    final documentationSignals = DocumentationAnalyzer(repoRoot: repoRoot)
        .analyze(
          documentationFiles: fullDocFiles.toList(),
          knownModuleKeys: moduleKeys,
        );

    final fileSignals = DartProjectAnalyzer(repoRoot: repoRoot).analyze(
      productionFiles: scope.productionFiles,
      documentationSignals: documentationSignals,
    );
    final routeBindings = RouteBindingAnalyzer(repoRoot: repoRoot).analyze();
    final groundTruth = GroundTruthBuilder().build(
      fileSignals: fileSignals,
      routeBindings: routeBindings,
    );

    final paths = PathInferer().infer(
      fileSignals: fileSignals,
      documentationSignals: documentationSignals,
      routeBindings: routeBindings,
    );
    final journeyClassifications = JourneyClassifier().classify(
      paths,
      overrides: journeyOverrides,
    );

    final baseline = CoverageReferenceBuilder().build(
      userPaths: paths,
      blockedPathReasons: const <String, List<String>>{},
    );

    final journeyDiffReport = JourneyDiffBuilder().build(
      classifications: journeyClassifications,
      pathToCoverageReferences: baseline.pathToCoverageReferences,
    );
    final coverageGap = CoverageFeedback().compute(
      groundTruth: groundTruth,
      explorationResult: ExplorationResult(
        screens: const <VisitedScreen>[],
        interactions: const <TestedInteraction>[],
        defects: const <FoundDefect>[],
        totalDuration: Duration.zero,
        visitedRoutes: const <String>{},
        unreachableRoutes: groundTruth.routes
            .map((route) => route.path)
            .toSet(),
      ),
    );

    final summary = _buildSummary(
      mode: mode,
      analyzedFileCount: scope.productionFiles.length,
      paths: paths,
      coverageReferences: baseline.coverageReferences,
      pathToCoverageReferences: baseline.pathToCoverageReferences,
      blockedPathReasons: const <String, List<String>>{},
      documentationSignals: documentationSignals,
    );

    final model = AnalysisModel(
      mode: mode,
      analyzedFiles: scope.productionFiles,
      deletedFilesInScope: scope.deletedProductionFiles,
      documentationSignals: documentationSignals,
      fileSignals: fileSignals,
      routeBindings: routeBindings,
      userPaths: paths,
      coverageReferences: baseline.coverageReferences,
      pathToCoverageReferences: baseline.pathToCoverageReferences,
      coverageReferenceToPaths: baseline.coverageReferenceToPaths,
      blockedPathReasons: const <String, List<String>>{},
      parityMapping: baseline.parityMapping,
      summary: summary,
      groundTruth: groundTruth,
      coverageGap: coverageGap,
      journeyClassifications: journeyClassifications,
      journeyDiffReport: journeyDiffReport,
    );

    final reportFiles = ReportWriter(
      repoRoot: repoRoot,
      outputDirectory: reportOutputDirectory,
    ).write(model);

    return PipelineResult(
      model: model,
      reportFiles: reportFiles,
      emittedTargets: const <String>[],
    );
  }

  AnalysisSummary _buildSummary({
    required AnalysisMode mode,
    required int analyzedFileCount,
    required List<UserPath> paths,
    required List<CoverageReference> coverageReferences,
    required Map<String, List<String>> pathToCoverageReferences,
    required Map<String, List<String>> blockedPathReasons,
    required DocumentationSignals documentationSignals,
  }) {
    final modulePathCount = SplayTreeMap<String, int>();
    final moduleReferenceCount = SplayTreeMap<String, int>();
    final uncertainties = <String>{};

    for (final path in paths) {
      modulePathCount[path.moduleKey] =
          (modulePathCount[path.moduleKey] ?? 0) + 1;
      if (path.confidence == 'low') {
        uncertainties.add(
          'Low-confidence path ${path.pathId}: ${path.description}',
        );
      }
      if (path.heuristicNotes.any((note) => note.contains('indirect'))) {
        uncertainties.add(
          'Indirect linkage for ${path.pathId}: no direct repository/service call in entry file.',
        );
      }
    }

    for (final test in coverageReferences) {
      final module = test.sourceFiles.isNotEmpty
          ? moduleKeyFromPath(test.sourceFiles.first)
          : 'unknown';
      moduleReferenceCount[module] = (moduleReferenceCount[module] ?? 0) + 1;
    }

    if (documentationSignals.documentationFiles.isEmpty) {
      uncertainties.add(
        'No documentation files were in scope; only AST signals were used.',
      );
    }
    if (mode == AnalysisMode.scoped && analyzedFileCount == 0) {
      uncertainties.add(
        'Scoped mode had no relevant changed production files; no new path inference possible.',
      );
    }
    if (blockedPathReasons.isNotEmpty) {
      uncertainties.add(
        'Blocked executable paths: ${blockedPathReasons.length} (see blocked_path_reasons for exact causes).',
      );
    }

    final scopeDiffHint = mode == AnalysisMode.scoped
        ? 'Scoped mode uses uncommitted changed/new files only. Logic is identical to full mode.'
        : 'Full mode scans all relevant lib/** files. Logic is identical to scoped mode.';

    final executablePathCount = paths
        .where(
          (path) =>
              (blockedPathReasons[path.pathId] ?? const <String>[]).isEmpty,
        )
        .length;
    final coveredExecutablePathCount = paths.where((path) {
      final blocked = blockedPathReasons[path.pathId] ?? const <String>[];
      final linkedTests = pathToCoverageReferences[path.pathId] ?? const <String>[];
      return blocked.isEmpty && linkedTests.isNotEmpty;
    }).length;

    return AnalysisSummary(
      mode: mode,
      analyzedFileCount: analyzedFileCount,
      pathCount: paths.length,
      executablePathCount: executablePathCount,
      coveredExecutablePathCount: coveredExecutablePathCount,
      uncoveredExecutablePathCount:
          executablePathCount - coveredExecutablePathCount,
      coverageReferenceCount: coverageReferences.length,
      modulePathCount: modulePathCount,
      moduleReferenceCount: moduleReferenceCount,
      scopeDiffHint: scopeDiffHint,
      uncertainties: uncertainties.toList(),
    );
  }
}
