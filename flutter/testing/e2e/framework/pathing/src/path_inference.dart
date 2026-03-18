import 'models.dart';
import 'path_utils.dart';

class PathInferer {
  List<UserPath> infer({
    required List<FileSignals> fileSignals,
    required DocumentationSignals documentationSignals,
    required Map<String, List<String>> routeBindings,
  }) {
    final paths = <UserPath>[];
    final sortedSignals = fileSignals.toList()
      ..sort((a, b) => a.filePath.compareTo(b.filePath));
    final signalsByModule = <String, List<FileSignals>>{};
    final knownRoutes = <String>{};

    for (final signal in sortedSignals) {
      signalsByModule
          .putIfAbsent(signal.moduleKey, () => <FileSignals>[])
          .add(signal);
    }
    for (final routes in routeBindings.values) {
      knownRoutes.addAll(routes);
    }

    for (final uiSignal in sortedSignals) {
      if (!_isJourneyEntrySignal(uiSignal)) {
        continue;
      }

      final entryRoute = _resolveEntryRoute(
        signal: uiSignal,
        routeBindings: routeBindings,
      );
      if (entryRoute == null) {
        continue;
      }

      final moduleSignals =
          signalsByModule[uiSignal.moduleKey] ?? const <FileSignals>[];
      final companions = _companionSignals(
        signal: uiSignal,
        moduleSignals: moduleSignals,
        entryRoute: entryRoute,
      );
      final context = _JourneyInferenceContext(
        signal: uiSignal,
        entrySignal: uiSignal,
        companions: companions,
        sourceRef: _firstReferenceOrFallback(uiSignal),
        entryRoute: entryRoute,
        docs: _relevantDocs(
          docs:
              documentationSignals.moduleHints[uiSignal.moduleKey] ??
              const <String>[],
          signal: uiSignal,
          entryRoute: entryRoute,
        ),
        knownRoutes: knownRoutes,
        isSubview: false,
      );

      paths.addAll(_inferPathsForContext(context));
      final visitedSubviewPairs = <String>{};

      void inferEmbeddedPaths({
        required FileSignals parentSignal,
        required FileSignals rootEntrySignal,
      }) {
        for (final subviewSignal in _embeddedSubviewSignals(
          entrySignal: parentSignal,
          allSignals: sortedSignals,
        )) {
          final edgeKey = '${parentSignal.filePath}=>${subviewSignal.filePath}';
          if (!visitedSubviewPairs.add(edgeKey)) {
            continue;
          }

          final subviewModuleSignals =
              signalsByModule[subviewSignal.moduleKey] ?? const <FileSignals>[];
          final subviewCompanions = <FileSignals>{
            parentSignal,
            rootEntrySignal,
            ..._companionSignals(
              signal: subviewSignal,
              moduleSignals: subviewModuleSignals,
              entryRoute: entryRoute,
            ),
          }.toList()..sort((a, b) => a.filePath.compareTo(b.filePath));

          paths.addAll(
            _inferPathsForContext(
              _JourneyInferenceContext(
                signal: subviewSignal,
                entrySignal: parentSignal,
                companions: subviewCompanions,
                sourceRef: _firstReferenceOrFallback(subviewSignal),
                entryRoute: entryRoute,
                docs: _relevantDocs(
                  docs:
                      documentationSignals.moduleHints[subviewSignal
                          .moduleKey] ??
                      const <String>[],
                  signal: subviewSignal,
                  entryRoute: entryRoute,
                ),
                knownRoutes: knownRoutes,
                isSubview: true,
              ),
            ),
          );

          inferEmbeddedPaths(
            parentSignal: subviewSignal,
            rootEntrySignal: rootEntrySignal,
          );
        }
      }

      inferEmbeddedPaths(parentSignal: uiSignal, rootEntrySignal: uiSignal);
    }

    final deduped = <String, UserPath>{};
    for (final path in paths) {
      final key = [
        path.primarySourceFile,
        path.variant,
        path.outcomeClass,
        path.description,
        path.steps.map((step) => '${step.kind}:${step.description}').join('|'),
      ].join('::');
      deduped[key] = path;
    }

    final normalized = deduped.values.toList()
      ..sort((a, b) => a.pathId.compareTo(b.pathId));
    return normalized;
  }

  List<UserPath> _inferPathsForContext(_JourneyInferenceContext context) {
    final journeyKind = _inferJourneyKind(
      signal: context.signal,
      entryRoute: context.entryRoute,
    );
    final transitions = _semanticTransitions(context);
    final logicLinks = _logicLinks(context);
    final validations = _semanticValidations(context);
    final guards = _semanticGuards(context);
    final errors = _semanticErrors(context);
    final supabase = _semanticSupabase(context);
    final confidence = _inferConfidence(
      entryRoute: context.entryRoute,
      transitions: transitions,
      logicLinks: logicLinks,
      journeyKind: journeyKind,
    );
    final steps = _buildBaseSteps(
      context: context,
      journeyKind: journeyKind,
      transitions: transitions,
      logicLinks: logicLinks,
    );
    final sourceFiles = <String>{
      context.signal.filePath,
      ...context.companions.map((signal) => signal.filePath),
    }.toList()..sort();

    final paths = <UserPath>[];
    var index = 1;

    void addPath({
      required String idVariant,
      required String variant,
      required String outcomeClass,
      required String description,
      required List<PathStep> pathSteps,
      required List<String> heuristicNotes,
      List<String>? pathGuards,
      List<String>? pathValidations,
      List<String>? pathErrors,
    }) {
      paths.add(
        UserPath(
          pathId: _buildPathId(
            moduleKey: context.signal.moduleKey,
            sourceFile: context.signal.filePath,
            variant: idVariant,
            index: index,
          ),
          moduleKey: context.signal.moduleKey,
          featureKey: context.signal.featureKey,
          variant: variant,
          confidence: confidence,
          outcomeClass: outcomeClass,
          description: description,
          sourceFiles: sourceFiles,
          steps: pathSteps,
          guards: pathGuards ?? guards,
          validations: pathValidations ?? validations,
          errors: pathErrors ?? errors,
          supabaseInteractions: supabase,
          heuristicNotes: heuristicNotes,
          parityKey: parityKeyFromSourceFile(context.signal.filePath),
          primarySourceFile: context.signal.filePath,
        ),
      );
      index += 1;
    }

    addPath(
      idVariant: 'positive',
      variant: 'positive',
      outcomeClass: _positiveOutcomeClass(
        journeyKind: journeyKind,
        context: context,
      ),
      description: _positiveDescription(
        journeyKind: journeyKind,
        context: context,
      ),
      pathSteps: steps,
      heuristicNotes: _baseHeuristics(
        confidence: confidence,
        docs: context.docs,
        signal: context.signal,
        entrySignal: context.entrySignal,
        entryRoute: context.entryRoute,
        journeyKind: journeyKind,
        transitions: transitions,
        logicLinks: logicLinks,
        isSubview: context.isSubview,
      ),
    );

    if (_supportsValidationPath(
      journeyKind: journeyKind,
      validations: validations,
    )) {
      addPath(
        idVariant: 'negative_validation',
        variant: 'negative',
        outcomeClass: 'validation_error',
        description: _validationDescription(
          journeyKind: journeyKind,
          context: context,
        ),
        pathSteps: <PathStep>[
          ...steps,
          PathStep(
            kind: 'validation_error',
            description: _validationOutcomeDescription(journeyKind),
            sourceReference: context.sourceRef,
          ),
        ],
        heuristicNotes: <String>[
          'Derived from explicit validators and required-field checks in the journey entrypoint.',
        ],
      );
    }

    if (_supportsGuardPath(
      journeyKind: journeyKind,
      guards: guards,
      entryRoute: context.entryRoute,
    )) {
      addPath(
        idVariant: 'negative_guard',
        variant: 'negative',
        outcomeClass: 'guard_blocked',
        description: _guardDescription(
          journeyKind: journeyKind,
          context: context,
        ),
        pathSteps: <PathStep>[
          ...steps,
          PathStep(
            kind: 'guard_blocked',
            description: _guardOutcomeDescription(context.entryRoute),
            sourceReference: context.sourceRef,
          ),
        ],
        heuristicNotes: <String>[
          'Derived from auth/permission guard signals or protected route requirements.',
        ],
      );
    }

    if (_supportsBackendErrorPath(
      journeyKind: journeyKind,
      errors: errors,
      logicLinks: logicLinks,
    )) {
      addPath(
        idVariant: 'negative_error',
        variant: 'negative',
        outcomeClass: 'backend_error',
        description: _backendErrorDescription(
          journeyKind: journeyKind,
          context: context,
        ),
        pathSteps: <PathStep>[
          ...steps,
          PathStep(
            kind: 'error_outcome',
            description: _backendErrorOutcomeDescription(journeyKind),
            sourceReference: context.sourceRef,
          ),
        ],
        heuristicNotes: <String>[
          'Derived from backend call signals together with explicit catch/throw markers.',
        ],
      );
    }

    final sequence = _buildSequentialPath(
      context: context,
      journeyKind: journeyKind,
      confidence: confidence,
      sourceFiles: sourceFiles,
      steps: steps,
      guards: guards,
      validations: validations,
      errors: errors,
      supabase: supabase,
      index: index,
    );
    if (sequence != null) {
      paths.add(sequence);
    }

    return paths;
  }

  List<FileSignals> _companionSignals({
    required FileSignals signal,
    required List<FileSignals> moduleSignals,
    required String entryRoute,
  }) {
    final stem = _entryStem(signal.filePath);
    final routePrefix = _routePrefix(entryRoute);
    final companions = <FileSignals>[];

    for (final candidate in moduleSignals) {
      if (candidate.filePath == signal.filePath) {
        continue;
      }
      if (!candidate.isUiFile) {
        continue;
      }

      final candidateStem = _entryStem(candidate.filePath);
      final candidateTransitions = candidate.navigationTransitions
          .where((route) => route.trim().startsWith('/'))
          .toList();
      final candidateWidgetNames = <String>{
        ...candidate.screens,
        ...candidate.widgets,
      };
      final relatedByStem = stem.isNotEmpty && candidateStem == stem;
      final relatedByListView =
          stem.endsWith('_list') &&
          candidate.filePath.contains('/presentation/') &&
          candidate.filePath.contains('${stem}_view.dart');
      final relatedByRoute =
          routePrefix.isNotEmpty &&
          (candidate.routes.any(
                (route) => _routePrefix(route) == routePrefix,
              ) ||
              candidateTransitions.any(
                (route) => _routePrefix(route) == routePrefix,
              ));
      final candidateIsJourneyEntry = isJourneyEntryFilePath(
        candidate.filePath,
      );
      final relatedByFilePrefix =
          _primaryNoun(signal.filePath).isNotEmpty &&
          !candidateIsJourneyEntry &&
          candidate.filePath
              .split('/')
              .last
              .contains(_primaryNoun(signal.filePath));
      final relatedByInstantiation = candidateWidgetNames.any(
        signal.instantiatedWidgets.contains,
      );

      if (relatedByStem ||
          relatedByListView ||
          relatedByInstantiation ||
          (relatedByRoute && !candidateIsJourneyEntry) ||
          relatedByFilePrefix) {
        companions.add(candidate);
      }
    }

    companions.sort((a, b) => a.filePath.compareTo(b.filePath));
    return companions;
  }

  List<String> _semanticTransitions(_JourneyInferenceContext context) {
    final transitions = <String>{
      ...context.signal.navigationTransitions.where(
        (route) => route.startsWith('/'),
      ),
      for (final companion in context.companions)
        ...companion.navigationTransitions.where(
          (route) => route.startsWith('/'),
        ),
    };
    final normalized = transitions.toList()..sort();
    return normalized;
  }

  List<String> _logicLinks(_JourneyInferenceContext context) {
    final candidates = <String>{
      ...context.signal.repositoryCalls,
      ...context.signal.serviceCalls,
      ...context.signal.supabaseInteractions,
      for (final companion in context.companions) ...companion.repositoryCalls,
      for (final companion in context.companions) ...companion.serviceCalls,
      for (final companion in context.companions)
        ...companion.supabaseInteractions,
      ...context.signal.stateChanges.where((change) => change.contains('.')),
    };
    final filtered = candidates.where(_isSemanticLogicLink).toList()
      ..sort((a, b) {
        final diff = _logicPriority(b) - _logicPriority(a);
        if (diff != 0) {
          return diff;
        }
        return a.compareTo(b);
      });
    return filtered;
  }

  bool _isSemanticLogicLink(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return false;
    }
    final lower = normalized.toLowerCase();
    if (lower.startsWith('construct:')) {
      return false;
    }
    if (lower.startsWith('widget:')) {
      return false;
    }
    if (lower.contains('.form') ||
        lower.contains('.textformfield') ||
        lower.contains('.inputdecoration') ||
        lower.contains('stylefrom') ||
        lower.contains('circularprogressindicator') ||
        lower.contains('contexthelpbutton') ||
        lower.contains('listtile') ||
        lower.contains('filledbutton') ||
        lower.contains('outlinedbutton')) {
      return false;
    }
    return lower.contains('repository') ||
        lower.contains('controller') ||
        lower.contains('notifier') ||
        lower.contains('provider') ||
        lower.contains('service') ||
        lower.contains('supabase') ||
        lower.contains('.auth.') ||
        lower.contains('create') ||
        lower.contains('join') ||
        lower.contains('sign') ||
        lower.contains('sync') ||
        lower.contains('refresh') ||
        lower.contains('watch') ||
        lower.contains('submit') ||
        lower.contains('load');
  }

  int _logicPriority(String raw) {
    final lower = raw.toLowerCase();
    var score = 0;
    if (lower.contains('controller') || lower.contains('notifier')) {
      score += 50;
    }
    if (lower.contains('repository')) {
      score += 40;
    }
    if (lower.contains('service')) {
      score += 35;
    }
    if (lower.contains('supabase') || lower.contains('.auth.')) {
      score += 30;
    }
    if (lower.contains('create') ||
        lower.contains('join') ||
        lower.contains('sign')) {
      score += 20;
    }
    if (lower.contains('watch') ||
        lower.contains('load') ||
        lower.contains('refresh')) {
      score += 10;
    }
    return score;
  }

  List<String> _semanticValidations(_JourneyInferenceContext context) {
    final candidates = <String>{
      ...context.signal.validations,
      ...context.signal.forms,
      for (final companion in context.companions) ...companion.validations,
      for (final companion in context.companions) ...companion.forms,
      ...context.signal.guards.where(_looksLikeValidation),
    };
    final filtered = candidates.where(_looksLikeValidation).toSet().toList()
      ..sort();
    return filtered;
  }

  List<String> _semanticGuards(_JourneyInferenceContext context) {
    final candidates = <String>{
      ...context.signal.guards,
      for (final companion in context.companions) ...companion.guards,
    };
    final filtered = candidates.where(_looksLikeGuard).toSet().toList()..sort();
    return filtered;
  }

  List<String> _semanticErrors(_JourneyInferenceContext context) {
    final candidates = <String>{
      ...context.signal.errorPaths,
      for (final companion in context.companions) ...companion.errorPaths,
    };
    final filtered =
        candidates
            .where((error) => !error.toLowerCase().contains('formfield'))
            .toSet()
            .toList()
          ..sort();
    return filtered;
  }

  List<String> _semanticSupabase(_JourneyInferenceContext context) {
    final values = <String>{
      ...context.signal.supabaseInteractions,
      for (final companion in context.companions)
        ...companion.supabaseInteractions,
    };
    final filtered = values.where(_isSemanticLogicLink).toSet().toList()
      ..sort();
    return filtered;
  }

  bool _looksLikeValidation(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('validate') ||
        lower.contains('validator') ||
        lower.contains('required') ||
        lower.contains('invalid') ||
        lower.contains('empty') ||
        lower.contains('format') ||
        lower.contains('contains(@)') ||
        lower.contains('textformfield') ||
        lower == 'form';
  }

  bool _looksLikeGuard(String raw) {
    final lower = raw.toLowerCase();
    if (_looksLikeValidation(raw)) {
      return false;
    }
    return lower.contains('auth') ||
        lower.contains('permission') ||
        lower.contains('role') ||
        lower.contains('admin') ||
        lower.contains('currentuser') ||
        lower.contains('logged') ||
        lower.contains('member') ||
        lower.contains('owner') ||
        lower.contains('redirect');
  }

  String _inferJourneyKind({
    required FileSignals signal,
    required String entryRoute,
  }) {
    final fileName = signal.filePath.split('/').last.toLowerCase();
    final action = _selectPrimaryAction(signal).toLowerCase();

    if (fileName.contains('record_ride')) {
      return 'record';
    }
    if (fileName == 'feed_view.dart') {
      return 'feed';
    }
    if (fileName.contains('members_tab')) {
      return 'members';
    }
    if (fileName.contains('facility_tab')) {
      return 'facility';
    }
    if (fileName.contains('horse_equipment')) {
      return 'equipment';
    }
    if (fileName.contains('equipment_assignment_dialog')) {
      return 'assignment';
    }
    if (fileName.contains('training_progress')) {
      return 'progress';
    }
    if (fileName.contains('user_profile_view')) {
      return 'profile';
    }
    if (fileName.contains('database_debug_screen')) {
      return 'debug';
    }
    if (fileName.contains('training')) {
      return 'training';
    }
    if (entryRoute == '/login' || fileName == 'login_screen.dart') {
      return 'login';
    }
    if (entryRoute.contains('/:') || fileName.contains('detail')) {
      return 'detail';
    }
    if (entryRoute == '/home' || entryRoute == '/profile') {
      return 'shell';
    }
    if (entryRoute == '/groups' ||
        entryRoute == '/horses' ||
        fileName.contains('_list_')) {
      return 'list';
    }
    if (fileName.contains('_wizard.') ||
        signal.filePath.endsWith('_wizard.dart')) {
      return 'wizard';
    }
    if (entryRoute.endsWith('/create') ||
        fileName.startsWith('create_') ||
        action.contains('create')) {
      return 'create';
    }
    if (entryRoute.endsWith('/join') ||
        fileName.startsWith('join_') ||
        action.contains('join')) {
      return 'join';
    }
    return 'generic';
  }

  List<PathStep> _buildBaseSteps({
    required _JourneyInferenceContext context,
    required String journeyKind,
    required List<String> transitions,
    required List<String> logicLinks,
  }) {
    final steps = <PathStep>[
      PathStep(
        kind: 'entry',
        description: _entryDescription(
          signal: context.signal,
          entrySignal: context.entrySignal,
          isSubview: context.isSubview,
        ),
        sourceReference: context.sourceRef,
      ),
      PathStep(
        kind: 'navigation',
        description: 'Start at route ${context.entryRoute}',
        sourceReference: context.sourceRef,
      ),
    ];

    if (context.isSubview) {
      steps.add(
        PathStep(
          kind: 'action',
          description: _subviewSelectionDescription(context),
          sourceReference: _firstReferenceOrFallback(context.entrySignal),
        ),
      );
    }

    if (_hasEmptyStateJourney(context, journeyKind)) {
      steps.add(
        PathStep(
          kind: 'empty_state',
          description:
              'Observe the initial empty state and available primary actions.',
          sourceReference: context.sourceRef,
        ),
      );
    }

    if (_requiresInputStep(journeyKind, context.signal.forms)) {
      steps.add(
        PathStep(
          kind: 'input',
          description: _inputDescription(journeyKind, context.signal.forms),
          sourceReference: context.sourceRef,
        ),
      );
    }

    final selectedAction = _selectPrimaryAction(context.signal);
    steps.add(
      PathStep(
        kind: 'action',
        description: _actionDescription(
          journeyKind: journeyKind,
          action: selectedAction,
          context: context,
        ),
        sourceReference: context.sourceRef,
      ),
    );

    final primaryTransition = _primaryTransition(
      transitions: transitions,
      journeyKind: journeyKind,
      entryRoute: context.entryRoute,
    );
    if (primaryTransition != null) {
      steps.add(
        PathStep(
          kind: 'navigation',
          description: 'Navigate to $primaryTransition',
          sourceReference: context.sourceRef,
        ),
      );
    }

    final primaryLogic = logicLinks.isEmpty ? null : logicLinks.first;
    if (primaryLogic != null) {
      steps.add(
        PathStep(
          kind: 'data',
          description: _dataDescription(
            journeyKind: journeyKind,
            logicLink: primaryLogic,
          ),
          sourceReference: context.sourceRef,
        ),
      );
    }

    steps.add(
      PathStep(
        kind: 'outcome',
        description: _positiveOutcomeDescription(
          journeyKind,
          context,
          primaryTransition,
        ),
        sourceReference: context.sourceRef,
      ),
    );

    return steps;
  }

  bool _hasEmptyStateJourney(
    _JourneyInferenceContext context,
    String journeyKind,
  ) {
    if (journeyKind != 'list') {
      return false;
    }
    final transitions = _semanticTransitions(context);
    return transitions.any(
      (route) =>
          route.endsWith('/create') ||
          route.endsWith('/join') ||
          route.endsWith('/add'),
    );
  }

  bool _requiresInputStep(String journeyKind, List<String> forms) {
    return journeyKind == 'login' ||
        journeyKind == 'create' ||
        journeyKind == 'join' ||
        journeyKind == 'wizard' ||
        journeyKind == 'record' ||
        forms.isNotEmpty;
  }

  String _inputDescription(String journeyKind, List<String> forms) {
    if (journeyKind == 'login') {
      return 'Provide a valid email address and submit the login form.';
    }
    if (journeyKind == 'join') {
      return 'Provide the required join code or membership input values.';
    }
    if (journeyKind == 'wizard') {
      return 'Fill the required wizard fields across the visible steps.';
    }
    if (journeyKind == 'create') {
      return 'Fill the required form fields with valid creation data.';
    }
    if (journeyKind == 'record') {
      return 'Configure horse selection, timing, and recording preconditions as needed.';
    }
    if (forms.isNotEmpty) {
      return 'Fill the detected form fields (${forms.join(', ')}) with valid input.';
    }
    return 'Provide the required input values.';
  }

  String _actionDescription({
    required String journeyKind,
    required String action,
    required _JourneyInferenceContext context,
  }) {
    if (_hasEmptyStateJourney(context, journeyKind)) {
      final transition = _primaryTransition(
        transitions: _semanticTransitions(context),
        journeyKind: journeyKind,
        entryRoute: context.entryRoute,
      );
      if (transition != null) {
        return 'Activate the primary empty-state CTA to continue to $transition.';
      }
    }

    return switch (journeyKind) {
      'login' => 'Submit the login action ($action).',
      'create' => 'Submit the creation action ($action).',
      'join' => 'Submit the join action ($action).',
      'wizard' => 'Advance the wizard using the primary action ($action).',
      'record' =>
        'Start, continue, or validate ride recording controls ($action).',
      'members' =>
        'Inspect the member list and membership status for the selected group.',
      'facility' =>
        'Inspect or manage the facility map/details for the selected group.',
      'equipment' => 'Inspect or manage assigned horse equipment.',
      'training' => 'Inspect or manage horse training entries.',
      'progress' => 'Inspect horse progress visualizations and filters.',
      'detail' => 'Trigger the primary detail action ($action).',
      'shell' || 'list' => 'Trigger the visible user action ($action).',
      _ => 'Trigger the inferred user action ($action).',
    };
  }

  String _dataDescription({
    required String journeyKind,
    required String logicLink,
  }) {
    return switch (journeyKind) {
      'login' => 'Execute authentication flow via $logicLink.',
      'create' => 'Persist the new entity via $logicLink.',
      'join' => 'Execute membership join flow via $logicLink.',
      'record' =>
        'Execute recording state changes and ride persistence via $logicLink.',
      'feed' => 'Load feed content and feed interactions via $logicLink.',
      'members' => 'Load or sync membership data via $logicLink.',
      'facility' => 'Load or persist facility data via $logicLink.',
      'equipment' => 'Load or persist equipment assignments via $logicLink.',
      'assignment' => 'Assign equipment through $logicLink.',
      'training' => 'Load or persist training data via $logicLink.',
      'progress' => 'Load progress timeline data via $logicLink.',
      'profile' => 'Load or persist profile preferences through $logicLink.',
      'debug' => 'Execute developer diagnostics via $logicLink.',
      'detail' => 'Load the selected resource via $logicLink.',
      'shell' || 'list' => 'Load the visible user data via $logicLink.',
      'wizard' => 'Persist wizard progress or final entity via $logicLink.',
      _ => 'Execute journey logic via $logicLink.',
    };
  }

  String _positiveOutcomeDescription(
    String journeyKind,
    _JourneyInferenceContext context,
    String? primaryTransition,
  ) {
    return switch (journeyKind) {
      'login' =>
        'Reach authenticated app state or visible login success feedback.',
      'create' =>
        'Observe the newly created item in the UI${primaryTransition != null ? ' after returning through $primaryTransition' : ''}.',
      'join' =>
        'Observe successful membership outcome without validation or error feedback.',
      'record' =>
        'Observe recording UI, preflight state, or active ride controls.',
      'feed' => 'Observe feed content, filter actions, or refresh controls.',
      'members' =>
        'Observe member list content or member empty-state feedback.',
      'facility' => 'Observe facility map/details content or facility actions.',
      'equipment' => 'Observe horse equipment content or assignment actions.',
      'assignment' =>
        'Observe the equipment assignment dialog and available assignment choices.',
      'training' =>
        'Observe training list content, training empty state, or training actions.',
      'progress' => 'Observe progress charts or progress empty-state guidance.',
      'profile' =>
        'Observe profile content, edit affordances, or preference controls.',
      'debug' =>
        'Observe database debug actions or database inspection output.',
      'detail' => 'Observe detail content for the selected route resource.',
      'list' when _hasEmptyStateJourney(context, journeyKind) =>
        'Observe an actionable empty state and continue into the next feature step.',
      'list' => 'Observe visible list content or list-level actions.',
      'shell' => 'Observe the authenticated shell and visible primary content.',
      'wizard' =>
        'Observe wizard progress and continue toward a completed entity flow.',
      _ => 'Observe visible journey completion in the UI.',
    };
  }

  String _positiveOutcomeClass({
    required String journeyKind,
    required _JourneyInferenceContext context,
  }) {
    return switch (journeyKind) {
      'login' => 'auth_success',
      'create' => 'entity_created_visible',
      'join' => 'membership_joined',
      'record' => 'recording_flow_visible',
      'feed' => 'feed_visible',
      'members' => 'members_visible',
      'facility' => 'facility_visible',
      'equipment' => 'equipment_visible',
      'assignment' => 'assignment_dialog_visible',
      'training' => 'training_visible',
      'progress' => 'progress_visible',
      'profile' => 'profile_visible',
      'debug' => 'debug_tools_visible',
      'detail' => 'detail_visible',
      'list' when _hasEmptyStateJourney(context, journeyKind) =>
        'empty_state_actionable',
      'list' => 'list_visible',
      'shell' => 'shell_visible',
      'wizard' => 'wizard_flow_visible',
      _ => 'journey_visible',
    };
  }

  String _positiveDescription({
    required String journeyKind,
    required _JourneyInferenceContext context,
  }) {
    return switch (journeyKind) {
      'login' =>
        'Login journey from ${context.signal.filePath} into the authenticated app flow.',
      'create' =>
        'Creation journey from ${context.signal.filePath} through visible post-submit outcome.',
      'join' =>
        'Join journey from ${context.signal.filePath} through successful membership outcome.',
      'record' =>
        'Ride recording subjourney from ${context.signal.filePath} inside the authenticated home shell.',
      'feed' =>
        'Feed subjourney from ${context.signal.filePath} inside the authenticated home shell.',
      'members' =>
        'Group members subjourney from ${context.signal.filePath} inside the group detail shell.',
      'facility' =>
        'Group facility subjourney from ${context.signal.filePath} inside the group detail shell.',
      'equipment' =>
        'Horse equipment subjourney from ${context.signal.filePath} inside the horse detail shell.',
      'assignment' =>
        'Equipment assignment subjourney from ${context.signal.filePath} inside the horse equipment flow.',
      'training' =>
        'Horse training subjourney from ${context.signal.filePath} inside the horse detail shell.',
      'progress' =>
        'Horse progress subjourney from ${context.signal.filePath} inside the horse detail shell.',
      'profile' =>
        'Profile subjourney from ${context.signal.filePath} inside the profile shell.',
      'debug' =>
        'Developer debug subjourney from ${context.signal.filePath} inside the developer settings flow.',
      'detail' =>
        'Detail journey from ${context.signal.filePath} to a visible resource detail state.',
      'list' when _hasEmptyStateJourney(context, journeyKind) =>
        'List journey from ${context.signal.filePath} through empty-state CTA progression.',
      'list' =>
        'List journey from ${context.signal.filePath} to a visible list state.',
      'shell' =>
        'Shell journey from ${context.signal.filePath} to authenticated shell content.',
      'wizard' =>
        'Wizard journey from ${context.signal.filePath} across the visible multi-step flow.',
      _ => 'User journey inferred from ${context.signal.filePath}.',
    };
  }

  String _validationDescription({
    required String journeyKind,
    required _JourneyInferenceContext context,
  }) {
    return switch (journeyKind) {
      'login' =>
        'Validation journey for invalid login input from ${context.signal.filePath}.',
      'create' =>
        'Validation journey for creation input from ${context.signal.filePath}.',
      'join' =>
        'Validation journey for join input from ${context.signal.filePath}.',
      'wizard' =>
        'Validation journey for incomplete wizard input from ${context.signal.filePath}.',
      'record' =>
        'Validation or preflight journey for ride recording input in ${context.signal.filePath}.',
      _ => 'Validation journey inferred from ${context.signal.filePath}.',
    };
  }

  String _guardDescription({
    required String journeyKind,
    required _JourneyInferenceContext context,
  }) {
    return switch (journeyKind) {
      'list' || 'shell' || 'detail' =>
        'Protected-route guard journey inferred from ${context.signal.filePath}.',
      _ => 'Guard-blocked journey inferred from ${context.signal.filePath}.',
    };
  }

  String _backendErrorDescription({
    required String journeyKind,
    required _JourneyInferenceContext context,
  }) {
    return switch (journeyKind) {
      'login' =>
        'Backend-error journey for the login flow in ${context.signal.filePath}.',
      'create' =>
        'Backend-error journey for the create flow in ${context.signal.filePath}.',
      'join' =>
        'Backend-error journey for the join flow in ${context.signal.filePath}.',
      'detail' =>
        'Backend-error journey for the detail flow in ${context.signal.filePath}.',
      _ => 'Backend-error journey inferred from ${context.signal.filePath}.',
    };
  }

  String _validationOutcomeDescription(String journeyKind) {
    return switch (journeyKind) {
      'login' =>
        'Expect inline validation feedback for missing or invalid email input.',
      'create' =>
        'Expect inline validation feedback for missing required creation data.',
      'join' =>
        'Expect inline validation feedback for missing or invalid join code.',
      'wizard' =>
        'Expect the wizard to stay on the current step with validation feedback.',
      'record' =>
        'Expect recording setup or preflight feedback before the ride can start.',
      _ => 'Expect inline validation feedback for invalid input.',
    };
  }

  String _guardOutcomeDescription(String entryRoute) {
    if (_routeRequiresAuth(entryRoute)) {
      return 'Expect the protected journey to redirect to login or block the action.';
    }
    return 'Expect guard or status checks to block the operation.';
  }

  String _backendErrorOutcomeDescription(String journeyKind) {
    return switch (journeyKind) {
      'login' =>
        'Expect visible authentication error feedback after backend failure.',
      'create' =>
        'Expect visible submission error feedback without persisting the entity.',
      'join' =>
        'Expect visible join error feedback without creating membership.',
      'record' =>
        'Expect visible ride recording failure feedback without starting recording.',
      _ => 'Expect visible user-facing error feedback after backend failure.',
    };
  }

  bool _supportsValidationPath({
    required String journeyKind,
    required List<String> validations,
  }) {
    if (validations.isEmpty) {
      return false;
    }
    return journeyKind == 'login' ||
        journeyKind == 'create' ||
        journeyKind == 'join' ||
        journeyKind == 'wizard' ||
        journeyKind == 'record' ||
        journeyKind == 'generic';
  }

  bool _supportsGuardPath({
    required String journeyKind,
    required List<String> guards,
    required String entryRoute,
  }) {
    if (guards.isNotEmpty) {
      return true;
    }
    return (journeyKind == 'list' ||
            journeyKind == 'shell' ||
            journeyKind == 'detail' ||
            journeyKind == 'record' ||
            journeyKind == 'members' ||
            journeyKind == 'facility' ||
            journeyKind == 'equipment' ||
            journeyKind == 'training' ||
            journeyKind == 'progress') &&
        _routeRequiresAuth(entryRoute);
  }

  bool _supportsBackendErrorPath({
    required String journeyKind,
    required List<String> errors,
    required List<String> logicLinks,
  }) {
    if (logicLinks.isEmpty && errors.isEmpty) {
      return false;
    }
    return journeyKind != 'list' || logicLinks.isNotEmpty || errors.isNotEmpty;
  }

  UserPath? _buildSequentialPath({
    required _JourneyInferenceContext context,
    required String journeyKind,
    required String confidence,
    required List<String> sourceFiles,
    required List<PathStep> steps,
    required List<String> guards,
    required List<String> validations,
    required List<String> errors,
    required List<String> supabase,
    required int index,
  }) {
    final sequenceOperations = _sequenceOperations(
      context: context,
      journeyKind: journeyKind,
    );
    if (sequenceOperations == null) {
      return null;
    }

    return UserPath(
      pathId: _buildPathId(
        moduleKey: context.signal.moduleKey,
        sourceFile: context.signal.filePath,
        variant: sequenceOperations.idVariant,
        index: index,
      ),
      moduleKey: context.signal.moduleKey,
      featureKey: context.signal.featureKey,
      variant: 'sequential',
      confidence: confidence,
      outcomeClass: 'sequence_success',
      description: sequenceOperations.description,
      sourceFiles: sourceFiles,
      steps: <PathStep>[
        ...steps,
        PathStep(
          kind: 'sequence',
          description: sequenceOperations.operations.join(' -> '),
          sourceReference: context.sourceRef,
        ),
      ],
      guards: guards,
      validations: validations,
      errors: errors,
      supabaseInteractions: supabase,
      heuristicNotes: <String>[
        'Sequence generated from the inferred follow-up route structure of the journey.',
      ],
      parityKey: parityKeyFromSourceFile(context.signal.filePath),
      primarySourceFile: context.signal.filePath,
    );
  }

  _SequencePlan? _sequenceOperations({
    required _JourneyInferenceContext context,
    required String journeyKind,
  }) {
    final followUpRoute = _followUpReadRoute(context);
    if (journeyKind == 'login') {
      final transitions = _semanticTransitions(context);
      if (transitions.isNotEmpty) {
        return const _SequencePlan(
          idVariant: 'sequence_auth_navigation',
          description:
              'Sequential auth -> navigate flow inferred from the login entrypoint.',
          operations: <String>['login', 'navigate', 'state_verify'],
        );
      }
    }

    if ((journeyKind == 'create' ||
            journeyKind == 'wizard' ||
            journeyKind == 'join') &&
        followUpRoute != null) {
      return _SequencePlan(
        idVariant: 'sequence_submit_followup',
        description:
            'Sequential submit -> follow-up read flow inferred from visible feature routes.',
        operations: <String>['submit', 'navigate', 'read'],
      );
    }

    return null;
  }

  String? _followUpReadRoute(_JourneyInferenceContext context) {
    final current = context.entryRoute;
    final routePrefix = _routePrefix(current);
    final preferred = <String>[];

    if (current.endsWith('/create') ||
        current.endsWith('/join') ||
        current.endsWith('/add')) {
      preferred.add(routePrefix);
      preferred.add('$routePrefix/:id');
    }

    for (final route in context.knownRoutes.toList()..sort()) {
      if (preferred.contains(route)) {
        return route;
      }
    }

    return null;
  }

  List<String> _relevantDocs({
    required List<String> docs,
    required FileSignals signal,
    required String entryRoute,
  }) {
    final fileName = signal.filePath
        .split('/')
        .last
        .toLowerCase()
        .replaceAll('.dart', '');
    final routeSegment =
        entryRoute
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .firstOrNull ??
        '';
    final filtered =
        docs
            .where((doc) {
              final lower = doc.toLowerCase();
              return lower.contains(fileName) ||
                  (routeSegment.isNotEmpty && lower.contains(routeSegment));
            })
            .toSet()
            .toList()
          ..sort();
    return filtered;
  }

  String _inferConfidence({
    required String entryRoute,
    required List<String> transitions,
    required List<String> logicLinks,
    required String journeyKind,
  }) {
    if (logicLinks.isNotEmpty &&
        (transitions.isNotEmpty || _routeRequiresAuth(entryRoute))) {
      return 'high';
    }
    if (journeyKind == 'list' ||
        journeyKind == 'shell' ||
        journeyKind == 'detail') {
      return 'high';
    }
    if (logicLinks.isNotEmpty || transitions.isNotEmpty) {
      return 'medium';
    }
    return 'low';
  }

  bool _routeRequiresAuth(String route) {
    return route != '/login';
  }

  String? _primaryTransition({
    required List<String> transitions,
    required String journeyKind,
    required String entryRoute,
  }) {
    if (transitions.isEmpty) {
      return null;
    }

    final sorted = transitions.toList()
      ..sort((a, b) {
        final diff =
            _transitionPriority(
              route: b,
              journeyKind: journeyKind,
              entryRoute: entryRoute,
            ) -
            _transitionPriority(
              route: a,
              journeyKind: journeyKind,
              entryRoute: entryRoute,
            );
        if (diff != 0) {
          return diff;
        }
        return a.compareTo(b);
      });
    return sorted.first;
  }

  int _transitionPriority({
    required String route,
    required String journeyKind,
    required String entryRoute,
  }) {
    var score = 0;
    if (route.endsWith('/create') || route.endsWith('/add')) {
      score += 40;
    }
    if (route.endsWith('/join')) {
      score += 35;
    }
    if (route.contains('/:')) {
      score += 20;
    }
    if (journeyKind == 'login' && route == '/home') {
      score += 50;
    }
    if (journeyKind == 'list' &&
        _routePrefix(route) == _routePrefix(entryRoute)) {
      score += 10;
    }
    return score;
  }

  String _entryStem(String filePath) {
    final fileName = filePath.split('/').last;
    return fileName
        .replaceAll('_screen.dart', '')
        .replaceAll('_view.dart', '')
        .replaceAll('_wizard.dart', '')
        .replaceAll('_dialog.dart', '');
  }

  String _primaryNoun(String filePath) {
    final stem = _entryStem(filePath);
    if (stem.isEmpty) {
      return '';
    }
    return stem.split('_').first;
  }

  String _routePrefix(String route) {
    final normalized = route.trim();
    if (normalized.isEmpty || normalized == '/') {
      return normalized;
    }
    final parts = normalized.split('/')
      ..removeWhere((segment) => segment.isEmpty);
    if (parts.isEmpty) {
      return normalized;
    }
    return '/${parts.first}';
  }

  String _selectPrimaryAction(FileSignals signal) {
    final actions = signal.uiActions.toList()..sort();
    if (actions.isEmpty) {
      return 'unknown_action';
    }

    actions.sort((a, b) {
      final scoreDiff = _actionPriorityScore(b) - _actionPriorityScore(a);
      if (scoreDiff != 0) {
        return scoreDiff;
      }
      return a.compareTo(b);
    });
    return actions.first;
  }

  int _actionPriorityScore(String action) {
    final lower = action.toLowerCase();
    var score = 0;

    if (lower.contains('onpressed')) {
      score += 100;
    } else if (lower.contains('ontap')) {
      score += 90;
    } else if (lower.contains('onsubmitted') ||
        lower.contains('onfieldsubmitted')) {
      score += 80;
    } else if (lower.contains('onlongpress')) {
      score += 70;
    } else if (lower.contains('onchanged')) {
      score += 10;
    }

    if (lower.contains('submit') ||
        lower.contains('save') ||
        lower.contains('create') ||
        lower.contains('join') ||
        lower.contains('login') ||
        lower.contains('sign') ||
        lower.contains('add')) {
      score += 25;
    }

    if (lower.contains('toggle') || lower.contains('select')) {
      score -= 10;
    }

    return score;
  }

  bool _isJourneyEntrySignal(FileSignals signal) {
    if (!isJourneyEntryFilePath(signal.filePath)) {
      return false;
    }
    if (signal.uiActions.isEmpty) {
      return false;
    }
    return signal.screens.isNotEmpty || signal.widgets.isNotEmpty;
  }

  String? _resolveEntryRoute({
    required FileSignals signal,
    required Map<String, List<String>> routeBindings,
  }) {
    final candidateClasses = <String>{...signal.screens, ...signal.widgets};

    final routes = <String>{};
    for (final className in candidateClasses) {
      routes.addAll(routeBindings[className] ?? const <String>[]);
    }

    if (routes.isEmpty) {
      return null;
    }

    final sortedRoutes = routes.toList()
      ..sort((a, b) {
        final aHasParams = a.contains(':');
        final bHasParams = b.contains(':');
        if (aHasParams != bHasParams) {
          return aHasParams ? 1 : -1;
        }
        return a.compareTo(b);
      });
    return sortedRoutes.first;
  }

  SourceReference _firstReferenceOrFallback(FileSignals signal) {
    if (signal.references.isNotEmpty) {
      return signal.references.first;
    }
    return SourceReference(
      file: signal.filePath,
      line: 1,
      column: 1,
      label: 'fallback',
    );
  }

  String _buildPathId({
    required String moduleKey,
    required String sourceFile,
    required String variant,
    required int index,
  }) {
    final module = sanitizeForId(moduleKey);
    final source = sanitizeForId(
      sourceFile.split('/').last.replaceAll('.dart', ''),
    );
    final variantSlug = sanitizeForId(variant);
    final suffix = index.toString().padLeft(2, '0');
    return 'UP_${module}_${source}_${variantSlug}_$suffix';
  }

  List<String> _baseHeuristics({
    required String confidence,
    required List<String> docs,
    required FileSignals signal,
    required FileSignals entrySignal,
    required String entryRoute,
    required String journeyKind,
    required List<String> transitions,
    required List<String> logicLinks,
    required bool isSubview,
  }) {
    final notes = <String>[
      'Inference mode is heuristic and derived from AST + route structure.',
      'Journey kind resolved as $journeyKind.',
      'Confidence=$confidence based on route visibility and semantic logic links.',
      'Entry route resolved from AST router analysis: $entryRoute',
    ];

    if (transitions.isNotEmpty) {
      notes.add(
        'Primary transitions considered: ${transitions.take(3).join(', ')}',
      );
    }
    if (logicLinks.isNotEmpty) {
      notes.add(
        'Primary logic links considered: ${logicLinks.take(3).join(', ')}',
      );
    }
    if (docs.isNotEmpty) {
      notes.add(
        'Feature-specific documentation hints considered: ${docs.take(3).join(' | ')}',
      );
    }
    if (logicLinks.isEmpty &&
        (journeyKind == 'list' || journeyKind == 'shell')) {
      notes.add(
        'No direct backend call in entry screen; outcome is inferred from visible shell/list structure.',
      );
    }
    if (signal.filePath.endsWith('_screen.dart') &&
        signal.filePath.contains('/presentation/')) {
      notes.add('Entry is restricted to a routable feature presentation file.');
    }
    if (isSubview) {
      notes.add(
        'Subjourney inferred from ${entrySignal.filePath} by following instantiated feature widgets.',
      );
    }

    return notes;
  }

  String _entryDescription({
    required FileSignals signal,
    required FileSignals entrySignal,
    required bool isSubview,
  }) {
    if (isSubview) {
      final childLabel =
          signal.screens.firstOrNull ?? signal.widgets.firstOrNull;
      final parentLabel =
          entrySignal.screens.firstOrNull ?? entrySignal.widgets.firstOrNull;
      return 'Open ${parentLabel ?? entrySignal.filePath} and inspect ${childLabel ?? signal.filePath}';
    }
    if (signal.screens.isNotEmpty) {
      return 'Open screen ${signal.screens.first}';
    }
    if (signal.widgets.isNotEmpty) {
      return 'Open widget ${signal.widgets.first}';
    }
    return 'Open entry file ${signal.filePath}';
  }

  String _subviewSelectionDescription(_JourneyInferenceContext context) {
    final childLabel =
        context.signal.screens.firstOrNull ??
        context.signal.widgets.firstOrNull;
    final parentLabel =
        context.entrySignal.screens.firstOrNull ??
        context.entrySignal.widgets.firstOrNull;
    return 'Switch within ${parentLabel ?? context.entrySignal.filePath} to ${childLabel ?? context.signal.filePath}.';
  }

  List<FileSignals> _embeddedSubviewSignals({
    required FileSignals entrySignal,
    required List<FileSignals> allSignals,
  }) {
    final instantiated = entrySignal.instantiatedWidgets.toSet();

    final subviews = allSignals.where((candidate) {
      if (candidate.filePath == entrySignal.filePath) {
        return false;
      }
      if (!candidate.filePath.contains('/presentation/')) {
        return false;
      }

      final fileName = candidate.filePath.split('/').last;
      if (!_isEmbeddedSubviewFileName(fileName)) {
        return false;
      }

      final candidateNames = <String>{
        ...candidate.screens,
        ...candidate.widgets,
      };
      final matchesInstantiation = candidateNames.any(instantiated.contains);
      final matchesSemanticSubview = _matchesSemanticSubview(
        entryFileName: entrySignal.filePath.split('/').last,
        candidateFileName: fileName,
      );
      if (!matchesInstantiation && !matchesSemanticSubview) {
        return false;
      }

      return candidate.uiActions.isNotEmpty ||
          candidate.forms.isNotEmpty ||
          candidate.repositoryCalls.isNotEmpty ||
          candidate.serviceCalls.isNotEmpty ||
          candidate.supabaseInteractions.isNotEmpty ||
          candidate.stateChanges.isNotEmpty ||
          candidate.navigationTransitions.isNotEmpty ||
          candidate.errorPaths.isNotEmpty;
    }).toList()..sort((a, b) => a.filePath.compareTo(b.filePath));

    return subviews;
  }

  bool _isEmbeddedSubviewFileName(String fileName) {
    return fileName.endsWith('_view.dart') ||
        fileName.endsWith('_tab.dart') ||
        fileName.endsWith('_dialog.dart') ||
        fileName.endsWith('_wizard.dart') ||
        fileName.endsWith('_screen.dart');
  }

  bool _matchesSemanticSubview({
    required String entryFileName,
    required String candidateFileName,
  }) {
    if (entryFileName == 'feed_screen.dart') {
      return candidateFileName == 'feed_view.dart' ||
          candidateFileName == 'record_ride_view.dart' ||
          candidateFileName == 'logout_dialog.dart';
    }
    if (entryFileName == 'group_detail_screen.dart') {
      return candidateFileName == 'members_tab.dart' ||
          candidateFileName == 'facility_tab.dart' ||
          candidateFileName == 'delete_group_dialog.dart';
    }
    if (entryFileName == 'profile_screen.dart') {
      return candidateFileName == 'user_profile_view.dart';
    }
    if (entryFileName == 'developer_settings_screen.dart') {
      return candidateFileName == 'database_debug_screen.dart';
    }
    if (entryFileName == 'horse_detail_screen.dart') {
      return candidateFileName == 'horse_equipment_view.dart' ||
          candidateFileName == 'horse_training_list_view.dart' ||
          candidateFileName == 'horse_training_progress_view.dart' ||
          candidateFileName == 'delete_horse_dialog.dart';
    }
    if (entryFileName == 'horse_equipment_view.dart') {
      return candidateFileName == 'equipment_assignment_dialog.dart';
    }
    if (entryFileName == 'horse_training_list_view.dart' ||
        entryFileName == 'horse_training_progress_view.dart') {
      return candidateFileName == 'create_training_wizard.dart';
    }
    if (entryFileName == 'facility_tab.dart') {
      return candidateFileName == 'address_edit_dialog.dart';
    }
    return false;
  }
}

class _JourneyInferenceContext {
  const _JourneyInferenceContext({
    required this.signal,
    required this.entrySignal,
    required this.companions,
    required this.sourceRef,
    required this.entryRoute,
    required this.docs,
    required this.knownRoutes,
    required this.isSubview,
  });

  final FileSignals signal;
  final FileSignals entrySignal;
  final List<FileSignals> companions;
  final SourceReference sourceRef;
  final String entryRoute;
  final List<String> docs;
  final Set<String> knownRoutes;
  final bool isSubview;
}

class _SequencePlan {
  const _SequencePlan({
    required this.idVariant,
    required this.description,
    required this.operations,
  });

  final String idVariant;
  final String description;
  final List<String> operations;
}

extension on Iterable<String> {
  String? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
