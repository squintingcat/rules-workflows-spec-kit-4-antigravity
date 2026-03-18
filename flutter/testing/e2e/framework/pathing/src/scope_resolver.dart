import 'dart:io';

import 'models.dart';
import 'path_utils.dart';

class ScopeResolver {
  ScopeResolver({required this.repoRoot});

  final String repoRoot;

  ScopeSelection resolve(AnalysisMode mode) {
    return switch (mode) {
      AnalysisMode.full => _resolveFull(),
      AnalysisMode.scoped => _resolveScoped(),
    };
  }

  ScopeSelection _resolveFull() {
    final productionFiles = <String>{};
    final documentationFiles = <String>{};

    for (final root in kRelevantRoots) {
      final directory = Directory('$repoRoot/$root');
      if (!directory.existsSync()) {
        continue;
      }
      final files = directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map(
            (file) =>
                relativePathFromRoot(rootPath: repoRoot, targetPath: file.path),
          );
      for (final relative in files) {
        if (isRelevantProductionDartFile(relative)) {
          productionFiles.add(toPosixPath(relative));
        }
      }
    }

    for (final root in kDocumentationRoots) {
      final absolute = FileSystemEntity.typeSync('$repoRoot/$root');
      if (absolute == FileSystemEntityType.notFound) {
        continue;
      }
      if (absolute == FileSystemEntityType.file) {
        if (isDocumentationSignalFile(root)) {
          documentationFiles.add(root);
        }
        continue;
      }

      final directory = Directory('$repoRoot/$root');
      final files = directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map(
            (file) =>
                relativePathFromRoot(rootPath: repoRoot, targetPath: file.path),
          );
      for (final relative in files) {
        if (isDocumentationSignalFile(relative)) {
          documentationFiles.add(toPosixPath(relative));
        }
      }
    }

    return ScopeSelection(
      mode: AnalysisMode.full,
      productionFiles: productionFiles.toList(),
      documentationFiles: documentationFiles.toList(),
      deletedProductionFiles: const <String>[],
      rawChangedFiles: const <String>[],
    );
  }

  ScopeSelection _resolveScoped() {
    final changed = <String>{
      ..._readGitLines('diff --name-only --diff-filter=ACMR'),
      ..._readGitLines('diff --cached --name-only --diff-filter=ACMR'),
      ..._readGitLines('ls-files --others --exclude-standard'),
    };

    final deleted = <String>{
      ..._readGitLines('diff --name-only --diff-filter=D'),
      ..._readGitLines('diff --cached --name-only --diff-filter=D'),
    };

    final productionFiles = <String>{};
    final documentationFiles = <String>{};
    final deletedProductionFiles = <String>{};

    for (final file in changed) {
      final normalized = toPosixPath(file.trim());
      if (normalized.isEmpty) {
        continue;
      }
      if (isRelevantProductionDartFile(normalized)) {
        productionFiles.add(normalized);
      }
      if (isDocumentationSignalFile(normalized)) {
        documentationFiles.add(normalized);
      }
    }

    for (final file in deleted) {
      final normalized = toPosixPath(file.trim());
      if (normalized.isEmpty) {
        continue;
      }
      if (isRelevantProductionDartFile(normalized)) {
        deletedProductionFiles.add(normalized);
      }
    }

    return ScopeSelection(
      mode: AnalysisMode.scoped,
      productionFiles: productionFiles.toList(),
      documentationFiles: documentationFiles.toList(),
      deletedProductionFiles: deletedProductionFiles.toList(),
      rawChangedFiles: changed.toList(),
    );
  }

  Set<String> _readGitLines(String args) {
    final split = args.split(' ');
    final result = Process.runSync(
      'git',
      split,
      workingDirectory: repoRoot,
      runInShell: false,
    );

    if (result.exitCode != 0) {
      return <String>{};
    }

    final output = (result.stdout as String?) ?? '';
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
    return lines;
  }
}
