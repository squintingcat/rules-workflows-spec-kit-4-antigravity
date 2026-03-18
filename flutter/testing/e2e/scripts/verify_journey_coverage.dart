import 'dart:convert';
import 'dart:io';

int main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      '[e2e-journey-gate] ERROR: expected exactly one argument: <analysis_model.json>.',
    );
    return 2;
  }

  final modelPath = args.single;
  final modelFile = File(modelPath);
  if (!modelFile.existsSync()) {
    stderr.writeln(
      '[e2e-journey-gate] ERROR: analysis model not found: $modelPath',
    );
    return 1;
  }

  final data = jsonDecode(modelFile.readAsStringSync()) as Map<String, dynamic>;
  final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
  final userPaths =
      ((data['user_paths'] as List?) ?? const <dynamic>[])
          .cast<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
  final pathToCoverageReferences =
      (data['path_to_coverage_references'] as Map?)?.cast<String, dynamic>() ??
      const {};
  final blocked =
      (data['blocked_path_reasons'] as Map?)?.cast<String, dynamic>() ?? const {};
  final coverageReferences =
      ((data['coverage_references'] as List?) ?? const <dynamic>[]).length;

  final executablePaths =
      userPaths
          .where((path) => !blocked.containsKey(path['path_id'] as String? ?? ''))
          .toList();
  final coveredPaths =
      executablePaths
          .where(
            (path) =>
                pathToCoverageReferences[path['path_id'] as String? ?? ''] !=
                null,
          )
          .toList();
  final uncoveredPaths =
      executablePaths
          .where(
            (path) =>
                pathToCoverageReferences[path['path_id'] as String? ?? ''] ==
                null,
          )
          .toList();

  final expectedExecutable =
      (summary['executable_path_count'] as num?)?.toInt() ??
      executablePaths.length;
  final expectedCovered =
      (summary['covered_executable_path_count'] as num?)?.toInt() ??
      coveredPaths.length;
  final expectedUncovered =
      (summary['uncovered_executable_path_count'] as num?)?.toInt() ??
      uncoveredPaths.length;

  stdout.writeln(
    '[e2e-journey-gate] executable_paths=${executablePaths.length}',
  );
  stdout.writeln(
    '[e2e-journey-gate] covered_executable_paths=${coveredPaths.length}',
  );
  stdout.writeln(
    '[e2e-journey-gate] uncovered_executable_paths=${uncoveredPaths.length}',
  );
  stdout.writeln(
    '[e2e-journey-gate] coverage_references=$coverageReferences',
  );

  final summaryMismatch =
      expectedExecutable != executablePaths.length ||
      expectedCovered != coveredPaths.length ||
      expectedUncovered != uncoveredPaths.length;
  if (summaryMismatch) {
    stderr.writeln(
      '[e2e-journey-gate] ERROR: summary coverage counts do not match model content.',
    );
    return 1;
  }

  if (uncoveredPaths.isNotEmpty) {
    stderr.writeln(
      '[e2e-journey-gate] ERROR: executable journeys without coverage reference:',
    );
    for (final path in uncoveredPaths.take(20)) {
      stderr.writeln(
        '  - ${path['path_id']} (${path['primary_source_file']})',
      );
    }
    if (uncoveredPaths.length > 20) {
      stderr.writeln('  - ... ${uncoveredPaths.length - 20} more');
    }
    return 1;
  }

  stdout.writeln('[e2e-journey-gate] OK');
  return 0;
}
