import 'dart:collection';

import 'models.dart';
import 'path_utils.dart';

class CoverageReferenceResult {
  CoverageReferenceResult({
    required this.coverageReferences,
    required this.pathToCoverageReferences,
    required this.coverageReferenceToPaths,
    required this.parityMapping,
  });

  final List<CoverageReference> coverageReferences;
  final Map<String, List<String>> pathToCoverageReferences;
  final Map<String, List<String>> coverageReferenceToPaths;
  final Map<String, String> parityMapping;
}

class CoverageReferenceBuilder {
  CoverageReferenceResult build({
    required List<UserPath> userPaths,
    required Map<String, List<String>> blockedPathReasons,
  }) {
    final coverageReferences = <CoverageReference>[];
    final pathToCoverageReferences = <String, List<String>>{};
    final coverageReferenceToPaths = <String, List<String>>{};
    final parityMapping = <String, String>{};

    for (final path in userPaths) {
      final blockedReasons =
          blockedPathReasons[path.pathId] ?? const <String>[];
      if (blockedReasons.isNotEmpty) {
        pathToCoverageReferences[path.pathId] = const <String>[];
        continue;
      }

      final coverageReferenceId = coverageReferenceIdForPath(path.pathId);
      coverageReferences.add(
        CoverageReference(
          referenceId: 'coverage_${sanitizeForId(path.pathId)}',
          referenceTarget: coverageReferenceId,
          variant: path.variant,
          title: 'Coverage reference for ${path.pathId}',
          pathIds: <String>[path.pathId],
          sourceFiles: path.sourceFiles,
          parityKey: path.parityKey,
          parameters: <Map<String, String>>[
            <String, String>{
              'journey_id': path.pathId,
              'coverage_reference_kind': 'coverage_reference',
              'expected_outcome': path.outcomeClass,
            },
          ],
        ),
      );
      pathToCoverageReferences[path.pathId] = <String>[coverageReferenceId];
      coverageReferenceToPaths[coverageReferenceId] = <String>[path.pathId];
      parityMapping.putIfAbsent(
        path.primarySourceFile,
        () => coverageReferenceId,
      );
    }

    return CoverageReferenceResult(
      coverageReferences: coverageReferences,
      pathToCoverageReferences: _normalizeMap(pathToCoverageReferences),
      coverageReferenceToPaths: _normalizeMap(coverageReferenceToPaths),
      parityMapping: SplayTreeMap<String, String>.from(parityMapping),
    );
  }

  Map<String, List<String>> _normalizeMap(Map<String, List<String>> raw) {
    final normalized = SplayTreeMap<String, List<String>>();
    final keys = raw.keys.toList()..sort();
    for (final key in keys) {
      normalized[key] = List<String>.from(raw[key] ?? const <String>[]);
    }
    return normalized;
  }
}
