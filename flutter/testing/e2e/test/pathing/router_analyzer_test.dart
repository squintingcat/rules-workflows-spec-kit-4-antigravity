import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../framework/pathing/src/router_analyzer.dart';

void main() {
  test('binds widget classes to concrete routes from router AST', () {
    final tempDir = Directory.systemTemp.createTempSync('router-analyzer-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File('${tempDir.path}/lib/config/router.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/groups',
                builder: (context, state) => const GroupListScreen(),
                routes: [
                  GoRoute(
                    path: 'create',
                    builder: (context, state) => const CreateGroupScreen(),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => CustomTransitionPage(
                      child: GroupDetailScreen(
                        groupId: state.pathParameters['id']!,
                      ),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
''');

    final bindings = RouteBindingAnalyzer(repoRoot: tempDir.path).analyze();

    expect(bindings['LoginScreen'], <String>['/login']);
    expect(bindings['GroupListScreen'], <String>['/groups']);
    expect(bindings['CreateGroupScreen'], <String>['/groups/create']);
    expect(bindings['GroupDetailScreen'], <String>['/groups/:id']);
  });

  test('binds widgets returned from nested conditional builders', () {
    final tempDir = Directory.systemTemp.createTempSync('router-analyzer-');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File('${tempDir.path}/lib/config/router.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/profile/add_equipment',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is String) {
            return AddEquipmentScreen(userId: extra);
          }
          return Scaffold(
            body: Text('invalid'),
          );
        },
      ),
    ],
  );
}
''');

    final bindings = RouteBindingAnalyzer(repoRoot: tempDir.path).analyze();

    expect(bindings['AddEquipmentScreen'], <String>['/profile/add_equipment']);
  });
}
