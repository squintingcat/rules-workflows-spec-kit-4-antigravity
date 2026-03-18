import 'dart:io';

const List<String> kRelevantRoots = <String>[
  'lib/features',
  'lib/shared',
  'lib/core',
  'lib/config',
];

const List<String> kDocumentationRoots = <String>[
  'README.md',
  'docs',
  '.agent/rules',
];

bool isRelevantProductionDartFile(String relativePath) {
  if (!relativePath.endsWith('.dart')) {
    return false;
  }
  if (isGeneratedDartFile(relativePath)) {
    return false;
  }
  return kRelevantRoots.any(
    (root) => relativePath == root || relativePath.startsWith('$root/'),
  );
}

bool isGeneratedDartFile(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.endsWith('.mocks.dart') ||
      path.endsWith('.gen.dart');
}

bool isDocumentationSignalFile(String relativePath) {
  if (relativePath == 'README.md') {
    return true;
  }
  if (relativePath.endsWith('.md') && relativePath.startsWith('docs/')) {
    return true;
  }
  if (relativePath.endsWith('.md') &&
      relativePath.startsWith('.agent/rules/')) {
    return true;
  }
  return false;
}

String moduleKeyFromPath(String relativePath) {
  if (relativePath.startsWith('lib/features/')) {
    final parts = relativePath.split('/');
    if (parts.length >= 3) {
      return 'features/${parts[2]}';
    }
  }
  if (relativePath.startsWith('lib/shared/')) {
    final parts = relativePath.split('/');
    if (parts.length >= 3) {
      return 'shared/${parts[2]}';
    }
    return 'shared';
  }
  if (relativePath.startsWith('lib/core/')) {
    final parts = relativePath.split('/');
    if (parts.length >= 3) {
      return 'core/${parts[2]}';
    }
    return 'core';
  }
  if (relativePath.startsWith('lib/config/')) {
    return 'config';
  }
  return 'unknown';
}

String featureKeyFromPath(String relativePath) {
  if (relativePath.startsWith('lib/features/')) {
    final parts = relativePath.split('/');
    if (parts.length >= 3) {
      return parts[2];
    }
  }
  if (relativePath.startsWith('lib/shared/')) {
    return 'shared';
  }
  if (relativePath.startsWith('lib/core/')) {
    return 'core';
  }
  if (relativePath.startsWith('lib/config/')) {
    return 'config';
  }
  return 'unknown';
}

String parityKeyFromSourceFile(String relativePath) {
  return relativePath;
}

String coverageReferenceIdForPath(String pathId) {
  return 'coverage-ref://${sanitizeForId(pathId)}';
}

String sanitizeForId(String raw) {
  final buffer = StringBuffer();
  for (final codePoint in raw.runes) {
    final char = String.fromCharCode(codePoint);
    final isAlphaNum = RegExp(r'[A-Za-z0-9]').hasMatch(char);
    if (isAlphaNum) {
      buffer.write(char.toLowerCase());
    } else {
      buffer.write('_');
    }
  }
  final collapsed = buffer.toString().replaceAll(RegExp(r'_+'), '_');
  return collapsed.replaceAll(RegExp(r'^_|_$'), '');
}

String relativePathFromRoot({
  required String rootPath,
  required String targetPath,
}) {
  final normalizedRoot = File(rootPath).absolute.path.replaceAll('\\', '/');
  final normalizedTarget = File(targetPath).absolute.path.replaceAll('\\', '/');
  final normalizedRootLower = normalizedRoot.toLowerCase();
  final normalizedTargetLower = normalizedTarget.toLowerCase();

  if (!normalizedTargetLower.startsWith(normalizedRootLower)) {
    return normalizedTarget;
  }

  final suffix = normalizedTarget.substring(normalizedRoot.length);
  final trimmed = suffix.startsWith('/') ? suffix.substring(1) : suffix;
  return trimmed;
}

String toPosixPath(String path) => path.replaceAll('\\', '/');

bool isUiLikelyFilePath(String relativePath) {
  return relativePath.contains('/presentation/') ||
      relativePath.contains('/widgets/') ||
      relativePath.endsWith('_screen.dart') ||
      relativePath.endsWith('_view.dart') ||
      relativePath.endsWith('_dialog.dart') ||
      relativePath.endsWith('_wizard.dart');
}

bool isFeaturePresentationFilePath(String relativePath) {
  return relativePath.startsWith('lib/features/') &&
      relativePath.contains('/presentation/');
}

bool isCorePresentationFilePath(String relativePath) {
  return relativePath.startsWith('lib/core/') &&
      relativePath.contains('/presentation/');
}

bool isJourneyPresentationFilePath(String relativePath) {
  return isFeaturePresentationFilePath(relativePath) ||
      isCorePresentationFilePath(relativePath);
}

bool isJourneyEntryFilePath(String relativePath) {
  if (!isJourneyPresentationFilePath(relativePath)) {
    return false;
  }

  return relativePath.endsWith('_screen.dart') ||
      relativePath.endsWith('_view.dart') ||
      relativePath.endsWith('_wizard.dart') ||
      relativePath.endsWith('_dialog.dart');
}

String relativeImportPath({required String fromFile, required String toFile}) {
  final fromParts = toPosixPath(fromFile).split('/');
  final toParts = toPosixPath(toFile).split('/');

  if (fromParts.isEmpty || toParts.isEmpty) {
    return toFile;
  }

  final fromDirs = fromParts.sublist(0, fromParts.length - 1);
  final toDirs = toParts.sublist(0, toParts.length - 1);

  var commonLength = 0;
  while (commonLength < fromDirs.length &&
      commonLength < toDirs.length &&
      fromDirs[commonLength] == toDirs[commonLength]) {
    commonLength += 1;
  }

  final upMoves = List<String>.filled(fromDirs.length - commonLength, '..');
  final downMoves = toParts.sublist(commonLength);
  final segments = <String>[...upMoves, ...downMoves];
  return segments.join('/');
}
