import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patrol/patrol.dart';

import '../../testing/e2e/framework/adapter/applicationSpecificAdapter.dart';
import '../../testing/e2e/framework/explorer/src/blind_explorer.dart';
import '../../testing/e2e/framework/explorer/src/input_strategy.dart';

void main() {
  patrolTest('Blind Explorer - Full Exploration', ($) async {
    // final adapter = applicationSpecificAdapter(); // TODO: implement
    const gapHintsDefine = String.fromEnvironment(
      'E2E_EXPLORER_GAP_HINTS',
      defaultValue: '',
    );
    final gapHints = gapHintsDefine
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    const explorerMode = String.fromEnvironment(
      'E2E_EXPLORER_MODE',
      defaultValue: 'scoped',
    );
    final isFull = explorerMode.trim().toLowerCase() == 'full';

    final explorer = BlindExplorer(
      tester: $.tester,
      adapter: adapter,
      inputStrategy: const InputStrategy(),
      maxDepth: isFull ? 2 : 2,
      maxActionsPerScreen: isFull ? 4 : 6,
      maxTotalActions: isFull ? 80 : 12,
      gapHints: gapHints,
    );

    final result = await explorer.explore();
    final docs = await getApplicationDocumentsDirectory();
    final reportFile = File('${docs.path}/exploration_result.json');
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result.toJson()),
    );
    final payload = base64Encode(utf8.encode(jsonEncode(result.toJson())));
    // The file is the source of truth. The payload stays in the log as a
    // fallback for environments where `run-as` extraction is unavailable.
    // ignore: avoid_print
    print('E2E_EXPLORATION_RESULT_START');
    const chunkSize = 800;
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = (offset + chunkSize < payload.length)
          ? offset + chunkSize
          : payload.length;
      // ignore: avoid_print
      print(payload.substring(offset, end));
    }
    // ignore: avoid_print
    print('E2E_EXPLORATION_RESULT_END');

    expect(result.visitedRoutes.length, greaterThanOrEqualTo(1));
  });
}
