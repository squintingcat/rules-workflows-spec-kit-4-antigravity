import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:patrol/patrol.dart';
import 'dart:convert';

import '../../framework/explorer/materialize_exploration_reports.dart';
import '../../framework/explorer/src/coverage_feedback.dart';
import '../../framework/explorer/src/blind_explorer.dart';
import '../../framework/explorer/src/input_strategy.dart';
import '../../framework/explorer/src/project_adapter.dart';

import '../../framework/pathing/src/ground_truth_builder.dart';
import '../../framework/pathing/src/journey_classifier.dart';
import '../../framework/pathing/src/journey_diff_builder.dart';
import '../../framework/pathing/src/coverage_reference_builder.dart';
import '../../framework/pathing/src/models.dart';

void main() {
  test('ground truth includes route metadata and interactions', () {
    final builder = GroundTruthBuilder();
    final model = builder.build(
      fileSignals: <FileSignals>[
        FileSignals(
          filePath: 'lib/features/group/presentation/create_group_screen.dart',
          moduleKey: 'features/group',
          featureKey: 'group',
          isUiFile: true,
          screens: {'CreateGroupScreen'},
          widgets: {'CreateGroupScreen'},
          routes: {'/groups/create'},
          navigationTransitions: {'/groups'},
          uiActions: {'submit'},
          forms: {'group_form'},
          validations: {'required'},
          guards: {'authGuard'},
          errorPaths: {'validation'},
          repositoryCalls: {'groupRepository.create'},
          serviceCalls: {},
          stateChanges: {'groupCreated'},
          supabaseInteractions: {'insert:groups'},
          crudOperations: {'create'},
          authOperations: {},
          commentHints: {},
          references: const <SourceReference>[],
        ),
      ],
      routeBindings: <String, List<String>>{
        'CreateGroupScreen': <String>['/groups/create'],
      },
    );

    expect(model.totalRoutes, 1);
    expect(model.entryScreens, contains('/groups/create'));
    expect(model.routes.first.hasForm, isTrue);
    expect(model.routes.first.guards, contains('authGuard'));
  });

  test('journey classifier maps paths into buckets', () {
    final classifier = JourneyClassifier();
    final classifications = classifier.classify(<UserPath>[
      UserPath(
        pathId: 'create_group',
        moduleKey: 'features/group',
        featureKey: 'group',
        variant: 'positive',
        confidence: 'high',
        outcomeClass: 'entity_created_visible',
        description: 'Create group',
        sourceFiles: <String>[
          'lib/features/group/presentation/create_group_screen.dart',
        ],
        steps: const <PathStep>[],
        guards: const <String>['authGuard'],
        validations: const <String>['required'],
        errors: const <String>[],
        supabaseInteractions: const <String>['insert:groups'],
        heuristicNotes: const <String>[],
        parityKey: 'lib/features/group/presentation/create_group_screen.dart',
        primarySourceFile:
            'lib/features/group/presentation/create_group_screen.dart',
      ),
      UserPath(
        pathId: 'ride_recording_validation',
        moduleKey: 'features/ride',
        featureKey: 'ride',
        variant: 'positive',
        confidence: 'high',
        outcomeClass: 'data_recorded',
        description: 'Sensor tracking record flow',
        sourceFiles: <String>[
          'lib/features/ride/presentation/ride_recording_screen.dart',
        ],
        steps: const <PathStep>[],
        guards: const <String>['authGuard'],
        validations: const <String>[],
        errors: const <String>[],
        supabaseInteractions: const <String>['insert:rides'],
        heuristicNotes: const <String>[],
        parityKey: 'lib/features/ride/presentation/ride_recording_screen.dart',
        primarySourceFile:
            'lib/features/ride/presentation/ride_recording_screen.dart',
      ),
      UserPath(
        pathId: 'group_guard_blocked',
        moduleKey: 'features/group',
        featureKey: 'group',
        variant: 'negative',
        confidence: 'high',
        outcomeClass: 'guard_blocked',
        description: 'Protected-route guard journey inferred from group list.',
        sourceFiles: <String>[
          'lib/features/group/presentation/group_list_screen.dart',
        ],
        steps: const <PathStep>[],
        guards: const <String>[],
        validations: const <String>['groups.isEmpty'],
        errors: const <String>[],
        supabaseInteractions: const <String>[],
        heuristicNotes: const <String>[
          'Derived from auth/permission guard signals or protected route requirements.',
        ],
        parityKey: 'lib/features/group/presentation/group_list_screen.dart',
        primarySourceFile:
            'lib/features/group/presentation/group_list_screen.dart',
      ),
    ]);

    expect(
      classifications
          .firstWhere(
            (classification) => classification.journeyId == 'create_group',
          )
          .bucket,
      JourneyBucket.bAdapterRequired,
    );
    expect(
      classifications
          .firstWhere(
            (classification) =>
                classification.journeyId == 'ride_recording_validation',
          )
          .bucket,
      JourneyBucket.cDomainOracleRequired,
    );
    expect(
      classifications
          .firstWhere(
            (classification) =>
                classification.journeyId == 'group_guard_blocked',
          )
          .bucket,
      JourneyBucket.bAdapterRequired,
    );

    final editClassification = classifier.classify(<UserPath>[
      UserPath(
        pathId: 'edit_profile',
        moduleKey: 'features/profile',
        featureKey: 'profile',
        variant: 'positive',
        confidence: 'high',
        outcomeClass: 'entity_updated_visible',
        description: 'Edit profile flow',
        sourceFiles: <String>[
          'lib/features/profile/presentation/edit_profile_screen.dart',
        ],
        steps: const <PathStep>[],
        guards: const <String>[],
        validations: const <String>[],
        errors: const <String>[],
        supabaseInteractions: const <String>['update:profiles'],
        heuristicNotes: const <String>[],
        parityKey: 'lib/features/profile/presentation/edit_profile_screen.dart',
        primarySourceFile:
            'lib/features/profile/presentation/edit_profile_screen.dart',
      ),
    ]);
    expect(editClassification.single.bucket, JourneyBucket.bAdapterRequired);
    expect(editClassification.single.needsOutcomeProbe, isFalse);
  });

  test('coverage references mark executable journeys as covered', () {
    final result = CoverageReferenceBuilder().build(
      userPaths: <UserPath>[
        UserPath(
          pathId: 'UP_features_group_group_list_screen_positive_01',
          moduleKey: 'features/group',
          featureKey: 'group',
          variant: 'positive',
          confidence: 'high',
          outcomeClass: 'navigation_success',
          description: 'Group list navigation journey',
          sourceFiles: <String>[
            'lib/features/group/presentation/group_list_screen.dart',
          ],
          steps: const <PathStep>[],
          guards: const <String>[],
          validations: const <String>[],
          errors: const <String>[],
          supabaseInteractions: const <String>[],
          heuristicNotes: const <String>[],
          parityKey: 'lib/features/group/presentation/group_list_screen.dart',
          primarySourceFile:
              'lib/features/group/presentation/group_list_screen.dart',
        ),
      ],
      blockedPathReasons: const <String, List<String>>{},
    );

    expect(result.coverageReferences, hasLength(1));
    expect(
      result
          .pathToCoverageReferences['UP_features_group_group_list_screen_positive_01'],
      <String>[
        'coverage-ref://up_features_group_group_list_screen_positive_01',
      ],
    );
  });

  test('journey diff flags old-covered new-missed entries', () {
    final report = JourneyDiffBuilder().build(
      classifications: <JourneyClassification>[
        JourneyClassification(
          journeyId: 'create_group',
          bucket: JourneyBucket.bAdapterRequired,
          expectedOutcome: OutcomeFamily.entityCreated,
          needsSeed: false,
          needsOutcomeProbe: false,
        ),
      ],
      pathToCoverageReferences: <String, List<String>>{
        'create_group': <String>['coverage-ref://create_group'],
      },
    );

    expect(report.oldCoveredNewMissed, hasLength(1));
    expect(report.oldCoveredNewMissed.first.journeyId, 'create_group');
  });

  test('journey diff uses outcome probe journey id for parity checks', () {
    final report = JourneyDiffBuilder().build(
      classifications: <JourneyClassification>[
        JourneyClassification(
          journeyId: 'groups_create',
          bucket: JourneyBucket.bAdapterRequired,
          expectedOutcome: OutcomeFamily.entityCreated,
          needsSeed: true,
          needsOutcomeProbe: true,
        ),
      ],
      pathToCoverageReferences: <String, List<String>>{
        'groups_create': <String>['coverage-ref://groups_create'],
      },
      explorationResult: ExplorationResult(
        screens: const <VisitedScreen>[],
        interactions: const <TestedInteraction>[
          TestedInteraction(
            route: '/groups/create',
            widgetType: 'FilledButton',
            action: 'tap',
            outcome: InteractionOutcome.navigationOccurred,
            assertion: BehaviorAssertion(
              expectation: BehaviorExpectation.feedbackAfterSubmit,
              passed: true,
            ),
            outcomeProbe: OutcomeProbeResult(
              family: OutcomeFamily.entityCreated,
              passed: true,
              journeyId: 'groups_create',
            ),
          ),
        ],
        defects: const <FoundDefect>[],
        totalDuration: Duration.zero,
        visitedRoutes: <String>{'/groups/create'},
        unreachableRoutes: const <String>{},
      ),
    );

    expect(report.entries.single.newCovered, isTrue);
    expect(report.entries.single.outcomeParity, isTrue);
  });

  test(
    'journey diff can cover generic navigation journeys via route hints',
    () {
      final report = JourneyDiffBuilder().build(
        classifications: <JourneyClassification>[
          JourneyClassification(
            journeyId: 'UP_features_group_group_list_screen_positive_01',
            bucket: JourneyBucket.aGenericUi,
            expectedOutcome: OutcomeFamily.navigationSucceeded,
            needsSeed: false,
            needsOutcomeProbe: false,
          ),
        ],
        pathToCoverageReferences: <String, List<String>>{
          'UP_features_group_group_list_screen_positive_01': <String>[
            'coverage-ref://group_list_screen',
          ],
        },
        journeyRouteHints: <String, List<String>>{
          'UP_features_group_group_list_screen_positive_01': <String>[
            '/groups',
          ],
        },
        explorationResult: ExplorationResult(
          screens: const <VisitedScreen>[],
          interactions: const <TestedInteraction>[
            TestedInteraction(
              route: '/groups',
              widgetType: 'NavigationDestination',
              action: 'tap',
              outcome: InteractionOutcome.navigationOccurred,
              assertion: BehaviorAssertion(
                expectation: BehaviorExpectation.appStaysAlive,
                passed: true,
              ),
            ),
          ],
          defects: const <FoundDefect>[],
          totalDuration: Duration.zero,
          visitedRoutes: <String>{'/home', '/groups'},
          unreachableRoutes: const <String>{},
        ),
      );

      expect(report.entries.single.newCovered, isTrue);
      expect(report.entries.single.outcomeParity, isTrue);
    },
  );

  test(
    'journey diff matches parameterized route hints against concrete visited routes',
    () {
      final report = JourneyDiffBuilder().build(
        classifications: <JourneyClassification>[
          JourneyClassification(
            journeyId: 'UP_features_group_group_detail_screen_positive_01',
            bucket: JourneyBucket.bAdapterRequired,
            expectedOutcome: OutcomeFamily.navigationSucceeded,
            needsSeed: true,
            needsOutcomeProbe: false,
          ),
        ],
        pathToCoverageReferences: <String, List<String>>{
          'UP_features_group_group_detail_screen_positive_01': <String>[
            'coverage-ref://group_detail_screen',
          ],
        },
        journeyRouteHints: <String, List<String>>{
          'UP_features_group_group_detail_screen_positive_01': <String>[
            '/groups/:id',
          ],
        },
        explorationResult: ExplorationResult(
          screens: const <VisitedScreen>[],
          interactions: const <TestedInteraction>[],
          defects: const <FoundDefect>[],
          totalDuration: Duration.zero,
          visitedRoutes: <String>{
            '/groups/00000000-0000-4000-8000-000000000001',
          },
          unreachableRoutes: const <String>{},
        ),
      );

      expect(report.entries.single.newCovered, isTrue);
      expect(report.entries.single.outcomeParity, isTrue);
    },
  );

  test(
    'journey diff treats visited adapter routes as covered for bucket B',
    () {
      final report = JourneyDiffBuilder().build(
        classifications: <JourneyClassification>[
          JourneyClassification(
            journeyId: 'UP_features_profile_edit_profile_screen_positive_01',
            bucket: JourneyBucket.bAdapterRequired,
            expectedOutcome: OutcomeFamily.entityUpdated,
            needsSeed: true,
            needsOutcomeProbe: false,
          ),
        ],
        pathToCoverageReferences: <String, List<String>>{
          'UP_features_profile_edit_profile_screen_positive_01': <String>[
            'coverage-ref://edit_profile_screen',
          ],
        },
        journeyRouteHints: <String, List<String>>{
          'UP_features_profile_edit_profile_screen_positive_01': <String>[
            '/profile/edit',
          ],
        },
        explorationResult: ExplorationResult(
          screens: const <VisitedScreen>[],
          interactions: const <TestedInteraction>[],
          defects: const <FoundDefect>[],
          totalDuration: Duration.zero,
          visitedRoutes: <String>{'/profile/edit'},
          unreachableRoutes: const <String>{},
        ),
      );

      expect(report.entries.single.newCovered, isTrue);
      expect(report.entries.single.outcomeParity, isTrue);
    },
  );

  test('journey diff excludes bucket C from explorer parity regression', () {
    final report = JourneyDiffBuilder().build(
      classifications: <JourneyClassification>[
        JourneyClassification(
          journeyId: 'ride_recording',
          bucket: JourneyBucket.cDomainOracleRequired,
          expectedOutcome: OutcomeFamily.dataRecorded,
          needsSeed: false,
          needsOutcomeProbe: true,
        ),
      ],
      pathToCoverageReferences: <String, List<String>>{
        'ride_recording': <String>[
          'patrol_test/domain_tests/ride_recording_validation_test.dart',
        ],
      },
      explorationResult: ExplorationResult(
        screens: const <VisitedScreen>[],
        interactions: const <TestedInteraction>[],
        defects: const <FoundDefect>[],
        totalDuration: Duration.zero,
        visitedRoutes: const <String>{},
        unreachableRoutes: const <String>{},
      ),
    );

    expect(report.entries.single.newCovered, isTrue);
    expect(report.entries.single.outcomeParity, isTrue);
  });

  test('coverage feedback clamps route coverage to 100 percent', () {
    final coverage = const CoverageFeedback().compute(
      groundTruth: GroundTruthModel(
        routes: <RouteGroundTruth>[
          RouteGroundTruth(
            path: '/groups',
            screen: 'GroupListScreen',
            authRequired: true,
            hasForm: false,
            guards: <String>[],
            parent: null,
            subjourneys: <String>[],
            sequentialTransitions: <String>[],
            interactiveElements: <String>[],
          ),
        ],
        entryScreens: const <String>['/groups'],
        guards: const <String>[],
        dialogs: const <String>[],
        parameterizedRouteFamilies: const <String>[],
        totalInteractiveElements: 1,
        formSubmits: 0,
      ),
      explorationResult: ExplorationResult(
        screens: const <VisitedScreen>[],
        interactions: const <TestedInteraction>[],
        defects: const <FoundDefect>[],
        totalDuration: Duration.zero,
        visitedRoutes: <String>{'/home', '/groups'},
        unreachableRoutes: const <String>{},
      ),
    );

    expect(coverage.routeCoverage, 1.0);
  });

  test('exploration materializer decodes wrapped Android log payloads', () {
    final payload = base64Encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'screens': <Object?>[
            <String, Object?>{
              'route': '/home',
              'interactive_widgets': <Object?>[
                <String, Object?>{
                  'widget_type': 'NavigationDestination',
                  'label': 'Groups',
                },
              ],
              'visited_at': '2026-03-12T08:56:19.508000',
              'has_content': true,
            },
          ],
          'interactions': <Object?>[
            <String, Object?>{
              'route': '/home',
              'widget_type': 'NavigationDestination',
              'action': 'tap',
              'outcome': 'navigationOccurred',
              'assertion': <String, Object?>{
                'expectation': 'navigationOnListItemTap',
                'passed': true,
              },
            },
          ],
          'defects': <Object?>[],
          'total_duration_ms': 17000,
          'visited_routes': <Object?>['/home', '/groups'],
          'unreachable_routes': <Object?>[],
          'passed_assertions': 1,
          'behavior_violations': 0,
          'crashes': 0,
          'timeouts': 0,
        }),
      ),
    );
    final wrapped = <String>[
      payload.substring(0, 80),
      payload.substring(80, 160),
      payload.substring(160),
    ].join('\n03-12 08:56:22.301 22718 22718 I flutter : ');
    final log =
        '''
03-12 08:56:22.301 22718 22718 I flutter : E2E_EXPLORATION_RESULT_START
03-12 08:56:22.301 22718 22718 I flutter : $wrapped
03-12 08:56:22.301 22718 22718 I flutter : E2E_EXPLORATION_RESULT_END
''';

    final result = extractExplorationResultFromLog(log);

    expect(result.visitedRoutes, containsAll(<String>{'/home', '/groups'}));
    expect(result.interactions, hasLength(1));
    expect(result.screens.single.route, '/home');
  });

  testWidgets('blind explorer discovers labeled navigation and routed screen', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            bottomNavigationBar: NavigationBar(
              destinations: const <NavigationDestination>[
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.group_outlined),
                  label: 'Groups',
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const FilledButton(onPressed: null, child: Text('Continue')),
              ],
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final result = await BlindExplorer(
      tester: tester,
      adapter: const _FakeProjectAdapter(),
      inputStrategy: const InputStrategy(),
      maxDepth: 0,
      maxActionsPerScreen: 0,
    ).explore();

    expect(result.visitedRoutes, contains('/home'));
    expect(
      result.screens.single.interactiveWidgets,
      contains(
        isA<DiscoveredWidget>().having(
          (widget) => widget.label,
          'label',
          'Home',
        ),
      ),
    );
    expect(
      result.screens.single.interactiveWidgets,
      contains(
        isA<DiscoveredWidget>().having(
          (widget) => widget.label,
          'label',
          'Groups',
        ),
      ),
    );
  });

  testWidgets(
    'blind explorer records adapter-driven child routes from gap hints',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/profile',
        routes: <RouteBase>[
          GoRoute(
            path: '/profile',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Profile'))),
            routes: <RouteBase>[
              GoRoute(
                path: 'edit',
                builder: (context, state) => Scaffold(
                  body: Form(
                    child: TextFormField(
                      decoration: InputDecoration(labelText: 'Display Name'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final result = await BlindExplorer(
        tester: tester,
        adapter: _RoutePushingAdapter('/profile/edit'),
        inputStrategy: const InputStrategy(),
        maxDepth: 0,
        maxActionsPerScreen: 0,
        gapHints: <String>{'/profile/edit'},
      ).explore();

      expect(result.visitedRoutes, contains('/profile/edit'));
    },
  );
}

class _FakeProjectAdapter implements ProjectAdapter {
  const _FakeProjectAdapter();

  @override
  List<Finder> additionalInteractiveWidgetFinders() => const <Finder>[];

  @override
  Future<void> cleanup() async {}

  @override
  Future<void> ensureAppStarted(WidgetTester tester) async {}

  @override
  Future<void> restartApp(WidgetTester tester) async {}

  @override
  Future<void> handlePermissions(PatrolIntegrationTester patrolTester) async {}

  @override
  Future<void> performLogin(WidgetTester tester) async {}

  @override
  Future<bool> navigateToRoute(WidgetTester tester, String route) async =>
      false;

  @override
  Future<String?> materializeRoute(String routePattern) async => routePattern;

  @override
  Future<OutcomeProbeResult?> probeOutcome(
    String journeyId,
    String route,
    InteractionOutcome outcome,
  ) async => null;

  @override
  Future<void> seedForRoute(String route) async {}
}

class _RoutePushingAdapter extends _FakeProjectAdapter {
  const _RoutePushingAdapter(this.targetRoute);

  final String targetRoute;

  @override
  Future<bool> navigateToRoute(WidgetTester tester, String route) async {
    if (route != targetRoute) {
      return false;
    }
    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final router = materialApp.routerConfig as GoRouter;
    router.go(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return true;
  }
}
