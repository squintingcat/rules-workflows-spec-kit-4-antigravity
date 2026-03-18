import '../../pathing/src/models.dart';

class CoverageFeedback {
  const CoverageFeedback();

  CoverageGap compute({
    required GroundTruthModel groundTruth,
    required ExplorationResult explorationResult,
  }) {
    final allRoutes = groundTruth.routes.map((route) => route.path).toSet();
    final visitedRoutes = explorationResult.visitedRoutes.toSet();
    final coveredRoutes = allRoutes
        .where(
          (groundTruthRoute) => visitedRoutes.any(
            (visitedRoute) =>
                routePatternMatches(groundTruthRoute, visitedRoute),
          ),
        )
        .toSet();
    final missedRoutes =
        allRoutes
            .where(
              (groundTruthRoute) => !visitedRoutes.any(
                (visitedRoute) =>
                    routePatternMatches(groundTruthRoute, visitedRoute),
              ),
            )
            .toList()
          ..sort();
    final coveredForms = explorationResult.interactions
        .where(
          (interaction) =>
              interaction.assertion.expectation ==
                  BehaviorExpectation.feedbackAfterSubmit ||
              interaction.assertion.expectation ==
                  BehaviorExpectation.validationErrorOnEmptyRequired,
        )
        .length;
    final guardHits = explorationResult.interactions
        .where(
          (interaction) =>
              interaction.assertion.expectation ==
                  BehaviorExpectation.validationErrorOnEmptyRequired ||
              (interaction.widgetType.contains('Button') &&
                  interaction.outcome == InteractionOutcome.noVisibleChange),
        )
        .length;
    final missedSubjourneys =
        groundTruth.routes
            .expand((route) => route.subjourneys)
            .where(
              (subjourney) => !explorationResult.visitedRoutes.any(
                (route) => route.contains(subjourney),
              ),
            )
            .toSet()
            .toList()
          ..sort();

    return CoverageGap(
      routeCoverage: allRoutes.isEmpty
          ? 1.0
          : _clampRatio(coveredRoutes.length, allRoutes.length),
      elementCoverage: groundTruth.totalInteractiveElements == 0
          ? 1.0
          : _clampRatio(
              explorationResult.interactions.length,
              groundTruth.totalInteractiveElements,
            ),
      formCoverage: groundTruth.formSubmits == 0
          ? 1.0
          : _clampRatio(coveredForms, groundTruth.formSubmits),
      guardCoverage: groundTruth.guards.isEmpty
          ? 1.0
          : _clampRatio(guardHits, groundTruth.guards.length),
      missedRoutes: missedRoutes,
      missedSubjourneys: missedSubjourneys,
      prioritizedHints: _generateHints(missedRoutes),
    );
  }

  List<String> _generateHints(List<String> missedRoutes) {
    final hints = <String>[];
    for (final route in missedRoutes) {
      if (route.contains('/:')) {
        hints.add('NEEDS_ENTITY:$route');
      } else if (route.endsWith('/create') || route.endsWith('/add')) {
        hints.add('CTA:$route');
      } else {
        hints.add('PRIORITY:$route');
      }
    }
    return hints..sort();
  }

  double _clampRatio(int numerator, int denominator) {
    if (denominator <= 0) {
      return 1.0;
    }
    final ratio = numerator / denominator;
    if (ratio < 0) {
      return 0.0;
    }
    if (ratio > 1) {
      return 1.0;
    }
    return ratio;
  }
}
