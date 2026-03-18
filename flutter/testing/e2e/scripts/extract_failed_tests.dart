import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final options = _parseArgs(args);
  final inputFile = File(options.inputPath);
  final outputFile = File(options.outputPath);

  if (!inputFile.existsSync()) {
    stderr.writeln(
      '[e2e-failures] ERROR: input report not found: ${options.inputPath}',
    );
    exit(1);
  }

  final summary = _readSummary(inputFile);

  final sink = outputFile.openWrite();
  sink.writeln('# E2E Failure Summary');
  sink.writeln();
  sink.writeln('- Source report: `${options.inputPath}`');
  sink.writeln('- Report kind: `${summary.kind}`');
  if (summary.doneSuccess != null) {
    sink.writeln('- Runner success: `${summary.doneSuccess}`');
  }
  if (summary.totalTests != null) {
    sink.writeln('- Total tests: `${summary.totalTests}`');
  }
  if (summary.successfulTests != null) {
    sink.writeln('- Successful tests: `${summary.successfulTests}`');
  }
  if (summary.skippedTests != null) {
    sink.writeln('- Skipped tests: `${summary.skippedTests}`');
  }
  sink.writeln('- Failed tests: `${summary.failures.length}`');
  sink.writeln();

  if (summary.failures.isEmpty) {
    sink.writeln('No failing tests detected.');
  } else {
    sink.writeln('| Test | Result | Detail |');
    sink.writeln('|---|---|---|');
    for (final failure in summary.failures) {
      sink.writeln(
        '| `${_escapePipes(failure.name)}` | `${_escapePipes(failure.result)}` | `${_escapePipes(failure.detail ?? '-')}` |',
      );
    }
  }

  sink.close();
  stdout.writeln(
    '[e2e-failures] summary written: ${outputFile.path} (failed=${summary.failures.length})',
  );
}

_FailureSummary _readSummary(File inputFile) {
  final extension = inputFile.path.toLowerCase();
  if (extension.endsWith('.json')) {
    return _readFlutterJsonSummary(inputFile);
  }
  if (extension.endsWith('.xml')) {
    return _readJUnitXmlSummary(inputFile);
  }

  return _readPatrolLogSummary(inputFile);
}

_FailureSummary _readJUnitXmlSummary(File inputFile) {
  final xml = inputFile.readAsStringSync();
  final suiteMatch = RegExp(
    r'<testsuite\b([^>]*)>',
    caseSensitive: false,
  ).firstMatch(xml);
  final attributes = suiteMatch == null
      ? const <String, String>{}
      : _parseXmlAttributes(suiteMatch.group(1) ?? '');

  final totalTests = int.tryParse(attributes['tests'] ?? '');
  final failuresCount = int.tryParse(attributes['failures'] ?? '') ?? 0;
  final errorsCount = int.tryParse(attributes['errors'] ?? '') ?? 0;
  final skippedTests = int.tryParse(attributes['skipped'] ?? '') ?? 0;
  final failures = <_Failure>[];

  final testcasePattern = RegExp(
    r'<testcase\b([^>]*)>(.*?)</testcase>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in testcasePattern.allMatches(xml)) {
    final testcaseAttrs = _parseXmlAttributes(match.group(1) ?? '');
    final name = testcaseAttrs['name'] ?? 'unnamed testcase';
    final body = match.group(2) ?? '';

    final failureTag = RegExp(
      r'<(failure|error)\b[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(body);
    if (failureTag == null) {
      continue;
    }

    final rawDetail = _decodeXmlText(_stripXmlTags(failureTag.group(2) ?? ''));
    final detail = _collapseWhitespace(rawDetail);
    failures.add(
      _Failure(
        name: name,
        result: failureTag.group(1)?.toLowerCase() ?? 'failed',
        detail: detail.isEmpty ? null : detail,
      ),
    );
  }

  final failedTests = failuresCount + errorsCount;
  final successfulTests = totalTests == null
      ? null
      : totalTests - failedTests - skippedTests;

  return _FailureSummary(
    kind: 'junit-xml',
    doneSuccess: failedTests == 0,
    totalTests: totalTests,
    successfulTests: successfulTests,
    skippedTests: skippedTests,
    failures: failures,
  );
}

_FailureSummary _readFlutterJsonSummary(File inputFile) {
  final testsById = <int, _TestInfo>{};
  final failures = <_Failure>[];
  var doneSuccess = true;
  var totalTests = 0;
  var successfulTests = 0;
  var skippedTests = 0;

  for (final line in inputFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      continue;
    }

    final type = decoded['type'];
    if (type == 'testStart') {
      final test = decoded['test'];
      if (test is Map<String, dynamic>) {
        final id = test['id'];
        final name = test['name'];
        if (id is int && name is String) {
          testsById[id] = _TestInfo(
            id: id,
            name: name,
            detail: test['url']?.toString(),
          );
        }
      }
      continue;
    }

    if (type == 'testDone') {
      final result = decoded['result']?.toString();
      final skipped = decoded['skipped'] == true;
      final hidden = decoded['hidden'] == true;
      final testId = decoded['testID'];
      if (!hidden && result != null) {
        totalTests += 1;
        if (skipped) {
          skippedTests += 1;
        } else if (result == 'success') {
          successfulTests += 1;
        }
      }
      if (testId is int &&
          result != null &&
          !skipped &&
          !hidden &&
          result != 'success') {
        final info = testsById[testId];
        failures.add(
          _Failure(
            name: info?.name ?? 'unknown test id $testId',
            result: result,
            detail: info?.detail,
          ),
        );
      }
      continue;
    }

    if (type == 'done') {
      doneSuccess = decoded['success'] == true;
    }
  }

  return _FailureSummary(
    kind: 'flutter-json',
    doneSuccess: doneSuccess,
    totalTests: totalTests,
    successfulTests: successfulTests,
    skippedTests: skippedTests,
    failures: failures,
  );
}

_FailureSummary _readPatrolLogSummary(File inputFile) {
  final failures = <_Failure>[];
  final seenNames = <String>{};
  final successfulNames = <String>{};
  final trailingErrorLines = <String>[];
  var doneSuccess = false;
  int? totalTests;
  int? successfulTests;
  int? skippedTests;

  final progressFailure = RegExp(
    r'^\d{2}:\d{2}\s+\+\d+\s+-\d+:\s+(.+?)\s+\[E\]$',
  );
  final bulletFailure = RegExp(r'^[xX✗]\s+(.+)$');
  final passLine = RegExp(r'^✅\s+(.+?)\s+\(//.*\)$');
  final totalLine = RegExp(r'^📝\s+Total:\s+([0-9]+)$');
  final successLine = RegExp(r'^✅\s+Successful:\s+([0-9]+)$');
  final skippedLine = RegExp(r'^⏩\s+Skipped:\s+([0-9]+)$');

  for (final rawLine in inputFile.readAsLinesSync()) {
    final line = _stripAnsi(rawLine).trim();
    if (line.isEmpty) {
      continue;
    }

    final totalMatch = totalLine.firstMatch(line);
    if (totalMatch != null) {
      totalTests = int.tryParse(totalMatch.group(1)!);
      continue;
    }

    final successMatch = successLine.firstMatch(line);
    if (successMatch != null) {
      successfulTests = int.tryParse(successMatch.group(1)!);
      continue;
    }

    final skippedMatch = skippedLine.firstMatch(line);
    if (skippedMatch != null) {
      skippedTests = int.tryParse(skippedMatch.group(1)!);
      continue;
    }

    final passMatch = passLine.firstMatch(line);
    if (passMatch != null) {
      final name = passMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) {
        successfulNames.add(name);
      }
      continue;
    }

    final progressMatch = progressFailure.firstMatch(line);
    if (progressMatch != null) {
      final name = progressMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty && seenNames.add(name)) {
        failures.add(_Failure(name: name, result: 'failed'));
      }
      continue;
    }

    final bulletMatch = bulletFailure.firstMatch(line);
    if (bulletMatch != null) {
      final name = bulletMatch.group(1)?.trim();
      if (name != null &&
          name.isNotEmpty &&
          !name.startsWith('[e2e-') &&
          seenNames.add(name)) {
        failures.add(_Failure(name: name, result: 'failed'));
      }
      continue;
    }

    if (line.contains('All tests passed!') ||
        line.startsWith('✓ Completed executing apk')) {
      doneSuccess = true;
      continue;
    }

    if (line.startsWith('✗ Failed to execute tests') ||
        line.startsWith('Exception:')) {
      doneSuccess = false;
    }

    if (line.contains('Exception') ||
        line.contains('TestFailure') ||
        line.contains('Expected:') ||
        line.contains('Actual:')) {
      trailingErrorLines.add(line);
    }
  }

  if (failures.isEmpty && trailingErrorLines.isNotEmpty) {
    failures.add(
      _Failure(
        name: 'patrol-runner',
        result: 'failed',
        detail: trailingErrorLines.take(3).join(' | '),
      ),
    );
  }

  if (successfulNames.isNotEmpty) {
    successfulTests = successfulNames.length;
  }

  if (totalTests == null) {
    final skipped = skippedTests ?? 0;
    totalTests = successfulNames.length + failures.length + skipped;
  }

  if (doneSuccess && successfulTests == null) {
    final skipped = skippedTests ?? 0;
    successfulTests = totalTests - failures.length - skipped;
  }

  return _FailureSummary(
    kind: 'patrol-log',
    doneSuccess: doneSuccess,
    totalTests: totalTests,
    successfulTests: successfulTests,
    skippedTests: skippedTests,
    failures: failures,
  );
}

String _escapePipes(String value) => value.replaceAll('|', r'\|');

String _stripAnsi(String value) {
  return value.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '');
}

String _stripXmlTags(String value) {
  return value.replaceAll(RegExp(r'<[^>]+>'), ' ');
}

String _decodeXmlText(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

String _collapseWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Map<String, String> _parseXmlAttributes(String rawAttributes) {
  final attributes = <String, String>{};
  final pattern = RegExp(r'([A-Za-z_:][A-Za-z0-9_.:-]*)="([^"]*)"');
  for (final match in pattern.allMatches(rawAttributes)) {
    final key = match.group(1);
    final value = match.group(2);
    if (key == null || value == null) {
      continue;
    }
    attributes[key] = _decodeXmlText(value);
  }
  return attributes;
}

_CliOptions _parseArgs(List<String> args) {
  String? inputPath;
  String? outputPath;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--input' && i + 1 < args.length) {
      inputPath = args[++i];
      continue;
    }
    if (arg == '--output' && i + 1 < args.length) {
      outputPath = args[++i];
      continue;
    }
    if (arg == '-h' || arg == '--help') {
      _printUsage();
      exit(0);
    }
    stderr.writeln('[e2e-failures] ERROR: unknown argument: $arg');
    _printUsage();
    exit(2);
  }

  if (inputPath == null || inputPath.trim().isEmpty) {
    stderr.writeln('[e2e-failures] ERROR: --input is required.');
    _printUsage();
    exit(2);
  }

  if (outputPath == null || outputPath.trim().isEmpty) {
    stderr.writeln('[e2e-failures] ERROR: --output is required.');
    _printUsage();
    exit(2);
  }

  return _CliOptions(
    inputPath: inputPath.trim(),
    outputPath: outputPath.trim(),
  );
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run testing/e2e/scripts/extract_failed_tests.dart --input <report_or_log> --output <summary_md>',
  );
}

class _CliOptions {
  const _CliOptions({required this.inputPath, required this.outputPath});

  final String inputPath;
  final String outputPath;
}

class _TestInfo {
  const _TestInfo({required this.id, required this.name, required this.detail});

  final int id;
  final String name;
  final String? detail;
}

class _Failure {
  const _Failure({required this.name, required this.result, this.detail});

  final String name;
  final String result;
  final String? detail;
}

class _FailureSummary {
  const _FailureSummary({
    required this.kind,
    required this.doneSuccess,
    required this.totalTests,
    required this.successfulTests,
    required this.skippedTests,
    required this.failures,
  });

  final String kind;
  final bool? doneSuccess;
  final int? totalTests;
  final int? successfulTests;
  final int? skippedTests;
  final List<_Failure> failures;
}
