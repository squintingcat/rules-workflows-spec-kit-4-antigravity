import 'dart:convert';
import 'dart:io';

import '../pathing/src/journey_diff_builder.dart';
import '../pathing/src/models.dart';
import 'src/coverage_feedback.dart';
import 'src/explorer_report_writer.dart';

const _startMarker = 'E2E_EXPLORATION_RESULT_START';
const _endMarker = 'E2E_EXPLORATION_RESULT_END';

void main(List<String> args) {
  try {
    final options = _parseArgs(args);
    final explorationResult = options.explorationJsonPath != null
        ? ExplorationResult.fromJson(
            _readJsonObject(options.explorationJsonPath!),
          )
        : extractExplorationResultFromLog(
            File(options.logPath!).readAsStringSync(),
          );
    final groundTruth = GroundTruthModel.fromJson(
      _readJsonObject(options.groundTruthPath),
    );
    final journeyClassifications = _readJsonList(
      options.classificationPath,
    ).map(JourneyClassification.fromJson).toList();
    final analysisSupport = _readAnalysisSupport(options.analysisModelPath);

    final coverageGap = const CoverageFeedback().compute(
      groundTruth: groundTruth,
      explorationResult: explorationResult,
    );
    final journeyDiff = JourneyDiffBuilder().build(
      classifications: journeyClassifications,
      pathToCoverageReferences: analysisSupport.pathToCoverageReferences,
      journeyRouteHints: analysisSupport.journeyRouteHints,
      explorationResult: explorationResult,
    );

    final reportFiles =
        ExplorerReportWriter(
          repoRoot: Directory.current.path,
          outputDirectory: options.outputDirectory,
        ).write(
          groundTruth: groundTruth,
          explorationResult: explorationResult,
          coverageGap: coverageGap,
          journeyDiffReport: journeyDiff,
          journeyClassifications: journeyClassifications,
          mode: options.mode,
        );

    stdout.writeln(
      '[e2e-explorer] visited_routes=${explorationResult.visitedRoutes.length}',
    );
    stdout.writeln(
      '[e2e-explorer] interactions=${explorationResult.interactions.length}',
    );
    stdout.writeln(
      '[e2e-explorer] behavior_violations=${explorationResult.behaviorViolationCount}',
    );
    stdout.writeln(
      '[e2e-explorer] route_coverage=${(coverageGap.routeCoverage * 100).toStringAsFixed(2)}%',
    );
    for (final entry in reportFiles.entries) {
      stdout.writeln('[e2e-explorer] ${entry.key}: ${entry.value}');
    }
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exit(2);
  } catch (error, stackTrace) {
    stderr.writeln('[e2e-explorer] ERROR: $error');
    stderr.writeln(stackTrace);
    exit(1);
  }
}

class _CliOptions {
  const _CliOptions({
    this.logPath,
    this.explorationJsonPath,
    required this.groundTruthPath,
    required this.classificationPath,
    required this.analysisModelPath,
    required this.outputDirectory,
    required this.mode,
  });

  final String? logPath;
  final String? explorationJsonPath;
  final String groundTruthPath;
  final String classificationPath;
  final String analysisModelPath;
  final String outputDirectory;
  final AnalysisMode mode;
}

_CliOptions _parseArgs(List<String> args) {
  String? logPath;
  String? explorationJsonPath;
  String? groundTruthPath;
  String? classificationPath;
  String? analysisModelPath;
  var outputDirectory = '.ciReport/e2e_pathing';
  var mode = AnalysisMode.full;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--log':
        logPath = _readNext(args, ++index, '--log');
        break;
      case '--exploration-json':
        explorationJsonPath = _readNext(args, ++index, '--exploration-json');
        break;
      case '--ground-truth':
        groundTruthPath = _readNext(args, ++index, '--ground-truth');
        break;
      case '--journey-classification':
        classificationPath = _readNext(
          args,
          ++index,
          '--journey-classification',
        );
        break;
      case '--analysis-model':
        analysisModelPath = _readNext(args, ++index, '--analysis-model');
        break;
      case '--out-dir':
        outputDirectory = _readNext(args, ++index, '--out-dir');
        break;
      case '--mode':
        mode = AnalysisModeX.parse(_readNext(args, ++index, '--mode'));
        break;
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        throw _UsageException('Unknown argument: $arg');
    }
  }

  if ((logPath == null && explorationJsonPath == null) ||
      groundTruthPath == null ||
      classificationPath == null ||
      analysisModelPath == null) {
    throw _UsageException(
      'Missing required arguments: (--log or --exploration-json), --ground-truth, --journey-classification, --analysis-model',
    );
  }

  return _CliOptions(
    logPath: logPath,
    explorationJsonPath: explorationJsonPath,
    groundTruthPath: groundTruthPath,
    classificationPath: classificationPath,
    analysisModelPath: analysisModelPath,
    outputDirectory: outputDirectory,
    mode: mode,
  );
}

String _readNext(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw _UsageException('Missing value for $flag');
  }
  return args[index];
}

Map<String, Object?> _readJsonObject(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! Map) {
    throw StateError('Expected JSON object in $path');
  }
  return decoded.cast<String, Object?>();
}

List<Map<String, Object?>> _readJsonList(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! List) {
    throw StateError('Expected JSON list in $path');
  }
  return decoded
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList();
}

ExplorationResult extractExplorationResultFromLog(String logContent) {
  final start = logContent.indexOf(_startMarker);
  if (start < 0) {
    throw StateError('Explorer log marker $_startMarker not found.');
  }
  final startIndex = start + _startMarker.length;
  final end = logContent.indexOf(_endMarker, startIndex);
  if (end < 0) {
    throw StateError('Explorer log marker $_endMarker not found.');
  }

  final payload = logContent
      .substring(startIndex, end)
      .split('\n')
      .map(_extractPayloadChunk)
      .where((line) => line.isNotEmpty)
      .join();
  final decoded = utf8.decode(base64Decode(_normalizeBase64Payload(payload)));
  final json = jsonDecode(decoded);
  if (json is! Map) {
    throw StateError('Explorer payload did not decode into a JSON object.');
  }
  return ExplorationResult.fromJson(json.cast<String, Object?>());
}

String _extractPayloadChunk(String line) {
  final flutterPrefix = 'I flutter : ';
  final prefixIndex = line.indexOf(flutterPrefix);
  if (prefixIndex >= 0) {
    return line.substring(prefixIndex + flutterPrefix.length).trim();
  }

  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(trimmed)) {
    return trimmed;
  }
  return '';
}

String _normalizeBase64Payload(String payload) {
  final sanitized = payload.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
  final withoutPadding = sanitized.replaceAll('=', '');
  final remainder = withoutPadding.length % 4;
  if (remainder == 0) {
    return withoutPadding;
  }
  return withoutPadding.padRight(withoutPadding.length + (4 - remainder), '=');
}

class _AnalysisSupport {
  const _AnalysisSupport({
    required this.pathToCoverageReferences,
    required this.journeyRouteHints,
  });

  final Map<String, List<String>> pathToCoverageReferences;
  final Map<String, List<String>> journeyRouteHints;
}

_AnalysisSupport _readAnalysisSupport(String path) {
  final root = _readJsonObject(path);
  final raw = root['path_to_coverage_references'];
  final normalized = <String, List<String>>{};
  if (raw is Map) {
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (entry.value is List) {
        normalized[key] = (entry.value as List)
            .map((item) => item.toString())
            .toList();
      }
    }
  }

  final routeBindings = <String, List<String>>{};
  final rawBindings = root['route_bindings'];
  if (rawBindings is Map) {
    for (final entry in rawBindings.entries) {
      if (entry.value is List) {
        routeBindings[entry.key.toString()] = (entry.value as List)
            .map((item) => item.toString())
            .toList();
      }
    }
  }

  final fileRoutes = <String, Set<String>>{};
  final rawFileSignals = root['file_signals'];
  if (rawFileSignals is List) {
    for (final item in rawFileSignals.whereType<Map>()) {
      final filePath = item['file_path']?.toString();
      if (filePath == null || filePath.isEmpty) {
        continue;
      }
      final routes = <String>{};
      final directRoutes = item['routes'];
      if (directRoutes is List) {
        routes.addAll(
          directRoutes
              .map((route) => route.toString())
              .where((route) => route.startsWith('/')),
        );
      }
      final screens = item['screens'];
      if (screens is List) {
        for (final screen in screens) {
          routes.addAll(routeBindings[screen.toString()] ?? const <String>[]);
        }
      }
      if (routes.isNotEmpty) {
        fileRoutes[filePath] = routes;
      }
    }
  }

  final journeyRouteHints = <String, List<String>>{};
  final rawPaths = root['user_paths'];
  if (rawPaths is List) {
    for (final item in rawPaths.whereType<Map>()) {
      final journeyId = item['path_id']?.toString();
      if (journeyId == null || journeyId.isEmpty) {
        continue;
      }
      final routes = <String>{};
      final sourceFiles = item['source_files'];
      if (sourceFiles is List) {
        for (final sourceFile in sourceFiles) {
          routes.addAll(fileRoutes[sourceFile.toString()] ?? const <String>{});
        }
      }
      final primarySource = item['primary_source_file']?.toString();
      if (primarySource != null) {
        routes.addAll(fileRoutes[primarySource] ?? const <String>{});
      }
      final steps = item['steps'];
      if (steps is List) {
        for (final step in steps.whereType<Map>()) {
          final description = step['description']?.toString() ?? '';
          routes.addAll(_extractRouteHints(description));
        }
      }
      final description = item['description']?.toString() ?? '';
      routes.addAll(_extractRouteHints(description));
      if (routes.isNotEmpty) {
        journeyRouteHints[journeyId] = routes.toList()..sort();
      }
    }
  }

  return _AnalysisSupport(
    pathToCoverageReferences: normalized,
    journeyRouteHints: journeyRouteHints,
  );
}

Set<String> _extractRouteHints(String value) {
  final matches = RegExp(
    r'\/[A-Za-z0-9_:\-]+(?:\/[A-Za-z0-9_:\-]+)*',
  ).allMatches(value);
  return matches
      .map((match) => match.group(0) ?? '')
      .where((candidate) => candidate.startsWith('/'))
      .map(normalizeRoutePath)
      .where((candidate) => candidate.isNotEmpty)
      .toSet();
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run testing/e2e/framework/explorer/materialize_exploration_reports.dart '
    '(--log <path> | --exploration-json <path>) --ground-truth <path> --journey-classification <path> --analysis-model <path> [options]',
  );
  stdout.writeln();
  stdout.writeln('Options:');
  stdout.writeln('  --mode <scoped|full>                 Analysis mode');
  stdout.writeln('  --out-dir <path>                     Output directory');
  stdout.writeln(
    '  --log <path>                         Patrol explorer log file',
  );
  stdout.writeln(
    '  --exploration-json <path>            Extracted explorer JSON result file',
  );
  stdout.writeln(
    '  --ground-truth <path>                Ground-truth JSON from generate step',
  );
  stdout.writeln(
    '  --journey-classification <path>      Journey classification JSON from generate step',
  );
  stdout.writeln(
    '  --analysis-model <path>              Analysis model JSON for old path->test coverage',
  );
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}
