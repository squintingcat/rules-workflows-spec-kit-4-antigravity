import 'models.dart';

class JourneyDiffBuilder {
  JourneyDiffReport build({
    required List<JourneyClassification> classifications,
    required Map<String, List<String>> pathToCoverageReferences,
    Map<String, List<String>> journeyRouteHints =
        const <String, List<String>>{},
    ExplorationResult? explorationResult,
  }) {
    final entries = <JourneyDiffEntry>[];
    final visitedRoutes =
        explorationResult?.visitedRoutes.toSet() ?? const <String>{};
    final probesByJourney = <String, List<OutcomeProbeResult>>{};
    if (explorationResult != null) {
      for (final interaction in explorationResult.interactions) {
        final probe = interaction.outcomeProbe;
        if (probe == null) continue;
        final probeKey = probe.journeyId ?? interaction.route;
        probesByJourney
            .putIfAbsent(probeKey, () => <OutcomeProbeResult>[])
            .add(probe);
      }
    }

    for (final classification in classifications) {
      final oldCovered =
          (pathToCoverageReferences[classification.journeyId] ??
                  const <String>[])
              .isNotEmpty;
      if (classification.bucket == JourneyBucket.cDomainOracleRequired) {
        entries.add(
          JourneyDiffEntry(
            journeyId: classification.journeyId,
            bucket: classification.bucket,
            expectedOutcome: classification.expectedOutcome,
            oldCovered: oldCovered,
            newCovered: oldCovered,
            outcomeParity: oldCovered,
            reason: oldCovered
                ? null
                : 'No domain-oracle coverage exists for this journey yet.',
          ),
        );
        continue;
      }
      final probeCovered = probesByJourney.containsKey(
        classification.journeyId,
      );
      final newCovered = _isExplorationCovered(
        classification,
        visitedRoutes,
        explorationResult,
        probeCovered: probeCovered,
        routeHints:
            journeyRouteHints[classification.journeyId] ?? const <String>[],
      );
      final outcomeParity = _hasOutcomeParity(
        classification,
        probesByJourney,
        newCovered,
      );
      entries.add(
        JourneyDiffEntry(
          journeyId: classification.journeyId,
          bucket: classification.bucket,
          expectedOutcome: classification.expectedOutcome,
          oldCovered: oldCovered,
          newCovered: newCovered,
          outcomeParity: outcomeParity,
          reason: oldCovered && !newCovered
              ? 'Explorer did not cover this journey yet.'
              : (!outcomeParity
                    ? 'Expected outcome family not confirmed.'
                    : null),
        ),
      );
    }

    return JourneyDiffReport(
      entries: entries,
      noRegressionModules: const <String>[
        'auth',
        'group',
        'horse',
        'ride',
        'task',
      ],
    );
  }

  bool _isExplorationCovered(
    JourneyClassification classification,
    Set<String> visitedRoutes,
    ExplorationResult? explorationResult, {
    required bool probeCovered,
    required List<String> routeHints,
  }) {
    if (explorationResult == null) {
      return false;
    }
    if (probeCovered) {
      return true;
    }
    if (classification.bucket == JourneyBucket.bAdapterRequired &&
        _routeHintVisited(visitedRoutes, routeHints)) {
      return true;
    }
    if (visitedRoutes.any(
      (route) => route.contains(classification.journeyId),
    )) {
      return true;
    }
    if (_matchesRouteHints(
      classification: classification,
      visitedRoutes: visitedRoutes,
      explorationResult: explorationResult,
      routeHints: routeHints,
    )) {
      return true;
    }
    return explorationResult.interactions.any(
      (interaction) =>
          interaction.route.contains(classification.journeyId) ||
          interaction.action.contains(classification.journeyId),
    );
  }

  bool _matchesRouteHints({
    required JourneyClassification classification,
    required Set<String> visitedRoutes,
    required ExplorationResult explorationResult,
    required List<String> routeHints,
  }) {
    if (routeHints.isEmpty) {
      return false;
    }

    bool interactionOnHint(
      bool Function(TestedInteraction interaction) predicate,
    ) {
      return explorationResult.interactions.any((interaction) {
        final matchesHint = routeHints.any(
          (hint) =>
              routePatternMatches(hint, interaction.route) ||
              routePatternMatches(
                hint,
                interaction.route,
                allowChildSegments: true,
              ),
        );
        return matchesHint && predicate(interaction);
      });
    }

    switch (classification.expectedOutcome) {
      case OutcomeFamily.navigationSucceeded:
      case OutcomeFamily.sessionChanged:
        return _routeHintVisited(visitedRoutes, routeHints);
      case OutcomeFamily.validationBlocked:
        return interactionOnHint(
          (interaction) =>
              interaction.outcome == InteractionOutcome.validationError ||
              (interaction.widgetType.contains('Button') &&
                  interaction.outcome == InteractionOutcome.noVisibleChange) ||
              interaction.assertion.expectation ==
                  BehaviorExpectation.validationErrorOnEmptyRequired,
        );
      case OutcomeFamily.feedbackShown:
        return interactionOnHint(
          (interaction) =>
              interaction.outcome == InteractionOutcome.snackBarShown,
        );
      case OutcomeFamily.entityCreated:
      case OutcomeFamily.entityUpdated:
      case OutcomeFamily.entityDeleted:
      case OutcomeFamily.dataRecorded:
        return interactionOnHint(
          (interaction) =>
              interaction.outcome == InteractionOutcome.navigationOccurred ||
              interaction.outcome == InteractionOutcome.snackBarShown,
        );
    }
  }

  bool _routeHintVisited(Set<String> visitedRoutes, List<String> routeHints) {
    if (routeHints.isEmpty) {
      return false;
    }
    return routeHints.any(
      (candidate) =>
          visitedRoutes.any((route) => routePatternMatches(candidate, route)) ||
          visitedRoutes.any(
            (route) =>
                routePatternMatches(candidate, route, allowChildSegments: true),
          ),
    );
  }

  bool _hasOutcomeParity(
    JourneyClassification classification,
    Map<String, List<OutcomeProbeResult>> probesByJourney,
    bool newCovered,
  ) {
    if (!newCovered) return false;
    if (!classification.needsOutcomeProbe) return true;

    final probes =
        probesByJourney[classification.journeyId] ??
        const <OutcomeProbeResult>[];
    return probes.any(
      (probe) => probe.family == classification.expectedOutcome && probe.passed,
    );
  }
}
