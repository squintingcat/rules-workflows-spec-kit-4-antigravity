import '../../pathing/src/models.dart';

class BehaviorAssertions {
  const BehaviorAssertions();

  BehaviorAssertion evaluate({
    required String widgetType,
    required InteractionOutcome outcome,
    required bool formPresent,
    required bool emptyState,
  }) {
    if (widgetType.contains('Button') && formPresent) {
      if (outcome == InteractionOutcome.validationError) {
        return const BehaviorAssertion(
          expectation: BehaviorExpectation.validationErrorOnEmptyRequired,
          passed: true,
        );
      }
      if (outcome == InteractionOutcome.noVisibleChange) {
        return const BehaviorAssertion(
          expectation: BehaviorExpectation.feedbackAfterSubmit,
          passed: true,
        );
      }
      final passed =
          outcome == InteractionOutcome.navigationOccurred ||
          outcome == InteractionOutcome.snackBarShown ||
          outcome == InteractionOutcome.validationError ||
          outcome == InteractionOutcome.contentChanged;
      return BehaviorAssertion(
        expectation: BehaviorExpectation.feedbackAfterSubmit,
        passed: passed,
        failureReason: passed
            ? null
            : 'Form submit produced no visible feedback: ${outcome.name}',
      );
    }

    if (emptyState && widgetType.contains('Button')) {
      final passed =
          outcome == InteractionOutcome.navigationOccurred ||
          outcome == InteractionOutcome.dialogOpened ||
          outcome == InteractionOutcome.contentChanged;
      return BehaviorAssertion(
        expectation: BehaviorExpectation.navigationOnCTATap,
        passed: passed,
        failureReason: passed
            ? null
            : 'Empty-state CTA produced no navigation/content change: ${outcome.name}',
      );
    }

    if (widgetType == 'ListTile' || widgetType == 'Card') {
      final passed =
          outcome == InteractionOutcome.navigationOccurred ||
          outcome == InteractionOutcome.dialogOpened;
      return BehaviorAssertion(
        expectation: BehaviorExpectation.navigationOnListItemTap,
        passed: passed,
        failureReason: passed
            ? null
            : 'List interaction produced no navigation/dialog: ${outcome.name}',
      );
    }

    if (widgetType == 'Tab') {
      final passed =
          outcome == InteractionOutcome.contentChanged ||
          outcome == InteractionOutcome.navigationOccurred;
      return BehaviorAssertion(
        expectation: BehaviorExpectation.contentChangeOnTabSwitch,
        passed: passed,
        failureReason: passed
            ? null
            : 'Tab switch produced no content change: ${outcome.name}',
      );
    }

    final passed =
        outcome != InteractionOutcome.crash &&
        outcome != InteractionOutcome.timeout;
    return BehaviorAssertion(
      expectation: BehaviorExpectation.appStaysAlive,
      passed: passed,
      failureReason: passed ? null : 'Interaction destabilized the app.',
    );
  }
}
