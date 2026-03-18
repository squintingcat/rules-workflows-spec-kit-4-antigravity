import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import '../../pathing/src/models.dart';

abstract interface class EmptyStateMarkerProvider {
  /// Markers that indicate an empty-state screen (e.g., 'kein', 'empty').
  List<String> emptyStateMarkers();
}

abstract interface class ValidationFeedbackProvider {
  /// Patterns that indicate a validation error is visible (e.g., 'required', 'pflicht').
  List<String> validationFeedbackPatterns();
}

abstract interface class BackNavigationMarkerProvider {
  /// Markers that indicate a back or close affordance in the current locale.
  List<String> backNavigationMarkers();
}

abstract class ProjectAdapter {
  Future<void> ensureAppStarted(WidgetTester tester);

  Future<void> restartApp(WidgetTester tester);

  Future<void> performLogin(WidgetTester tester);

  Future<bool> navigateToRoute(WidgetTester tester, String route);

  Future<void> seedForRoute(String route);

  Future<String?> materializeRoute(String routePattern);

  Future<void> cleanup();

  Future<void> handlePermissions(PatrolIntegrationTester patrolTester);

  List<Finder> additionalInteractiveWidgetFinders();

  Future<OutcomeProbeResult?> probeOutcome(
    String journeyId,
    String route,
    InteractionOutcome outcome,
  );
}

extension ProjectAdapterMarkers on ProjectAdapter {
  /// Markers that indicate an empty-state screen (e.g., 'kein', 'empty').
  List<String> emptyStateMarkers() {
    final adapter = this;
    if (adapter is EmptyStateMarkerProvider) {
      return adapter.emptyStateMarkers();
    }
    return const <String>[];
  }

  /// Patterns that indicate a validation error is visible (e.g., 'required', 'pflicht').
  List<String> validationFeedbackPatterns() {
    final adapter = this;
    if (adapter is ValidationFeedbackProvider) {
      return adapter.validationFeedbackPatterns();
    }
    return const <String>[];
  }

  /// Markers that indicate a back or close affordance in the current locale.
  List<String> backNavigationMarkers() {
    final adapter = this;
    if (adapter is BackNavigationMarkerProvider) {
      return adapter.backNavigationMarkers();
    }
    return const <String>['back', 'close'];
  }
}
