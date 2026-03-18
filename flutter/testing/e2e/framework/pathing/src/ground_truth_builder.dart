import 'models.dart';

class GroundTruthBuilder {
  GroundTruthModel build({
    required List<FileSignals> fileSignals,
    required Map<String, List<String>> routeBindings,
  }) {
    final routeEntries = <String, RouteGroundTruth>{};
    final entryScreens = <String>{};
    final guardSet = <String>{};
    final dialogs = <String>{};
    final parameterized = <String>{};
    var totalInteractiveElements = 0;
    var formSubmits = 0;

    for (final signal in fileSignals) {
      totalInteractiveElements +=
          signal.uiActions.length + signal.widgets.length + signal.forms.length;
      formSubmits += signal.forms.length;
      guardSet.addAll(signal.guards);
      if (signal.filePath.endsWith('_dialog.dart')) {
        dialogs.addAll(
          signal.widgets.isEmpty
              ? <String>{signal.filePath.split('/').last}
              : signal.widgets.toSet(),
        );
      }

      final classes = <String>{...signal.screens, ...signal.widgets};
      final interactiveElements = <String>{
        ...signal.uiActions,
        ...signal.widgets,
        ...signal.forms,
      };
      final sequentialTransitions = signal.navigationTransitions
          .where((route) => route.startsWith('/'))
          .toSet();
      final subjourneys = signal.instantiatedWidgets
          .where(
            (widget) =>
                widget.toLowerCase().contains('tab') ||
                widget.toLowerCase().contains('dialog') ||
                widget.toLowerCase().contains('view'),
          )
          .map(
            (widget) => widget
                .replaceAll('Widget', '')
                .replaceAll('Screen', '')
                .replaceAll('View', '_view')
                .replaceAll('Dialog', '_dialog')
                .toLowerCase(),
          )
          .toSet();

      for (final className in classes) {
        for (final route in routeBindings[className] ?? const <String>[]) {
          if (route.contains('/:')) {
            parameterized.add(route);
          }
          if (signal.filePath.endsWith('_screen.dart') ||
              signal.filePath.endsWith('_view.dart')) {
            entryScreens.add(route);
          }
          routeEntries[route] = RouteGroundTruth(
            path: route,
            screen: className,
            authRequired:
                signal.guards.any(
                  (guard) => guard.toLowerCase().contains('auth'),
                ) ||
                route != '/login',
            hasForm: signal.forms.isNotEmpty,
            guards: signal.guards,
            parent: _parentRoute(route),
            subjourneys: subjourneys.toList(),
            sequentialTransitions: sequentialTransitions.toList(),
            interactiveElements: interactiveElements.toList(),
          );
        }
      }
    }

    return GroundTruthModel(
      routes: routeEntries.values.toList(),
      entryScreens: entryScreens.toList(),
      guards: guardSet.toList(),
      dialogs: dialogs.toList(),
      parameterizedRouteFamilies: parameterized.toList(),
      totalInteractiveElements: totalInteractiveElements,
      formSubmits: formSubmits,
    );
  }

  String? _parentRoute(String route) {
    final parts = route.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.length <= 1) {
      return null;
    }
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }
}
