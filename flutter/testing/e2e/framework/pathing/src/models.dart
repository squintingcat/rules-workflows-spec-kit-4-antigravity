import 'dart:convert';

enum AnalysisMode { scoped, full }

enum PipelineMode { generate, explore, diff }

extension AnalysisModeX on AnalysisMode {
  String get value => this == AnalysisMode.scoped ? 'scoped' : 'full';

  static AnalysisMode parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'scoped' => AnalysisMode.scoped,
      'full' => AnalysisMode.full,
      _ => throw ArgumentError('Unsupported mode: $raw (allowed: scoped|full)'),
    };
  }
}

extension PipelineModeX on PipelineMode {
  String get value => switch (this) {
    PipelineMode.generate => 'generate',
    PipelineMode.explore => 'explore',
    PipelineMode.diff => 'diff',
  };

  static PipelineMode parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'generate' => PipelineMode.generate,
      'explore' => PipelineMode.explore,
      'diff' => PipelineMode.diff,
      _ => throw ArgumentError(
        'Unsupported pipeline mode: $raw (allowed: generate|explore|diff)',
      ),
    };
  }
}

class SourceReference {
  const SourceReference({
    required this.file,
    required this.line,
    required this.column,
    required this.label,
  });

  final String file;
  final int line;
  final int column;
  final String label;

  Map<String, Object> toJson() => <String, Object>{
    'file': file,
    'line': line,
    'column': column,
    'label': label,
  };
}

class FileSignals {
  FileSignals({
    required this.filePath,
    required this.moduleKey,
    required this.featureKey,
    required this.isUiFile,
    required Set<String> screens,
    required Set<String> widgets,
    Set<String> instantiatedWidgets = const <String>{},
    required Set<String> routes,
    required Set<String> navigationTransitions,
    required Set<String> uiActions,
    required Set<String> forms,
    required Set<String> validations,
    required Set<String> guards,
    required Set<String> errorPaths,
    required Set<String> repositoryCalls,
    required Set<String> serviceCalls,
    required Set<String> stateChanges,
    required Set<String> supabaseInteractions,
    required Set<String> crudOperations,
    required Set<String> authOperations,
    required Set<String> commentHints,
    required List<SourceReference> references,
  }) : screens = _normalizeSet(screens),
       widgets = _normalizeSet(widgets),
       instantiatedWidgets = _normalizeSet(instantiatedWidgets),
       routes = _normalizeSet(routes),
       navigationTransitions = _normalizeSet(navigationTransitions),
       uiActions = _normalizeSet(uiActions),
       forms = _normalizeSet(forms),
       validations = _normalizeSet(validations),
       guards = _normalizeSet(guards),
       errorPaths = _normalizeSet(errorPaths),
       repositoryCalls = _normalizeSet(repositoryCalls),
       serviceCalls = _normalizeSet(serviceCalls),
       stateChanges = _normalizeSet(stateChanges),
       supabaseInteractions = _normalizeSet(supabaseInteractions),
       crudOperations = _normalizeSet(crudOperations),
       authOperations = _normalizeSet(authOperations),
       commentHints = _normalizeSet(commentHints),
       references = _normalizeRefs(references);

  final String filePath;
  final String moduleKey;
  final String featureKey;
  final bool isUiFile;

  final List<String> screens;
  final List<String> widgets;
  final List<String> instantiatedWidgets;
  final List<String> routes;
  final List<String> navigationTransitions;
  final List<String> uiActions;
  final List<String> forms;
  final List<String> validations;
  final List<String> guards;
  final List<String> errorPaths;
  final List<String> repositoryCalls;
  final List<String> serviceCalls;
  final List<String> stateChanges;
  final List<String> supabaseInteractions;
  final List<String> crudOperations;
  final List<String> authOperations;
  final List<String> commentHints;
  final List<SourceReference> references;

  bool get hasActionableUi =>
      isUiFile ||
      screens.isNotEmpty ||
      widgets.isNotEmpty ||
      routes.isNotEmpty ||
      uiActions.isNotEmpty ||
      forms.isNotEmpty;

  Map<String, Object> toJson() => <String, Object>{
    'file_path': filePath,
    'module_key': moduleKey,
    'feature_key': featureKey,
    'is_ui_file': isUiFile,
    'screens': screens,
    'widgets': widgets,
    'instantiated_widgets': instantiatedWidgets,
    'routes': routes,
    'navigation_transitions': navigationTransitions,
    'ui_actions': uiActions,
    'forms': forms,
    'validations': validations,
    'guards': guards,
    'error_paths': errorPaths,
    'repository_calls': repositoryCalls,
    'service_calls': serviceCalls,
    'state_changes': stateChanges,
    'supabase_interactions': supabaseInteractions,
    'crud_operations': crudOperations,
    'auth_operations': authOperations,
    'comment_hints': commentHints,
    'references': references.map((ref) => ref.toJson()).toList(),
  };
}

class PathStep {
  const PathStep({
    required this.kind,
    required this.description,
    required this.sourceReference,
  });

  final String kind;
  final String description;
  final SourceReference sourceReference;

  Map<String, Object> toJson() => <String, Object>{
    'kind': kind,
    'description': description,
    'source_reference': sourceReference.toJson(),
  };
}

class UserPath {
  UserPath({
    required this.pathId,
    required this.moduleKey,
    required this.featureKey,
    required this.variant,
    required this.confidence,
    required this.outcomeClass,
    required this.description,
    required List<String> sourceFiles,
    required List<PathStep> steps,
    required List<String> guards,
    required List<String> validations,
    required List<String> errors,
    required List<String> supabaseInteractions,
    required List<String> heuristicNotes,
    required this.parityKey,
    required this.primarySourceFile,
  }) : sourceFiles = _normalizeSet(sourceFiles.toSet()),
       steps = _normalizeSteps(steps),
       guards = _normalizeSet(guards.toSet()),
       validations = _normalizeSet(validations.toSet()),
       errors = _normalizeSet(errors.toSet()),
       supabaseInteractions = _normalizeSet(supabaseInteractions.toSet()),
       heuristicNotes = _normalizeSet(heuristicNotes.toSet());

  final String pathId;
  final String moduleKey;
  final String featureKey;
  final String variant;
  final String confidence;
  final String outcomeClass;
  final String description;
  final List<String> sourceFiles;
  final List<PathStep> steps;
  final List<String> guards;
  final List<String> validations;
  final List<String> errors;
  final List<String> supabaseInteractions;
  final List<String> heuristicNotes;
  final String parityKey;
  final String primarySourceFile;

  Map<String, Object> toJson() => <String, Object>{
    'path_id': pathId,
    'module_key': moduleKey,
    'feature_key': featureKey,
    'variant': variant,
    'confidence': confidence,
    'outcome_class': outcomeClass,
    'description': description,
    'source_files': sourceFiles,
    'steps': steps.map((step) => step.toJson()).toList(),
    'guards': guards,
    'validations': validations,
    'errors': errors,
    'supabase_interactions': supabaseInteractions,
    'heuristic_notes': heuristicNotes,
    'parity_key': parityKey,
    'primary_source_file': primarySourceFile,
  };
}

class CoverageReference {
  CoverageReference({
    required this.referenceId,
    required this.referenceTarget,
    required this.variant,
    required this.title,
    required List<String> pathIds,
    required List<String> sourceFiles,
    required this.parityKey,
    required List<Map<String, String>> parameters,
  }) : pathIds = _normalizeSet(pathIds.toSet()),
       sourceFiles = _normalizeSet(sourceFiles.toSet()),
       parameters = _normalizeParameters(parameters);

  final String referenceId;
  final String referenceTarget;
  final String variant;
  final String title;
  final List<String> pathIds;
  final List<String> sourceFiles;
  final String parityKey;
  final List<Map<String, String>> parameters;

  Map<String, Object> toJson() => <String, Object>{
    'reference_id': referenceId,
    'reference_target': referenceTarget,
    'variant': variant,
    'title': title,
    'path_ids': pathIds,
    'source_files': sourceFiles,
    'parity_key': parityKey,
    'parameters': parameters,
  };
}

class DocumentationSignals {
  DocumentationSignals({
    required Map<String, List<String>> moduleHints,
    required Map<String, List<String>> moduleRoutes,
    required List<String> globalHints,
    required List<String> documentationFiles,
  }) : moduleHints = _normalizeMap(moduleHints),
       moduleRoutes = _normalizeMap(moduleRoutes),
       globalHints = _normalizeSet(globalHints.toSet()),
       documentationFiles = _normalizeSet(documentationFiles.toSet());

  final Map<String, List<String>> moduleHints;
  final Map<String, List<String>> moduleRoutes;
  final List<String> globalHints;
  final List<String> documentationFiles;

  Map<String, Object> toJson() => <String, Object>{
    'module_hints': moduleHints,
    'module_routes': moduleRoutes,
    'global_hints': globalHints,
    'documentation_files': documentationFiles,
  };
}

class RouteGroundTruth {
  RouteGroundTruth({
    required this.path,
    required this.screen,
    required this.authRequired,
    required this.hasForm,
    required List<String> guards,
    required this.parent,
    required List<String> subjourneys,
    required List<String> sequentialTransitions,
    required List<String> interactiveElements,
  }) : guards = _normalizeSet(guards.toSet()),
       subjourneys = _normalizeSet(subjourneys.toSet()),
       sequentialTransitions = _normalizeSet(sequentialTransitions.toSet()),
       interactiveElements = _normalizeSet(interactiveElements.toSet());

  final String path;
  final String screen;
  final bool authRequired;
  final bool hasForm;
  final List<String> guards;
  final String? parent;
  final List<String> subjourneys;
  final List<String> sequentialTransitions;
  final List<String> interactiveElements;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'screen': screen,
    'auth_required': authRequired,
    'has_form': hasForm,
    'guards': guards,
    'parent': parent,
    'subjourneys': subjourneys,
    'sequential_transitions': sequentialTransitions,
    'interactive_elements': interactiveElements,
  };

  factory RouteGroundTruth.fromJson(Map<String, Object?> json) {
    return RouteGroundTruth(
      path: json['path'] as String? ?? '',
      screen: json['screen'] as String? ?? '',
      authRequired: json['auth_required'] as bool? ?? false,
      hasForm: json['has_form'] as bool? ?? false,
      guards: _stringListFromDynamic(json['guards']),
      parent: json['parent'] as String?,
      subjourneys: _stringListFromDynamic(json['subjourneys']),
      sequentialTransitions: _stringListFromDynamic(
        json['sequential_transitions'],
      ),
      interactiveElements: _stringListFromDynamic(json['interactive_elements']),
    );
  }
}

class GroundTruthModel {
  GroundTruthModel({
    required List<RouteGroundTruth> routes,
    required List<String> entryScreens,
    required List<String> guards,
    required List<String> dialogs,
    required List<String> parameterizedRouteFamilies,
    required this.totalInteractiveElements,
    required this.formSubmits,
  }) : routes = _normalizeGroundTruthRoutes(routes),
       entryScreens = _normalizeSet(entryScreens.toSet()),
       guards = _normalizeSet(guards.toSet()),
       dialogs = _normalizeSet(dialogs.toSet()),
       parameterizedRouteFamilies = _normalizeSet(
         parameterizedRouteFamilies.toSet(),
       );

  final List<RouteGroundTruth> routes;
  final List<String> entryScreens;
  final List<String> guards;
  final List<String> dialogs;
  final List<String> parameterizedRouteFamilies;
  final int totalInteractiveElements;
  final int formSubmits;

  int get totalRoutes => routes.length;

  Map<String, Object> toJson() => <String, Object>{
    'routes': routes.map((route) => route.toJson()).toList(),
    'entry_screens': entryScreens,
    'guards': guards,
    'dialogs': dialogs,
    'parameterized_route_families': parameterizedRouteFamilies,
    'total_routes': totalRoutes,
    'total_interactive_elements': totalInteractiveElements,
    'form_submits': formSubmits,
  };

  factory GroundTruthModel.fromJson(Map<String, Object?> json) {
    return GroundTruthModel(
      routes: _mapListFromDynamic(
        json['routes'],
        (item) => RouteGroundTruth.fromJson(item),
      ),
      entryScreens: _stringListFromDynamic(json['entry_screens']),
      guards: _stringListFromDynamic(json['guards']),
      dialogs: _stringListFromDynamic(json['dialogs']),
      parameterizedRouteFamilies: _stringListFromDynamic(
        json['parameterized_route_families'],
      ),
      totalInteractiveElements: json['total_interactive_elements'] as int? ?? 0,
      formSubmits: json['form_submits'] as int? ?? 0,
    );
  }
}

enum BehaviorExpectation {
  validationErrorOnEmptyRequired,
  feedbackAfterSubmit,
  navigationOnListItemTap,
  navigationOnCTATap,
  contentChangeOnTabSwitch,
  previousRouteOnBack,
  appStaysAlive,
}

enum InteractionOutcome {
  navigationOccurred,
  dialogOpened,
  snackBarShown,
  validationError,
  contentChanged,
  loadingStarted,
  noVisibleChange,
  crash,
  timeout,
}

enum DefectSeverity { crash, timeout, unexpectedState, behaviorViolation }

class BehaviorAssertion {
  const BehaviorAssertion({
    required this.expectation,
    required this.passed,
    this.failureReason,
  });

  final BehaviorExpectation expectation;
  final bool passed;
  final String? failureReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'expectation': expectation.name,
    'passed': passed,
    'failure_reason': failureReason,
  };

  factory BehaviorAssertion.fromJson(Map<String, Object?> json) {
    return BehaviorAssertion(
      expectation: BehaviorExpectation.values.byName(
        json['expectation'] as String? ??
            BehaviorExpectation.appStaysAlive.name,
      ),
      passed: json['passed'] as bool? ?? false,
      failureReason: json['failure_reason'] as String?,
    );
  }
}

class DiscoveredWidget {
  const DiscoveredWidget({
    required this.widgetType,
    this.label,
    this.semanticsLabel,
    this.wasTested = false,
  });

  final String widgetType;
  final String? label;
  final String? semanticsLabel;
  final bool wasTested;

  Map<String, Object?> toJson() => <String, Object?>{
    'widget_type': widgetType,
    'label': label,
    'semantics_label': semanticsLabel,
    'was_tested': wasTested,
  };

  factory DiscoveredWidget.fromJson(Map<String, Object?> json) {
    return DiscoveredWidget(
      widgetType: json['widget_type'] as String? ?? 'unknown',
      label: json['label'] as String?,
      semanticsLabel: json['semantics_label'] as String?,
      wasTested: json['was_tested'] as bool? ?? false,
    );
  }
}

class VisitedScreen {
  VisitedScreen({
    required this.route,
    required List<DiscoveredWidget> interactiveWidgets,
    required this.visitedAt,
    required this.hasContent,
  }) : interactiveWidgets = interactiveWidgets.toList();

  final String route;
  final List<DiscoveredWidget> interactiveWidgets;
  final DateTime visitedAt;
  final bool hasContent;

  Map<String, Object> toJson() => <String, Object>{
    'route': route,
    'interactive_widgets': interactiveWidgets
        .map((item) => item.toJson())
        .toList(),
    'visited_at': visitedAt.toIso8601String(),
    'has_content': hasContent,
  };

  factory VisitedScreen.fromJson(Map<String, Object?> json) {
    return VisitedScreen(
      route: json['route'] as String? ?? '',
      interactiveWidgets: _mapListFromDynamic(
        json['interactive_widgets'],
        (item) => DiscoveredWidget.fromJson(item),
      ),
      visitedAt:
          DateTime.tryParse(json['visited_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hasContent: json['has_content'] as bool? ?? false,
    );
  }
}

class OutcomeProbeResult {
  const OutcomeProbeResult({
    required this.family,
    required this.passed,
    this.journeyId,
    this.details,
  });

  final OutcomeFamily family;
  final bool passed;
  final String? journeyId;
  final String? details;

  Map<String, Object?> toJson() => <String, Object?>{
    'family': family.name,
    'passed': passed,
    'journey_id': journeyId,
    'details': details,
  };

  factory OutcomeProbeResult.fromJson(Map<String, Object?> json) {
    return OutcomeProbeResult(
      family: OutcomeFamily.values.byName(
        json['family'] as String? ?? OutcomeFamily.feedbackShown.name,
      ),
      passed: json['passed'] as bool? ?? false,
      journeyId: json['journey_id'] as String?,
      details: json['details'] as String?,
    );
  }
}

class TestedInteraction {
  const TestedInteraction({
    required this.route,
    required this.widgetType,
    required this.action,
    required this.outcome,
    required this.assertion,
    this.input,
    this.outcomeProbe,
  });

  final String route;
  final String widgetType;
  final String action;
  final String? input;
  final InteractionOutcome outcome;
  final BehaviorAssertion assertion;
  final OutcomeProbeResult? outcomeProbe;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route,
    'widget_type': widgetType,
    'action': action,
    'input': input,
    'outcome': outcome.name,
    'assertion': assertion.toJson(),
    'outcome_probe': outcomeProbe?.toJson(),
  };

  factory TestedInteraction.fromJson(Map<String, Object?> json) {
    return TestedInteraction(
      route: json['route'] as String? ?? '',
      widgetType: json['widget_type'] as String? ?? 'unknown',
      action: json['action'] as String? ?? 'unknown',
      input: json['input'] as String?,
      outcome: InteractionOutcome.values.byName(
        json['outcome'] as String? ?? InteractionOutcome.noVisibleChange.name,
      ),
      assertion: BehaviorAssertion.fromJson(
        (json['assertion'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      outcomeProbe: json['outcome_probe'] is Map
          ? OutcomeProbeResult.fromJson(
              (json['outcome_probe'] as Map).cast<String, Object?>(),
            )
          : null,
    );
  }
}

class FoundDefect {
  const FoundDefect({
    required this.route,
    required this.action,
    required this.description,
    required this.severity,
    this.violatedExpectation,
  });

  final String route;
  final String action;
  final String description;
  final DefectSeverity severity;
  final BehaviorExpectation? violatedExpectation;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route,
    'action': action,
    'description': description,
    'severity': severity.name,
    'violated_expectation': violatedExpectation?.name,
  };

  factory FoundDefect.fromJson(Map<String, Object?> json) {
    return FoundDefect(
      route: json['route'] as String? ?? '',
      action: json['action'] as String? ?? '',
      description: json['description'] as String? ?? '',
      severity: DefectSeverity.values.byName(
        json['severity'] as String? ?? DefectSeverity.unexpectedState.name,
      ),
      violatedExpectation: json['violated_expectation'] is String
          ? BehaviorExpectation.values.byName(
              json['violated_expectation'] as String,
            )
          : null,
    );
  }
}

class ExplorationResult {
  ExplorationResult({
    required List<VisitedScreen> screens,
    required List<TestedInteraction> interactions,
    required List<FoundDefect> defects,
    required this.totalDuration,
    required Set<String> visitedRoutes,
    required Set<String> unreachableRoutes,
  }) : screens = screens.toList(),
       interactions = interactions.toList(),
       defects = defects.toList(),
       visitedRoutes = _normalizeSet(visitedRoutes),
       unreachableRoutes = _normalizeSet(unreachableRoutes);

  final List<VisitedScreen> screens;
  final List<TestedInteraction> interactions;
  final List<FoundDefect> defects;
  final Duration totalDuration;
  final List<String> visitedRoutes;
  final List<String> unreachableRoutes;

  int get passedAssertions =>
      interactions.where((item) => item.assertion.passed).length;
  int get behaviorViolationCount => defects
      .where((item) => item.severity == DefectSeverity.behaviorViolation)
      .length;
  int get crashCount =>
      defects.where((item) => item.severity == DefectSeverity.crash).length;
  int get timeoutCount =>
      defects.where((item) => item.severity == DefectSeverity.timeout).length;

  Map<String, Object> toJson() => <String, Object>{
    'screens': screens.map((screen) => screen.toJson()).toList(),
    'interactions': interactions
        .map((interaction) => interaction.toJson())
        .toList(),
    'defects': defects.map((defect) => defect.toJson()).toList(),
    'total_duration_ms': totalDuration.inMilliseconds,
    'visited_routes': visitedRoutes,
    'unreachable_routes': unreachableRoutes,
    'passed_assertions': passedAssertions,
    'behavior_violations': behaviorViolationCount,
    'crashes': crashCount,
    'timeouts': timeoutCount,
  };

  factory ExplorationResult.fromJson(Map<String, Object?> json) {
    return ExplorationResult(
      screens: _mapListFromDynamic(
        json['screens'],
        (item) => VisitedScreen.fromJson(item),
      ),
      interactions: _mapListFromDynamic(
        json['interactions'],
        (item) => TestedInteraction.fromJson(item),
      ),
      defects: _mapListFromDynamic(
        json['defects'],
        (item) => FoundDefect.fromJson(item),
      ),
      totalDuration: Duration(
        milliseconds: json['total_duration_ms'] as int? ?? 0,
      ),
      visitedRoutes: _stringSetFromDynamic(json['visited_routes']),
      unreachableRoutes: _stringSetFromDynamic(json['unreachable_routes']),
    );
  }
}

enum OutcomeFamily {
  entityCreated,
  entityUpdated,
  entityDeleted,
  navigationSucceeded,
  feedbackShown,
  validationBlocked,
  sessionChanged,
  dataRecorded,
}

enum JourneyBucket { aGenericUi, bAdapterRequired, cDomainOracleRequired }

extension JourneyBucketX on JourneyBucket {
  String get value => switch (this) {
    JourneyBucket.aGenericUi => 'A',
    JourneyBucket.bAdapterRequired => 'B',
    JourneyBucket.cDomainOracleRequired => 'C',
  };
}

class JourneyClassification {
  JourneyClassification({
    required this.journeyId,
    required this.bucket,
    required this.expectedOutcome,
    required this.needsSeed,
    required this.needsOutcomeProbe,
  });

  final String journeyId;
  final JourneyBucket bucket;
  final OutcomeFamily expectedOutcome;
  final bool needsSeed;
  final bool needsOutcomeProbe;

  Map<String, Object> toJson() => <String, Object>{
    'journey_id': journeyId,
    'bucket': bucket.value,
    'expected_outcome': expectedOutcome.name,
    'needs_seed': needsSeed,
    'needs_outcome_probe': needsOutcomeProbe,
  };

  factory JourneyClassification.fromJson(Map<String, Object?> json) {
    return JourneyClassification(
      journeyId: json['journey_id'] as String? ?? '',
      bucket: JourneyBucket.values.firstWhere(
        (value) => value.value == (json['bucket'] as String? ?? 'A'),
        orElse: () => JourneyBucket.aGenericUi,
      ),
      expectedOutcome: OutcomeFamily.values.byName(
        json['expected_outcome'] as String? ?? OutcomeFamily.feedbackShown.name,
      ),
      needsSeed: json['needs_seed'] as bool? ?? false,
      needsOutcomeProbe: json['needs_outcome_probe'] as bool? ?? false,
    );
  }
}

class JourneyDiffEntry {
  JourneyDiffEntry({
    required this.journeyId,
    required this.bucket,
    required this.expectedOutcome,
    required this.oldCovered,
    required this.newCovered,
    required this.outcomeParity,
    this.reason,
  });

  final String journeyId;
  final JourneyBucket bucket;
  final OutcomeFamily expectedOutcome;
  final bool oldCovered;
  final bool newCovered;
  final bool outcomeParity;
  final String? reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'journey_id': journeyId,
    'bucket': bucket.value,
    'expected_outcome': expectedOutcome.name,
    'old_covered': oldCovered,
    'new_covered': newCovered,
    'outcome_parity': outcomeParity,
    'reason': reason,
  };
}

class JourneyDiffReport {
  JourneyDiffReport({
    required List<JourneyDiffEntry> entries,
    required List<String> noRegressionModules,
  }) : entries = entries.toList(),
       noRegressionModules = _normalizeSet(noRegressionModules.toSet());

  final List<JourneyDiffEntry> entries;
  final List<String> noRegressionModules;

  List<JourneyDiffEntry> get oldCoveredNewMissed =>
      entries.where((entry) => entry.oldCovered && !entry.newCovered).toList();
  List<JourneyDiffEntry> get contradictory => entries
      .where(
        (entry) => entry.oldCovered && entry.newCovered && !entry.outcomeParity,
      )
      .toList();

  Map<String, Object> toJson() => <String, Object>{
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'old_covered_new_missed': oldCoveredNewMissed
        .map((entry) => entry.toJson())
        .toList(),
    'contradictory': contradictory.map((entry) => entry.toJson()).toList(),
    'no_regression_modules': noRegressionModules,
  };
}

class CoverageGap {
  CoverageGap({
    required this.routeCoverage,
    required this.elementCoverage,
    required this.formCoverage,
    required this.guardCoverage,
    required List<String> missedRoutes,
    required List<String> missedSubjourneys,
    required List<String> prioritizedHints,
  }) : missedRoutes = _normalizeSet(missedRoutes.toSet()),
       missedSubjourneys = _normalizeSet(missedSubjourneys.toSet()),
       prioritizedHints = _normalizeSet(prioritizedHints.toSet());

  final double routeCoverage;
  final double elementCoverage;
  final double formCoverage;
  final double guardCoverage;
  final List<String> missedRoutes;
  final List<String> missedSubjourneys;
  final List<String> prioritizedHints;

  Map<String, Object> toJson() => <String, Object>{
    'route_coverage': routeCoverage,
    'element_coverage': elementCoverage,
    'form_coverage': formCoverage,
    'guard_coverage': guardCoverage,
    'missed_routes': missedRoutes,
    'missed_subjourneys': missedSubjourneys,
    'prioritized_hints': prioritizedHints,
  };

  factory CoverageGap.fromJson(Map<String, Object?> json) {
    return CoverageGap(
      routeCoverage: (json['route_coverage'] as num?)?.toDouble() ?? 0,
      elementCoverage: (json['element_coverage'] as num?)?.toDouble() ?? 0,
      formCoverage: (json['form_coverage'] as num?)?.toDouble() ?? 0,
      guardCoverage: (json['guard_coverage'] as num?)?.toDouble() ?? 0,
      missedRoutes: _stringListFromDynamic(json['missed_routes']),
      missedSubjourneys: _stringListFromDynamic(json['missed_subjourneys']),
      prioritizedHints: _stringListFromDynamic(json['prioritized_hints']),
    );
  }
}

String normalizeRoutePath(String route) {
  final trimmed = route.trim();
  if (trimmed.isEmpty) {
    return '/';
  }
  final withoutQuery = trimmed.split('?').first.split('#').first.trim();
  if (withoutQuery.isEmpty || withoutQuery == '/') {
    return '/';
  }
  final normalized = withoutQuery.startsWith('/')
      ? withoutQuery
      : '/$withoutQuery';
  if (normalized.length > 1 && normalized.endsWith('/')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool routePatternMatches(
  String pattern,
  String actual, {
  bool allowChildSegments = false,
}) {
  final normalizedPattern = normalizeRoutePath(pattern);
  final normalizedActual = normalizeRoutePath(actual);
  if (normalizedPattern == normalizedActual) {
    return true;
  }

  final patternSegments = _routeSegments(normalizedPattern);
  final actualSegments = _routeSegments(normalizedActual);
  if (patternSegments.isEmpty) {
    return actualSegments.isEmpty;
  }

  if (allowChildSegments) {
    if (actualSegments.length < patternSegments.length) {
      return false;
    }
  } else if (patternSegments.length != actualSegments.length) {
    return false;
  }

  for (var index = 0; index < patternSegments.length; index += 1) {
    final patternSegment = patternSegments[index];
    final actualSegment = actualSegments[index];
    if (patternSegment.startsWith(':')) {
      if (actualSegment.isEmpty) {
        return false;
      }
      continue;
    }
    if (patternSegment != actualSegment) {
      return false;
    }
  }

  return allowChildSegments || patternSegments.length == actualSegments.length;
}

List<String> _routeSegments(String route) {
  return normalizeRoutePath(
    route,
  ).split('/').where((segment) => segment.isNotEmpty).toList(growable: false);
}

class AnalysisSummary {
  AnalysisSummary({
    required this.mode,
    required this.analyzedFileCount,
    required this.pathCount,
    required this.executablePathCount,
    required this.coveredExecutablePathCount,
    required this.uncoveredExecutablePathCount,
    required this.coverageReferenceCount,
    required this.modulePathCount,
    required this.moduleReferenceCount,
    required this.scopeDiffHint,
    required List<String> uncertainties,
    this.explorerVisitedRouteCount = 0,
    this.explorerAssertionCount = 0,
    this.explorerBehaviorViolationCount = 0,
  }) : uncertainties = _normalizeSet(uncertainties.toSet());

  final AnalysisMode mode;
  final int analyzedFileCount;
  final int pathCount;
  final int executablePathCount;
  final int coveredExecutablePathCount;
  final int uncoveredExecutablePathCount;
  final int coverageReferenceCount;
  final Map<String, int> modulePathCount;
  final Map<String, int> moduleReferenceCount;
  final String scopeDiffHint;
  final List<String> uncertainties;
  final int explorerVisitedRouteCount;
  final int explorerAssertionCount;
  final int explorerBehaviorViolationCount;

  double get journeyCoveragePercent {
    if (executablePathCount == 0) {
      return 100.0;
    }
    return (coveredExecutablePathCount / executablePathCount) * 100.0;
  }

  Map<String, Object> toJson() => <String, Object>{
    'mode': mode.value,
    'analyzed_file_count': analyzedFileCount,
    'path_count': pathCount,
    'executable_path_count': executablePathCount,
    'covered_executable_path_count': coveredExecutablePathCount,
    'uncovered_executable_path_count': uncoveredExecutablePathCount,
    'journey_coverage_percent': journeyCoveragePercent,
    'coverage_reference_count': coverageReferenceCount,
    'module_path_count': modulePathCount,
    'module_reference_count': moduleReferenceCount,
    'scope_diff_hint': scopeDiffHint,
    'uncertainties': uncertainties,
    'explorer_visited_route_count': explorerVisitedRouteCount,
    'explorer_assertion_count': explorerAssertionCount,
    'explorer_behavior_violation_count': explorerBehaviorViolationCount,
  };
}

class AnalysisModel {
  AnalysisModel({
    required this.mode,
    required List<String> analyzedFiles,
    required List<String> deletedFilesInScope,
    required this.documentationSignals,
    required List<FileSignals> fileSignals,
    required this.routeBindings,
    required List<UserPath> userPaths,
    required List<CoverageReference> coverageReferences,
    required this.pathToCoverageReferences,
    required this.coverageReferenceToPaths,
    required Map<String, List<String>> blockedPathReasons,
    required this.parityMapping,
    required this.summary,
    this.groundTruth,
    this.explorationResult,
    this.coverageGap,
    required List<JourneyClassification> journeyClassifications,
    this.journeyDiffReport,
  }) : analyzedFiles = _normalizeSet(analyzedFiles.toSet()),
       deletedFilesInScope = _normalizeSet(deletedFilesInScope.toSet()),
       fileSignals = _normalizeFileSignals(fileSignals),
       userPaths = _normalizeUserPaths(userPaths),
       coverageReferences = _normalizeCoverageReferences(coverageReferences),
       blockedPathReasons = _normalizeMap(blockedPathReasons),
       journeyClassifications = _normalizeJourneyClassifications(
         journeyClassifications,
       );

  final AnalysisMode mode;
  final List<String> analyzedFiles;
  final List<String> deletedFilesInScope;
  final DocumentationSignals documentationSignals;
  final List<FileSignals> fileSignals;
  final Map<String, List<String>> routeBindings;
  final List<UserPath> userPaths;
  final List<CoverageReference> coverageReferences;
  final Map<String, List<String>> pathToCoverageReferences;
  final Map<String, List<String>> coverageReferenceToPaths;
  final Map<String, List<String>> blockedPathReasons;
  final Map<String, String> parityMapping;
  final AnalysisSummary summary;
  final GroundTruthModel? groundTruth;
  final ExplorationResult? explorationResult;
  final CoverageGap? coverageGap;
  final List<JourneyClassification> journeyClassifications;
  final JourneyDiffReport? journeyDiffReport;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.value,
    'analyzed_files': analyzedFiles,
    'deleted_files_in_scope': deletedFilesInScope,
    'documentation_signals': documentationSignals.toJson(),
    'file_signals': fileSignals.map((item) => item.toJson()).toList(),
    'route_bindings': routeBindings,
    'user_paths': userPaths.map((item) => item.toJson()).toList(),
    'coverage_references': coverageReferences.map((item) => item.toJson()).toList(),
    'path_to_coverage_references': pathToCoverageReferences,
    'coverage_reference_to_paths': coverageReferenceToPaths,
    'blocked_path_reasons': blockedPathReasons,
    'parity_mapping': parityMapping,
    'summary': summary.toJson(),
    'ground_truth': groundTruth?.toJson(),
    'exploration_result': explorationResult?.toJson(),
    'coverage_gap': coverageGap?.toJson(),
    'journey_classifications': journeyClassifications
        .map((item) => item.toJson())
        .toList(),
    'journey_diff_report': journeyDiffReport?.toJson(),
  };

  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }
}

class ScopeSelection {
  ScopeSelection({
    required this.mode,
    required List<String> productionFiles,
    required List<String> documentationFiles,
    required List<String> deletedProductionFiles,
    required List<String> rawChangedFiles,
  }) : productionFiles = _normalizeSet(productionFiles.toSet()),
       documentationFiles = _normalizeSet(documentationFiles.toSet()),
       deletedProductionFiles = _normalizeSet(deletedProductionFiles.toSet()),
       rawChangedFiles = _normalizeSet(rawChangedFiles.toSet());

  final AnalysisMode mode;
  final List<String> productionFiles;
  final List<String> documentationFiles;
  final List<String> deletedProductionFiles;
  final List<String> rawChangedFiles;

  Map<String, Object> toJson() => <String, Object>{
    'mode': mode.value,
    'production_files': productionFiles,
    'documentation_files': documentationFiles,
    'deleted_production_files': deletedProductionFiles,
    'raw_changed_files': rawChangedFiles,
  };
}

List<String> _normalizeSet(Set<String> values) {
  final normalized =
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return normalized;
}

List<String> _stringListFromDynamic(Object? raw) {
  if (raw is! List) {
    return const <String>[];
  }
  return raw
      .whereType<Object?>()
      .map((value) => value?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toList();
}

Set<String> _stringSetFromDynamic(Object? raw) {
  return _stringListFromDynamic(raw).toSet();
}

List<T> _mapListFromDynamic<T>(
  Object? raw,
  T Function(Map<String, Object?> item) mapper,
) {
  if (raw is! List) {
    return <T>[];
  }
  return raw
      .whereType<Map>()
      .map((item) => mapper(item.cast<String, Object?>()))
      .toList();
}

List<SourceReference> _normalizeRefs(List<SourceReference> values) {
  final dedup = <String, SourceReference>{};
  for (final ref in values) {
    final key = '${ref.file}|${ref.line}|${ref.column}|${ref.label}';
    dedup[key] = ref;
  }
  final normalized = dedup.values.toList()
    ..sort((a, b) {
      final file = a.file.compareTo(b.file);
      if (file != 0) return file;
      final line = a.line.compareTo(b.line);
      if (line != 0) return line;
      final column = a.column.compareTo(b.column);
      if (column != 0) return column;
      return a.label.compareTo(b.label);
    });
  return normalized;
}

List<PathStep> _normalizeSteps(List<PathStep> values) {
  final dedup = <String, PathStep>{};
  for (final step in values) {
    final ref = step.sourceReference;
    final key =
        '${step.kind}|${step.description}|${ref.file}|${ref.line}|${ref.column}|${ref.label}';
    dedup.putIfAbsent(key, () => step);
  }
  return dedup.values.toList();
}

List<Map<String, String>> _normalizeParameters(
  List<Map<String, String>> values,
) {
  final dedup = <String, Map<String, String>>{};
  for (final map in values) {
    final normalized = <String, String>{};
    final keys = map.keys.toList()..sort();
    for (final key in keys) {
      normalized[key] = map[key] ?? '';
    }
    final key = normalized.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('|');
    dedup[key] = normalized;
  }
  final normalized = dedup.values.toList()
    ..sort((a, b) {
      final aKey = a.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('|');
      final bKey = b.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('|');
      return aKey.compareTo(bKey);
    });
  return normalized;
}

Map<String, List<String>> _normalizeMap(Map<String, List<String>> values) {
  final normalized = <String, List<String>>{};
  final keys = values.keys.toList()..sort();
  for (final key in keys) {
    normalized[key] = _normalizeSet(values[key]?.toSet() ?? <String>{});
  }
  return normalized;
}

List<FileSignals> _normalizeFileSignals(List<FileSignals> values) {
  final normalized = values.toList()
    ..sort((a, b) => a.filePath.compareTo(b.filePath));
  return normalized;
}

List<UserPath> _normalizeUserPaths(List<UserPath> values) {
  final normalized = values.toList()
    ..sort((a, b) => a.pathId.compareTo(b.pathId));
  return normalized;
}

List<CoverageReference> _normalizeCoverageReferences(
  List<CoverageReference> values,
) {
  final normalized = values.toList()
    ..sort((a, b) => a.referenceId.compareTo(b.referenceId));
  return normalized;
}

List<RouteGroundTruth> _normalizeGroundTruthRoutes(
  List<RouteGroundTruth> values,
) {
  final normalized = values.toList()..sort((a, b) => a.path.compareTo(b.path));
  return normalized;
}

List<JourneyClassification> _normalizeJourneyClassifications(
  List<JourneyClassification> values,
) {
  final normalized = values.toList()
    ..sort((a, b) => a.journeyId.compareTo(b.journeyId));
  return normalized;
}
