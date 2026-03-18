// ignore_for_file: avoid_print

/// Logger for explorer runtime output.
/// Uses print intentionally - this is test infrastructure, not feature code.
/// Output is parsed by materialize_exploration_reports.dart.
class ExplorerLogger {
  const ExplorerLogger();

  void screen({
    required String route,
    required int widgets,
    required int depth,
  }) {
    print('EXPLORER_SCREEN route=$route widgets=$widgets depth=$depth');
  }

  void action({
    required String route,
    required String widget,
    String? label,
    String? semantics,
  }) {
    print(
      'EXPLORER_ACTION route=$route widget=$widget label=${label ?? ''} semantics=${semantics ?? ''}',
    );
  }

  void outcome({
    required String route,
    required String widget,
    required String outcome,
    required bool assertionPassed,
    bool? probePassed,
  }) {
    print(
      'EXPLORER_OUTCOME route=$route widget=$widget outcome=$outcome assertion=$assertionPassed${probePassed == null ? '' : ' probe=$probePassed'}',
    );
  }

  void gapHint({required String target, required String source}) {
    print('EXPLORER_GAP_HINT target=$target source=$source');
  }
}
