import 'models.dart';

class JourneyClassifier {
  List<JourneyClassification> classify(
    List<UserPath> userPaths, {
    Map<String, JourneyClassification> overrides = const {},
  }) {
    return userPaths.map((path) {
      if (overrides.containsKey(path.pathId)) {
        return overrides[path.pathId]!;
      }
      return _classifyPath(path);
    }).toList()..sort((a, b) => a.journeyId.compareTo(b.journeyId));
  }

  JourneyClassification _classifyPath(UserPath path) {
    final description = path.description.toLowerCase();
    final primarySource = path.primarySourceFile.toLowerCase();
    final indicatesProtectedRoute =
        path.outcomeClass.toLowerCase() == 'guard_blocked' ||
        description.contains('protected-route') ||
        description.contains('protected route') ||
        description.contains('redirect to login') ||
        description.contains('auth/permission');
    final needsSeed =
        path.sourceFiles.any((file) => file.contains('/detail_')) ||
        description.contains('detail') ||
        description.contains('edit') ||
        description.contains('join') ||
        description.contains('delete') ||
        description.contains('task') ||
        description.contains('facility') ||
        description.contains('horse') ||
        description.contains('create') ||
        description.contains('add') ||
        indicatesProtectedRoute ||
        primarySource.contains('edit_') ||
        primarySource.contains('create_') ||
        primarySource.contains('add_');
    final needsOutcomeProbe =
        description.contains('sensor') ||
        description.contains('tracking') ||
        description.contains('record ride') ||
        primarySource.contains('record_ride');

    final bucket =
        description.contains('sensor') ||
            description.contains('tracking') ||
            description.contains('record ride') ||
            primarySource.contains('record_ride')
        ? JourneyBucket.cDomainOracleRequired
        : (needsSeed || needsOutcomeProbe)
        ? JourneyBucket.bAdapterRequired
        : JourneyBucket.aGenericUi;

    return JourneyClassification(
      journeyId: path.pathId,
      bucket: bucket,
      expectedOutcome: _expectedOutcome(path),
      needsSeed: needsSeed,
      needsOutcomeProbe: needsOutcomeProbe,
    );
  }

  OutcomeFamily _expectedOutcome(UserPath path) {
    final value = '${path.variant} ${path.outcomeClass} ${path.description}'
        .toLowerCase();
    if (value.contains('delete')) return OutcomeFamily.entityDeleted;
    if (value.contains('update') || value.contains('edit')) {
      return OutcomeFamily.entityUpdated;
    }
    if (value.contains('validation') || value.contains('guard')) {
      return OutcomeFamily.validationBlocked;
    }
    if (value.contains('login') ||
        value.contains('logout') ||
        value.contains('auth')) {
      return OutcomeFamily.sessionChanged;
    }
    if (value.contains('record') || value.contains('tracking')) {
      return OutcomeFamily.dataRecorded;
    }
    if (value.contains('snack') || value.contains('feedback')) {
      return OutcomeFamily.feedbackShown;
    }
    if (value.contains('create') ||
        value.contains('add') ||
        value.contains('join')) {
      return OutcomeFamily.entityCreated;
    }
    return OutcomeFamily.navigationSucceeded;
  }
}
