import 'dart:io';

import 'src/models.dart';
import 'src/pipeline.dart';

void main(List<String> args) {
  try {
    final options = _parseArgs(args);
    final repoRoot = Directory.current.path;

    final pipeline = E2EPathingPipeline(
      repoRoot: repoRoot,
      reportOutputDirectory: options.reportOutputDirectory,
    );

    final result = pipeline.run(mode: options.mode);
    final summary = result.model.summary;

    stdout.writeln('[e2e-pathing] mode=${summary.mode.value}');
    stdout.writeln('[e2e-pathing] analyzed_files=${summary.analyzedFileCount}');
    stdout.writeln('[e2e-pathing] paths=${summary.pathCount}');
    stdout.writeln(
      '[e2e-pathing] executable_paths=${summary.executablePathCount}',
    );
    stdout.writeln(
      '[e2e-pathing] executable_coverage=${summary.journeyCoveragePercent.toStringAsFixed(2)}%',
    );
    stdout.writeln(
      '[e2e-pathing] coverage_references=${summary.coverageReferenceCount}',
    );
    stdout.writeln(
      '[e2e-pathing] emitted_targets=${result.emittedTargets.length}',
    );

    for (final entry in result.reportFiles.entries) {
      stdout.writeln('[e2e-pathing] ${entry.key}: ${entry.value}');
    }

    if (summary.uncertainties.isNotEmpty) {
      stdout.writeln(
        '[e2e-pathing] uncertainties=${summary.uncertainties.length}',
      );
      for (final uncertainty in summary.uncertainties.take(5)) {
        stdout.writeln('[e2e-pathing] uncertainty: $uncertainty');
      }
    }
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exit(2);
  } catch (error, stackTrace) {
    stderr.writeln('[e2e-pathing] ERROR: $error');
    stderr.writeln(stackTrace);
    exit(1);
  }
}

class _CliOptions {
  _CliOptions({required this.mode, required this.reportOutputDirectory});

  final AnalysisMode mode;
  final String reportOutputDirectory;
}

_CliOptions _parseArgs(List<String> args) {
  var mode = AnalysisMode.scoped;
  var reportOutputDirectory = '.ciReport/e2e_pathing';

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    switch (arg) {
      case '--mode':
        if (i + 1 >= args.length) {
          throw _UsageException('Missing value for --mode');
        }
        mode = AnalysisModeX.parse(args[++i]);
        break;
      case '--out-dir':
        if (i + 1 >= args.length) {
          throw _UsageException('Missing value for --out-dir');
        }
        reportOutputDirectory = args[++i].trim();
        if (reportOutputDirectory.isEmpty) {
          throw _UsageException('--out-dir must not be empty');
        }
        break;
      case '-h':
      case '--help':
        _printUsage();
        exit(0);
      default:
        throw _UsageException('Unknown argument: $arg');
    }
  }

  return _CliOptions(mode: mode, reportOutputDirectory: reportOutputDirectory);
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run testing/e2e/framework/pathing/generate_e2e_from_code.dart [options]',
  );
  stdout.writeln();
  stdout.writeln('Options:');
  stdout.writeln(
    '  --mode <scoped|full>    Analysis scope mode (default: scoped)',
  );
  stdout.writeln(
    '  --out-dir <path>        Report output directory (default: .ciReport/e2e_pathing)',
  );
  stdout.writeln('  -h, --help              Show this help message');
}

class _UsageException implements Exception {
  _UsageException(this.message);

  final String message;
}
