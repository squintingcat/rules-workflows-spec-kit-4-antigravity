import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../pathing/src/models.dart';
import 'behavior_assertions.dart';
import 'explorer_logger.dart';
import 'input_strategy.dart';
import 'project_adapter.dart';

class BlindExplorer {
  BlindExplorer({
    required this.tester,
    required this.adapter,
    this.inputStrategy = const InputStrategy(),
    this.behaviorAssertions = const BehaviorAssertions(),
    this.maxDepth = 10,
    this.maxActionsPerScreen = 20,
    this.maxTotalActions = 24,
    this.interactionTimeout = const Duration(seconds: 10),
    this.logger = const ExplorerLogger(),
    Set<String> gapHints = const <String>{},
  }) : gapHints = gapHints.toSet();

  final WidgetTester tester;
  final ProjectAdapter adapter;
  final InputStrategy inputStrategy;
  final BehaviorAssertions behaviorAssertions;
  final int maxDepth;
  final int maxActionsPerScreen;
  final int maxTotalActions;
  final Duration interactionTimeout;
  final ExplorerLogger logger;
  final Set<String> gapHints;

  final Map<String, VisitedScreen> _visited = <String, VisitedScreen>{};
  final List<TestedInteraction> _interactions = <TestedInteraction>[];
  final List<FoundDefect> _defects = <FoundDefect>[];
  int _totalActions = 0;

  Future<ExplorationResult> explore() async {
    final stopwatch = Stopwatch()..start();
    _totalActions = 0;
    _visited.clear();
    _interactions.clear();
    _defects.clear();
    await adapter.ensureAppStarted(tester);
    await _waitForInteractiveUi();
    await _exploreScreen(route: _currentRoute(), depth: 0);
    await adapter.performLogin(tester);
    await _waitForAuthenticatedUi();
    await _exploreScreen(route: _currentRoute(), depth: 0);
    await _exploreGapHints();
    try {
      await adapter.restartApp(tester);
      await _waitForInteractiveUi();
    } catch (_) {
      // Best-effort reset to leave the app in a stable state for test teardown.
    }
    await adapter.cleanup();
    stopwatch.stop();
    return ExplorationResult(
      screens: _visited.values.toList(),
      interactions: _interactions,
      defects: _defects,
      totalDuration: stopwatch.elapsed,
      visitedRoutes: _visited.keys.toSet(),
      unreachableRoutes: gapHints.difference(_visited.keys.toSet()),
    );
  }

  Future<void> _exploreScreen({
    required String route,
    required int depth,
  }) async {
    if (depth > maxDepth || route.isEmpty || _visited.containsKey(route)) {
      return;
    }

    await adapter.seedForRoute(route);
    await _waitForRouteReady(route);

    final widgets = _discoverInteractiveWidgets();
    logger.screen(route: route, widgets: widgets.length, depth: depth);
    _visited[route] = VisitedScreen(
      route: route,
      interactiveWidgets: widgets,
      visitedAt: DateTime.now(),
      hasContent: _hasVisibleContent(),
    );

    final emptyState = _isEmptyState();

    final queue = emptyState
        ? widgets.where((widget) => !_isEmptyStateQueueAction(widget)).toList()
        : <DiscoveredWidget>[...widgets];
    final seenKeys = widgets.map(_widgetKey).toSet();
    final interactionCounts = <String, int>{};
    var actionCount = 0;
    for (var index = 0; index < queue.length; index += 1) {
      if (depth == 0 && _allGapHintsVisited()) {
        break;
      }
      final widget = queue[index];
      final widgetKey = _widgetKey(widget);
      if ((interactionCounts[widgetKey] ?? 0) >=
          _maxInteractionsForWidget(widget)) {
        continue;
      }
      if (actionCount >= maxActionsPerScreen ||
          _totalActions >= maxTotalActions) {
        break;
      }
      final outcome = await _interactWith(widget, route: route);
      actionCount += 1;
      _totalActions += 1;
      interactionCounts[widgetKey] = (interactionCounts[widgetKey] ?? 0) + 1;

      final currentRoute = _currentRoute();
      if (currentRoute != route) {
        await _exploreScreen(route: currentRoute, depth: depth + 1);
        final returned = await _navigateBack(targetRoute: route);
        if (!returned) {
          return;
        }
        continue;
      }

      if (outcome == InteractionOutcome.contentChanged ||
          outcome == InteractionOutcome.dialogOpened ||
          outcome == InteractionOutcome.validationError) {
        final rediscovered = _discoverInteractiveWidgets();
        for (final candidate in rediscovered) {
          if (emptyState && _isEmptyStateQueueAction(candidate)) {
            continue;
          }
          final key = _widgetKey(candidate);
          final shouldRevisit =
              _formIsPresent() &&
              candidate.widgetType.contains('Button') &&
              (interactionCounts[key] ?? 0) <
                  _maxInteractionsForWidget(candidate);
          if (shouldRevisit || seenKeys.add(key)) {
            queue.add(candidate);
          }
        }
      }
    }
  }

  Future<void> _exploreGapHints() async {
    if (gapHints.isEmpty) {
      return;
    }

    final orderedHints = gapHints.toList()..sort();
    for (final routeHint in orderedHints) {
      if (_totalActions >= maxTotalActions || _allGapHintsVisited()) {
        break;
      }
      await adapter.restartApp(tester);
      await _waitForInteractiveUi();
      await adapter.performLogin(tester);
      await _waitForAuthenticatedUi();
      final targetRoute = await _materializeRouteHint(routeHint);
      if (targetRoute == null || _visited.containsKey(targetRoute)) {
        continue;
      }
      logger.gapHint(target: targetRoute, source: routeHint);
      final navigated = await _navigateToRoute(targetRoute);
      if (!navigated) {
        continue;
      }
      final currentRoute = _currentRoute();
      final effectiveRoute =
          routePatternMatches(targetRoute, currentRoute) ||
              routePatternMatches(
                targetRoute,
                currentRoute,
                allowChildSegments: true,
              )
          ? currentRoute
          : targetRoute;
      await _exploreScreen(route: effectiveRoute, depth: 0);
    }
  }

  Future<String?> _materializeRouteHint(String routeHint) async {
    final normalized = routeHint.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (!normalized.contains(':')) {
      return normalized;
    }
    return adapter.materializeRoute(normalized);
  }

  Future<bool> _navigateToRoute(String targetRoute) async {
    if (targetRoute.trim().isEmpty) {
      return false;
    }
    final routeBefore = _currentRoute();
    final signatureBefore = _uiSignature();
    if (routePatternMatches(targetRoute, routeBefore) ||
        routePatternMatches(
          targetRoute,
          routeBefore,
          allowChildSegments: true,
        )) {
      return true;
    }

    final adapterNavigated = await adapter.navigateToRoute(tester, targetRoute);
    if (adapterNavigated) {
      await _settle();
      await _waitForRouteReady(targetRoute);
      final routeAfterAdapter = _currentRoute();
      final signatureAfterAdapter = _uiSignature();
      if (routePatternMatches(targetRoute, routeAfterAdapter) ||
          routePatternMatches(
            targetRoute,
            routeAfterAdapter,
            allowChildSegments: true,
          ) ||
          routeAfterAdapter != routeBefore ||
          signatureAfterAdapter != signatureBefore) {
        return true;
      }
      return false;
    }

    try {
      final materialAppFinder = find.byType(MaterialApp);
      if (materialAppFinder.evaluate().isNotEmpty) {
        final materialApp = tester.widget<MaterialApp>(materialAppFinder.first);
        final routerConfig = materialApp.routerConfig;
        if (routerConfig is GoRouter) {
          routerConfig.go(targetRoute);
          await _settle();
          await _waitForRouteReady(targetRoute);
          final routeAfterGo = _currentRoute();
          if (routePatternMatches(targetRoute, routeAfterGo) ||
              routePatternMatches(
                targetRoute,
                routeAfterGo,
                allowChildSegments: true,
              )) {
            return true;
          }
        }
      }
    } catch (_) {
      // Fall back to context-based routing.
    }

    return _currentRoute() == targetRoute;
  }

  Future<InteractionOutcome> _interactWith(
    DiscoveredWidget widget, {
    required String route,
  }) async {
    if (_isBackLikeControl(widget)) {
      return InteractionOutcome.noVisibleChange;
    }
    if (_shouldSkipRouteLocalNavigation(widget, route)) {
      return InteractionOutcome.noVisibleChange;
    }
    final routeBefore = _currentRoute();
    final signatureBefore = _uiSignature();
    logger.action(
      route: route,
      widget: widget.widgetType,
      label: widget.label,
      semantics: widget.semanticsLabel,
    );
    try {
      switch (widget.widgetType) {
        case 'TextFormField':
          await _fillTextField(widget);
          break;
        case 'NavigationDestination':
        case 'SegmentedButton':
        case 'DropdownButton':
        case 'Checkbox':
        case 'Switch':
        case 'ListTile':
        case 'Card':
        case 'Tab':
          await _tapWidget(widget);
          break;
        default:
          if (widget.widgetType.contains('Button')) {
            await _tapWidget(widget);
          } else {
            return InteractionOutcome.noVisibleChange;
          }
      }

      final outcome = await _assessOutcome(
        routeBefore: routeBefore,
        signatureBefore: signatureBefore,
      );
      final assertion = behaviorAssertions.evaluate(
        widgetType: widget.widgetType,
        outcome: outcome,
        formPresent: _formIsPresent(),
        emptyState: _isEmptyState(),
      );
      final probe = await adapter.probeOutcome(
        _journeyIdHint(route, widget.widgetType),
        route,
        outcome,
      );
      _interactions.add(
        TestedInteraction(
          route: route,
          widgetType: widget.widgetType,
          action: _actionForWidget(widget.widgetType),
          outcome: outcome,
          assertion: assertion,
          outcomeProbe: probe,
        ),
      );
      logger.outcome(
        route: route,
        widget: widget.widgetType,
        outcome: outcome.name,
        assertionPassed: assertion.passed,
        probePassed: probe?.passed,
      );
      if (!assertion.passed) {
        _defects.add(
          FoundDefect(
            route: route,
            action: 'interact:${widget.widgetType}',
            description: assertion.failureReason ?? 'Unexpected behavior',
            severity: DefectSeverity.behaviorViolation,
            violatedExpectation: assertion.expectation,
          ),
        );
      }
      if (probe != null && !probe.passed) {
        _defects.add(
          FoundDefect(
            route: route,
            action: 'probe:${widget.widgetType}',
            description: probe.details ?? 'Outcome probe failed',
            severity: DefectSeverity.behaviorViolation,
          ),
        );
      }
      return outcome;
    } catch (error) {
      _defects.add(
        FoundDefect(
          route: route,
          action: 'interact:${widget.widgetType}',
          description: error.toString(),
          severity: DefectSeverity.crash,
          violatedExpectation: BehaviorExpectation.appStaysAlive,
        ),
      );
      return InteractionOutcome.crash;
    }
  }

  List<DiscoveredWidget> _discoverInteractiveWidgets() {
    final discovered = <DiscoveredWidget>[];
    void addFromFinder(String type, Finder finder) {
      for (final candidate in finder.evaluate()) {
        discovered.add(
          DiscoveredWidget(
            widgetType: type,
            label: _labelForElement(candidate),
            semanticsLabel: _semanticsLabelForElement(candidate),
          ),
        );
      }
    }

    void addByPredicate(String type, bool Function(Widget widget) predicate) {
      addFromFinder(
        type,
        find.byWidgetPredicate(
          predicate,
          description: 'widgets assignable to $type',
        ),
      );
    }

    addFromFinder('TextFormField', find.byType(TextFormField));
    addByPredicate('ElevatedButton', (widget) => widget is ElevatedButton);
    addByPredicate('TextButton', (widget) => widget is TextButton);
    addByPredicate('FilledButton', (widget) => widget is FilledButton);
    addByPredicate('OutlinedButton', (widget) => widget is OutlinedButton);
    addByPredicate('IconButton', (widget) => widget is IconButton);
    addByPredicate(
      'FloatingActionButton',
      (widget) => widget is FloatingActionButton,
    );
    addFromFinder('DropdownButton', find.byType(DropdownButton));
    addFromFinder('Checkbox', find.byType(Checkbox));
    addFromFinder('Switch', find.byType(Switch));
    addByPredicate('ListTile', (widget) => widget is ListTile);
    addByPredicate('Card', (widget) => widget is Card);
    addByPredicate('Tab', (widget) => widget is Tab);
    addByPredicate(
      'NavigationDestination',
      (widget) => widget is NavigationDestination,
    );

    for (final finder in adapter.additionalInteractiveWidgetFinders()) {
      for (final element in finder.evaluate()) {
        discovered.add(
          DiscoveredWidget(
            widgetType: element.widget.runtimeType.toString(),
            label: _labelForElement(element),
            semanticsLabel: _semanticsLabelForElement(element),
          ),
        );
      }
    }

    final dedup = <String, DiscoveredWidget>{};
    for (final widget in discovered) {
      final key = _widgetKey(widget);
      dedup.putIfAbsent(key, () => widget);
    }
    final widgets = dedup.values.toList();
    if (_formIsPresent()) {
      widgets.sort((left, right) {
        final leftPriority = _explorationPriority(left);
        final rightPriority = _explorationPriority(right);
        return leftPriority.compareTo(rightPriority);
      });
    }
    return widgets;
  }

  Future<void> _fillTextField(DiscoveredWidget widget) async {
    final finder = _finderForTextField(widget);
    if (finder.evaluate().isEmpty) {
      return;
    }
    final value = inputStrategy.generateText(
      keyboardType: null,
      label: widget.label,
    );
    await tester.enterText(finder.first, value);
    await _settle();
  }

  Future<void> _tapWidget(DiscoveredWidget widget) async {
    var finder = _finderForWidget(widget);
    if (finder.evaluate().isEmpty) {
      return;
    }
    await tester.ensureVisible(finder.first);
    await _settle();
    finder = _finderForWidget(widget);
    if (finder.evaluate().isEmpty) {
      return;
    }
    await tester.tap(finder.first);
    await _settle();
  }

  Future<InteractionOutcome> _assessOutcome({
    required String routeBefore,
    required String signatureBefore,
  }) async {
    final deadline = DateTime.now().add(
      interactionTimeout > const Duration(milliseconds: 1500)
          ? const Duration(milliseconds: 1500)
          : interactionTimeout,
    );

    while (DateTime.now().isBefore(deadline)) {
      if (_hasRedScreen()) {
        return InteractionOutcome.crash;
      }

      final currentRoute = _currentRoute();
      if (currentRoute != routeBefore) {
        return InteractionOutcome.navigationOccurred;
      }
      if (find.byType(SnackBar).evaluate().isNotEmpty) {
        return InteractionOutcome.snackBarShown;
      }
      if (_hasValidationFeedback()) {
        return InteractionOutcome.validationError;
      }
      if (_uiSignature() != signatureBefore) {
        return InteractionOutcome.contentChanged;
      }

      await tester.pump(const Duration(milliseconds: 150));
    }

    return InteractionOutcome.noVisibleChange;
  }

  String _currentRoute() {
    try {
      final materialAppFinder = find.byType(MaterialApp);
      if (materialAppFinder.evaluate().isNotEmpty) {
        final materialApp = tester.widget<MaterialApp>(materialAppFinder.first);
        final routerConfig = materialApp.routerConfig;
        final routeInformationProvider =
            (routerConfig as dynamic).routeInformationProvider;
        final routeInformation = routeInformationProvider?.value;
        final uri = routeInformation?.uri;
        final location = uri?.toString() ?? routeInformation?.location;
        if (location is String && location.trim().isNotEmpty) {
          return location.trim();
        }
      }
    } catch (_) {
      // Continue with scaffold-backed route detection.
    }

    final candidateElements = <Element>[
      ...find.byType(TextFormField).evaluate(),
      ...find.byType(EditableText).evaluate(),
      ...find.byType(Form).evaluate(),
      ...find.byType(AppBar).evaluate(),
      ...find.byType(Scaffold).evaluate(),
    ];
    final resolvedRoutes = <String>{};
    for (final element in candidateElements.reversed) {
      try {
        final state = GoRouterState.of(element);
        final matchedLocation = state.matchedLocation.trim();
        if (matchedLocation.isNotEmpty) {
          resolvedRoutes.add(matchedLocation);
        }
      } catch (_) {
        // Continue with other route detection strategies.
      }
    }
    if (resolvedRoutes.isNotEmpty) {
      final sortedRoutes = resolvedRoutes.toList()
        ..sort(
          (left, right) =>
              right.split('/').length.compareTo(left.split('/').length),
        );
      return sortedRoutes.first;
    }
    return '/unknown';
  }

  Finder _finderForTextField(DiscoveredWidget widget) {
    return find.byType(TextFormField).hitTestable();
  }

  Finder _finderForWidget(DiscoveredWidget widget) {
    final label = widget.label?.trim();
    if (label != null && label.isNotEmpty) {
      if (widget.widgetType.contains('Button')) {
        final buttonAncestor = find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (candidate) =>
                    _matchesDiscoveredType(candidate, widget.widgetType),
                description: 'ancestor ${widget.widgetType} for "$label"',
              ),
            )
            .hitTestable();
        if (buttonAncestor.evaluate().isNotEmpty) {
          return buttonAncestor;
        }
      }
      final textFinder = find.text(label).hitTestable();
      if (textFinder.evaluate().isNotEmpty) {
        return textFinder;
      }
    }

    final semanticsLabel = widget.semanticsLabel?.trim();
    if (semanticsLabel != null && semanticsLabel.isNotEmpty) {
      final semanticsFinder = find
          .bySemanticsLabel(semanticsLabel)
          .hitTestable();
      if (semanticsFinder.evaluate().isNotEmpty) {
        return semanticsFinder;
      }
      final tooltipFinder = find.byTooltip(semanticsLabel).hitTestable();
      if (tooltipFinder.evaluate().isNotEmpty) {
        return tooltipFinder;
      }
    }

    return find
        .byWidgetPredicate(
          (candidate) => _matchesDiscoveredType(candidate, widget.widgetType),
        )
        .hitTestable();
  }

  bool _matchesDiscoveredType(Widget candidate, String widgetType) {
    switch (widgetType) {
      case 'ElevatedButton':
        return candidate is ElevatedButton;
      case 'TextButton':
        return candidate is TextButton;
      case 'FilledButton':
        return candidate is FilledButton;
      case 'OutlinedButton':
        return candidate is OutlinedButton;
      case 'IconButton':
        return candidate is IconButton;
      case 'FloatingActionButton':
        return candidate is FloatingActionButton;
      case 'ListTile':
        return candidate is ListTile;
      case 'Card':
        return candidate is Card;
      case 'Tab':
        return candidate is Tab;
      case 'NavigationDestination':
        return candidate is NavigationDestination;
      default:
        return candidate.runtimeType.toString() == widgetType;
    }
  }

  String? _labelForWidget(Widget widget) {
    if (widget is NavigationDestination) {
      return widget.label;
    }
    if (widget is Tab) {
      return widget.text;
    }
    if (widget is IconButton) {
      return widget.tooltip;
    }
    if (widget is ListTile) {
      return _textFromWidget(widget.title) ?? _textFromWidget(widget.subtitle);
    }
    if (widget is Card) {
      return _textFromWidget(widget.child);
    }
    if (widget is DropdownButton) {
      return _textFromWidget(widget.hint);
    }
    if (widget is ElevatedButton) {
      return _textFromWidget(widget.child);
    }
    if (widget is FilledButton) {
      return _textFromWidget(widget.child);
    }
    if (widget is OutlinedButton) {
      return _textFromWidget(widget.child);
    }
    if (widget is TextButton) {
      return _textFromWidget(widget.child);
    }
    if (widget is FloatingActionButton) {
      return _textFromWidget(widget.child) ?? widget.tooltip;
    }
    return _textFromWidget(widget);
  }

  String? _labelForElement(Element element) {
    return _firstNonEmptyTextInSubtree(element) ??
        _labelForWidget(element.widget);
  }

  String? _semanticsLabelForWidget(Widget widget) {
    if (widget is IconButton) {
      return widget.tooltip;
    }
    if (widget is FloatingActionButton) {
      return widget.tooltip;
    }
    return null;
  }

  String? _semanticsLabelForElement(Element element) {
    return _firstSemanticsLabelInSubtree(element) ??
        _semanticsLabelForWidget(element.widget);
  }

  String? _firstNonEmptyTextInSubtree(Element element) {
    final direct = _textFromWidget(element.widget);
    if (_looksLikeSemanticText(direct)) {
      return direct;
    }

    String? found;
    void visit(Element current) {
      if (found != null) {
        return;
      }
      final text = _textFromWidget(current.widget);
      if (_looksLikeSemanticText(text)) {
        found = text;
        return;
      }
      current.visitChildren(visit);
    }

    element.visitChildren(visit);
    return found;
  }

  bool _looksLikeSemanticText(String? text) {
    if (text == null) {
      return false;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return RegExp(r'[A-Za-z0-9]').hasMatch(trimmed);
  }

  String? _firstSemanticsLabelInSubtree(Element element) {
    final direct = _semanticsLabelForWidget(element.widget);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    String? found;
    void visit(Element current) {
      if (found != null) {
        return;
      }
      final semantics = _semanticsLabelForWidget(current.widget);
      if (semantics != null && semantics.isNotEmpty) {
        found = semantics;
        return;
      }
      current.visitChildren(visit);
    }

    element.visitChildren(visit);
    return found;
  }

  String? _textFromWidget(Widget? widget) {
    if (widget == null) {
      return null;
    }
    if (widget is Text) {
      return widget.data?.trim();
    }
    if (widget is RichText) {
      return widget.text.toPlainText().trim();
    }
    if (widget is Tooltip) {
      return widget.message;
    }
    if (widget is SizedBox) {
      return _textFromWidget(widget.child);
    }
    if (widget is Padding) {
      return _textFromWidget(widget.child);
    }
    if (widget is Center) {
      return _textFromWidget(widget.child);
    }
    if (widget is Align) {
      return _textFromWidget(widget.child);
    }
    if (widget is Semantics) {
      return widget.properties.label ?? _textFromWidget(widget.child);
    }
    return null;
  }

  String _journeyIdHint(String route, String widgetType) {
    final segments = route
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return widgetType.toLowerCase();
    }
    final buffer = StringBuffer();
    for (final segment in segments) {
      if (segment.startsWith(':')) {
        continue;
      }
      if (buffer.isNotEmpty) {
        buffer.write('_');
      }
      buffer.write(segment.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_'));
    }
    if (widgetType.toLowerCase().contains('button')) {
      buffer.write('_action');
    }
    return buffer.isEmpty ? widgetType.toLowerCase() : buffer.toString();
  }

  String _widgetKey(DiscoveredWidget widget) => [
    widget.widgetType,
    widget.label ?? '',
    widget.semanticsLabel ?? '',
  ].join('|');

  int _explorationPriority(DiscoveredWidget widget) {
    if (widget.widgetType.contains('Button')) {
      return 0;
    }
    if (widget.widgetType == 'DropdownButton' ||
        widget.widgetType == 'SegmentedButton' ||
        widget.widgetType == 'Checkbox' ||
        widget.widgetType == 'Switch') {
      return 1;
    }
    if (widget.widgetType == 'TextFormField') {
      return 2;
    }
    return 3;
  }

  int _maxInteractionsForWidget(DiscoveredWidget widget) {
    if (_formIsPresent() && widget.widgetType.contains('Button')) {
      return 2;
    }
    return 1;
  }

  bool _allGapHintsVisited() {
    if (gapHints.isEmpty) {
      return false;
    }
    return gapHints.every(
      (hint) => _visited.keys.any((route) => route == hint),
    );
  }

  Future<bool> _navigateBack({required String targetRoute}) async {
    if (_currentRoute() == targetRoute) {
      return true;
    }

    if (targetRoute.trim().isNotEmpty && targetRoute != '/unknown') {
      final rerouted = await _navigateToRoute(targetRoute);
      if (rerouted) {
        return true;
      }
    }

    final scaffoldElements = find.byType(Scaffold).evaluate().toList();
    for (final element in scaffoldElements) {
      try {
        final navigator = Navigator.maybeOf(element);
        if (navigator?.canPop() ?? false) {
          navigator!.pop();
          await _settle();
          if (_currentRoute() == targetRoute) {
            return true;
          }
        }
      } catch (_) {
        // Fall through to more generic back mechanisms.
      }
    }

    final backFinders = <Finder>[
      find.byType(BackButton).hitTestable(),
      find.byIcon(Icons.arrow_back).hitTestable(),
      find.byIcon(Icons.arrow_back_ios).hitTestable(),
      find.byIcon(Icons.arrow_back_ios_new).hitTestable(),
      find.byTooltip('Back').hitTestable(),
      find.bySemanticsLabel('Back').hitTestable(),
      find.text('Back').hitTestable(),
    ];
    for (final finder in backFinders) {
      if (finder.evaluate().isEmpty) {
        continue;
      }
      try {
        await tester.tap(finder.first);
        await _settle();
        if (_currentRoute() == targetRoute) {
          return true;
        }
      } catch (_) {
        // Try the next back strategy.
      }
    }

    return _currentRoute() == targetRoute;
  }

  bool _isEmptyState() {
    final hasListContent =
        find.byType(ListTile).evaluate().isNotEmpty ||
        find.byType(Card).evaluate().isNotEmpty;
    final hasCta =
        find.byType(FilledButton).evaluate().isNotEmpty ||
        find.byType(ElevatedButton).evaluate().isNotEmpty;
    if (hasListContent || !hasCta) {
      return false;
    }
    for (final marker in adapter.emptyStateMarkers()) {
      if (find
          .textContaining(marker, findRichText: true)
          .evaluate()
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _hasVisibleContent() {
    return find.byType(Scaffold).evaluate().isNotEmpty;
  }

  bool _formIsPresent() {
    return find.byType(Form).evaluate().isNotEmpty ||
        find.byType(TextFormField).evaluate().isNotEmpty;
  }

  bool _hasRedScreen() => find.byType(ErrorWidget).evaluate().isNotEmpty;

  bool _isBackLikeControl(DiscoveredWidget widget) {
    final value = [
      widget.label ?? '',
      widget.semanticsLabel ?? '',
    ].join(' ').trim().toLowerCase();
    if (value.isEmpty) {
      return false;
    }
    return adapter.backNavigationMarkers().any(value.contains);
  }

  bool _isEmptyStateQueueAction(DiscoveredWidget widget) {
    if (_isBackLikeControl(widget)) {
      return true;
    }
    return widget.widgetType.contains('Button') ||
        widget.widgetType == 'NavigationDestination' ||
        widget.widgetType == 'ListTile';
  }

  bool _shouldSkipRouteLocalNavigation(DiscoveredWidget widget, String route) {
    if (widget.widgetType != 'NavigationDestination') {
      return false;
    }
    final segments = route.split('/').where((segment) => segment.isNotEmpty);
    return segments.length > 1;
  }

  bool _hasValidationFeedback() {
    for (final pattern in adapter.validationFeedbackPatterns()) {
      if (find
          .textContaining(pattern, findRichText: true)
          .evaluate()
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  String _actionForWidget(String widgetType) {
    if (widgetType == 'TextFormField') {
      return 'enterText';
    }
    if (widgetType == 'Checkbox' || widgetType == 'Switch') {
      return 'toggle';
    }
    if (widgetType == 'DropdownButton' || widgetType == 'SegmentedButton') {
      return 'select';
    }
    return 'tap';
  }

  /// Pumps the widget tree without using pumpAndSettle() to avoid hangs
  /// on infinite animations (loading spinners, shimmer effects).
  /// Short delay intentional - longer waits happen in _waitForRouteReady()
  /// via stability sampling.
  Future<void> _settle() async {
    await tester.pump();
    await tester.pump(
      interactionTimeout > const Duration(milliseconds: 250)
          ? const Duration(milliseconds: 250)
          : interactionTimeout,
    );
  }

  String _uiSignature() {
    final labels = <String>[
      for (final text in find.byType(Text).evaluate())
        _textFromWidget(text.widget) ?? '',
    ]..sort();
    return [
      _currentRoute(),
      find.byType(TextFormField).evaluate().length,
      find.byType(FilledButton).evaluate().length,
      find.byType(OutlinedButton).evaluate().length,
      find.byType(TextButton).evaluate().length,
      find.byType(ListTile).evaluate().length,
      find.byType(Card).evaluate().length,
      labels.take(8).join('|'),
    ].join('::');
  }

  Future<void> _waitForInteractiveUi() async {
    final deadline = DateTime.now().add(interactionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await _settle();
      if (_currentRoute() != '/unknown') {
        return;
      }
      if (_hasVisibleContent()) {
        return;
      }
      if (find.byType(TextFormField).evaluate().isNotEmpty ||
          find.byType(NavigationBar).evaluate().isNotEmpty ||
          find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        return;
      }
    }
  }

  Future<void> _waitForAuthenticatedUi() async {
    final deadline = DateTime.now().add(interactionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await _settle();
      final route = _currentRoute();
      if (route.isNotEmpty && route != '/unknown' && route != '/login') {
        return;
      }
      if (find.byType(NavigationBar).evaluate().isNotEmpty ||
          find.byType(BottomNavigationBar).evaluate().isNotEmpty) {
        return;
      }
    }
  }

  Future<void> _waitForRouteReady(String route) async {
    var stableSamples = 0;
    var previousCount = -1;
    final deadline = DateTime.now().add(interactionTimeout);

    while (DateTime.now().isBefore(deadline)) {
      await _settle();

      if (_currentRoute() != route) {
        return;
      }

      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
          find.byType(LinearProgressIndicator).evaluate().isNotEmpty) {
        stableSamples = 0;
        previousCount = -1;
        continue;
      }

      final currentCount = _discoverInteractiveWidgets().length;
      if (currentCount == previousCount) {
        stableSamples += 1;
      } else {
        stableSamples = 0;
        previousCount = currentCount;
      }

      if (stableSamples >= 2) {
        return;
      }
    }
  }
}
