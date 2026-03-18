import 'dart:io';

import 'models.dart';
import 'path_utils.dart';

class DocumentationAnalyzer {
  DocumentationAnalyzer({required this.repoRoot});

  final String repoRoot;

  DocumentationSignals analyze({
    required List<String> documentationFiles,
    required Set<String> knownModuleKeys,
  }) {
    final moduleHints = <String, List<String>>{};
    final moduleRoutes = <String, List<String>>{};
    final globalHints = <String>{};
    final files = <String>{};

    for (final relativePath in documentationFiles) {
      final normalized = toPosixPath(relativePath);
      final file = File('$repoRoot/$normalized');
      if (!file.existsSync()) {
        continue;
      }

      files.add(normalized);
      final content = file.readAsStringSync();
      final lines = content.split('\n');

      final inferredModules = _inferModulesFromPathAndContent(
        filePath: normalized,
        content: content,
        knownModuleKeys: knownModuleKeys,
      );

      final routeMatches = _extractRouteLikeTokens(content);
      for (final route in routeMatches) {
        if (inferredModules.isEmpty) {
          globalHints.add('route:$route');
        } else {
          for (final module in inferredModules) {
            moduleRoutes.putIfAbsent(module, () => <String>[]).add(route);
          }
        }
      }

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) {
          continue;
        }

        final normalizedLine = trimmed.toLowerCase();
        final hasInterestingKeyword = _documentationKeywords.any(
          (keyword) => normalizedLine.contains(keyword),
        );

        if (!hasInterestingKeyword) {
          continue;
        }

        if (inferredModules.isEmpty) {
          globalHints.add(trimmed);
        } else {
          for (final module in inferredModules) {
            moduleHints.putIfAbsent(module, () => <String>[]).add(trimmed);
          }
        }
      }
    }

    return DocumentationSignals(
      moduleHints: moduleHints,
      moduleRoutes: moduleRoutes,
      globalHints: globalHints.toList(),
      documentationFiles: files.toList(),
    );
  }

  Set<String> _inferModulesFromPathAndContent({
    required String filePath,
    required String content,
    required Set<String> knownModuleKeys,
  }) {
    final modules = <String>{};
    final lowerPath = filePath.toLowerCase();
    final lowerContent = content.toLowerCase();

    for (final module in knownModuleKeys) {
      final moduleToken = module.toLowerCase().replaceAll('/', ' ');
      final tailToken = module.toLowerCase().split('/').last;
      if (lowerPath.contains(tailToken) ||
          lowerContent.contains(' $tailToken ') ||
          lowerContent.contains('$tailToken/') ||
          lowerContent.contains(moduleToken)) {
        modules.add(module);
      }
    }

    return modules;
  }

  Set<String> _extractRouteLikeTokens(String content) {
    final routes = <String>{};

    for (final match in RegExp(r"'(/[^'\\s]*)'").allMatches(content)) {
      final value = (match.group(1) ?? '').trim();
      if (value.startsWith('/')) {
        routes.add(value);
      }
    }

    for (final match in RegExp(r'"(/[^"\\s]*)"').allMatches(content)) {
      final value = (match.group(1) ?? '').trim();
      if (value.startsWith('/')) {
        routes.add(value);
      }
    }

    return routes;
  }
}

const Set<String> _documentationKeywords = <String>{
  'login',
  'register',
  'auth',
  'navigate',
  'route',
  'validation',
  'guard',
  'error',
  'retry',
  'create',
  'update',
  'delete',
  'read',
  'supabase',
  'profile',
  'settings',
  'submit',
  'form',
};
