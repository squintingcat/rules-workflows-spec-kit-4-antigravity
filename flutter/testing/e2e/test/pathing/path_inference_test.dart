import 'package:flutter_test/flutter_test.dart';

import '../../framework/pathing/src/models.dart';
import '../../framework/pathing/src/path_inference.dart';

void main() {
  test('infers positive, negative and sequential variants from signals', () {
    final signal = FileSignals(
      filePath: 'lib/features/auth/presentation/login_screen.dart',
      moduleKey: 'features/auth',
      featureKey: 'auth',
      isUiFile: true,
      screens: <String>{'LoginScreen'},
      widgets: <String>{},
      routes: <String>{'/login', '/home'},
      navigationTransitions: <String>{'/home'},
      uiActions: <String>{'onPressed:_submit'},
      forms: <String>{'Form', 'TextFormField'},
      validations: <String>{'validator:required', 'validator:email'},
      guards: <String>{'if (!isAuthenticated)'},
      errorPaths: <String>{'catch:AuthException'},
      repositoryCalls: <String>{'authRepository.signIn'},
      serviceCalls: <String>{},
      stateChanges: <String>{'setState'},
      supabaseInteractions: <String>{'supabase.auth.signInWithOtp'},
      crudOperations: <String>{'create', 'read', 'update', 'delete', 'auth'},
      authOperations: <String>{'signInWithOtp'},
      commentHints: <String>{'// TODO retry path'},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/auth/presentation/login_screen.dart',
          line: 10,
          column: 3,
          label: 'screen:LoginScreen',
        ),
      ],
    );

    final docs = DocumentationSignals(
      moduleHints: <String, List<String>>{
        'features/auth': <String>['login flow with retry on error'],
      },
      moduleRoutes: <String, List<String>>{
        'features/auth': <String>['/login', '/home'],
      },
      globalHints: const <String>[],
      documentationFiles: const <String>['README.md'],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[signal],
      documentationSignals: docs,
      routeBindings: const <String, List<String>>{
        'LoginScreen': <String>['/login'],
      },
    );

    expect(paths.any((path) => path.variant == 'positive'), isTrue);
    expect(
      paths.any((path) => path.outcomeClass == 'validation_error'),
      isTrue,
    );
    expect(paths.any((path) => path.outcomeClass == 'guard_blocked'), isTrue);
    expect(paths.any((path) => path.outcomeClass == 'backend_error'), isTrue);
    expect(paths.any((path) => path.variant == 'sequential'), isTrue);

    final positive = paths.firstWhere((path) => path.variant == 'positive');
    expect(
      positive.pathId,
      startsWith('UP_features_auth_login_screen_positive_'),
    );
    expect(positive.steps.map((step) => step.kind), contains('entry'));
    expect(positive.steps.map((step) => step.kind), contains('navigation'));
    expect(positive.steps.map((step) => step.kind), contains('data'));
    expect(
      positive.steps.any((step) => step.description.contains('/login')),
      isTrue,
    );
  });

  test('skips non-routable presentation files and shared widgets', () {
    final sharedWidget = FileSignals(
      filePath: 'lib/shared/ui_kit/inputs/app_year_select.dart',
      moduleKey: 'shared/ui_kit',
      featureKey: 'shared',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'AppYearSelect'},
      routes: const <String>{},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onChanged:_handleYearChanged'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[],
    );

    final internalFeatureWidget = FileSignals(
      filePath: 'lib/features/group/presentation/widgets/facility_tab.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'FacilityTab'},
      routes: const <String>{},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onPressed:_openEditor'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[],
    );

    final unroutableScreen = FileSignals(
      filePath: 'lib/features/group/presentation/group_debug_screen.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: <String>{'GroupDebugScreen'},
      widgets: const <String>{},
      routes: const <String>{},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onPressed:_debugAction'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[
        sharedWidget,
        internalFeatureWidget,
        unroutableScreen,
      ],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'LoginScreen': <String>['/login'],
      },
    );

    expect(paths, isEmpty);
  });

  test('prefers submit-like actions over field change callbacks', () {
    final signal = FileSignals(
      filePath: 'lib/features/group/presentation/join_group_screen.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: <String>{'JoinGroupScreen'},
      widgets: const <String>{},
      routes: <String>{'/groups/join'},
      navigationTransitions: const <String>{},
      uiActions: <String>{
        'onChanged:_toggleHorseSelection',
        'onPressed:_submit',
      },
      forms: <String>{'Form', 'TextFormField'},
      validations: <String>{'validator:required'},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: <String>{'groupRepository.joinGroup'},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: <String>{'create'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/group/presentation/join_group_screen.dart',
          line: 13,
          column: 7,
          label: 'screen:JoinGroupScreen',
        ),
      ],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[signal],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'JoinGroupScreen': <String>['/groups/join'],
      },
    );

    final positive = paths.firstWhere((path) => path.variant == 'positive');
    final actionStep = positive.steps.firstWhere(
      (step) => step.kind == 'action',
    );
    expect(actionStep.description, contains('onPressed:_submit'));
    expect(
      actionStep.description,
      isNot(contains('onChanged:_toggleHorseSelection')),
    );
  });

  test('infers empty-state list journeys from companion list views', () {
    final listScreen = FileSignals(
      filePath: 'lib/features/group/presentation/group_list_screen.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: <String>{'GroupListScreen'},
      widgets: const <String>{},
      routes: <String>{'/groups'},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onPressed:_showActionSheet'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/group/presentation/group_list_screen.dart',
          line: 12,
          column: 7,
          label: 'screen:GroupListScreen',
        ),
      ],
    );

    final listView = FileSignals(
      filePath: 'lib/features/group/presentation/group_list_view.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'GroupListView'},
      routes: const <String>{},
      navigationTransitions: <String>{'/groups/create', '/groups/join'},
      uiActions: <String>{
        'onPressed:() => context.go(\'/groups/create\')',
        'onPressed:() => context.go(\'/groups/join\')',
      },
      forms: const <String>{},
      validations: const <String>{},
      guards: <String>{'if (groups.isEmpty)'},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: <String>{
        'ref.read(groupControllerProvider.notifier).refreshGroups',
      },
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/group/presentation/group_list_view.dart',
          line: 22,
          column: 11,
          label: 'widget:GroupListView',
        ),
      ],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[listScreen, listView],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'GroupListScreen': <String>['/groups'],
      },
    );

    final positive = paths.firstWhere((path) => path.variant == 'positive');
    expect(positive.outcomeClass, equals('empty_state_actionable'));
    expect(positive.steps.any((step) => step.kind == 'empty_state'), isTrue);
    expect(
      positive.steps.any((step) => step.description.contains('/groups/create')),
      isTrue,
    );
  });

  test('infers route-bound core screens and dialog entries', () {
    final developerSignal = FileSignals(
      filePath: 'lib/core/presentation/developer_settings_screen.dart',
      moduleKey: 'core/presentation',
      featureKey: 'core',
      isUiFile: true,
      screens: <String>{'DeveloperSettingsScreen'},
      widgets: const <String>{},
      routes: const <String>{},
      navigationTransitions: const <String>{'push'},
      uiActions: <String>{'onPressed:_openDatabaseDebug'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: <String>{'notifier.enableAll'},
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/core/presentation/developer_settings_screen.dart',
          line: 5,
          column: 7,
          label: 'screen:DeveloperSettingsScreen',
        ),
      ],
    );

    final equipmentDialogSignal = FileSignals(
      filePath:
          'lib/features/equipment/presentation/widgets/equipment_detail_dialog.dart',
      moduleKey: 'features/equipment',
      featureKey: 'equipment',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'EquipmentDetailDialog'},
      routes: const <String>{},
      navigationTransitions: const <String>{'push', 'pop'},
      uiActions: <String>{'onPressed:_closeDialog'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: <String>{'equipmentRepository.getEquipmentItem'},
      serviceCalls: const <String>{},
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file:
              'lib/features/equipment/presentation/widgets/equipment_detail_dialog.dart',
          line: 10,
          column: 7,
          label: 'widget:EquipmentDetailDialog',
        ),
      ],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[developerSignal, equipmentDialogSignal],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'DeveloperSettingsScreen': <String>['/profile/developer'],
        'EquipmentDetailDialog': <String>['/equipment/:id'],
      },
    );

    expect(
      paths.any(
        (path) =>
            path.primarySourceFile ==
            'lib/core/presentation/developer_settings_screen.dart',
      ),
      isTrue,
    );
    expect(
      paths.any(
        (path) =>
            path.primarySourceFile ==
            'lib/features/equipment/presentation/widgets/equipment_detail_dialog.dart',
      ),
      isTrue,
    );
  });

  test('infers embedded subjourneys from parent-instantiated widgets', () {
    final parent = FileSignals(
      filePath: 'lib/features/group/presentation/group_detail_screen.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: <String>{'GroupDetailScreen'},
      widgets: const <String>{},
      instantiatedWidgets: <String>{'MembersTab', 'FacilityTab'},
      routes: <String>{'/groups/:id'},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onTap:_toggleSidebar'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/group/presentation/group_detail_screen.dart',
          line: 12,
          column: 7,
          label: 'screen:GroupDetailScreen',
        ),
      ],
    );

    final members = FileSignals(
      filePath: 'lib/features/group/presentation/widgets/members_tab.dart',
      moduleKey: 'features/group',
      featureKey: 'group',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'MembersTab'},
      routes: const <String>{},
      navigationTransitions: const <String>{},
      uiActions: const <String>{},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: <String>{'groupRepository.syncGroupMembers'},
      serviceCalls: <String>{'ref.watch(groupMembersProvider(groupId))'},
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/group/presentation/widgets/members_tab.dart',
          line: 9,
          column: 7,
          label: 'widget:MembersTab',
        ),
      ],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[parent, members],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'GroupDetailScreen': <String>['/groups/:id'],
      },
    );

    final membersPath = paths.where(
      (path) =>
          path.primarySourceFile ==
              'lib/features/group/presentation/widgets/members_tab.dart' &&
          path.variant == 'positive',
    );

    expect(membersPath, isNotEmpty);
    expect(
      membersPath.first.steps.any(
        (step) =>
            step.kind == 'action' && step.description.contains('MembersTab'),
      ),
      isTrue,
    );
    expect(
      membersPath.first.heuristicNotes.any(
        (note) => note.contains('Subjourney inferred from'),
      ),
      isTrue,
    );
  });

  test('infers nested cross-module dialog subjourneys from embedded widgets', () {
    final horseDetail = FileSignals(
      filePath: 'lib/features/horse/presentation/horse_detail_screen.dart',
      moduleKey: 'features/horse',
      featureKey: 'horse',
      isUiFile: true,
      screens: <String>{'HorseDetailScreen'},
      widgets: const <String>{},
      instantiatedWidgets: <String>{'HorseEquipmentView'},
      routes: <String>{'/horses/:id'},
      navigationTransitions: const <String>{},
      uiActions: <String>{'onTap:_openEquipment'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: const <String>{},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'read'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/horse/presentation/horse_detail_screen.dart',
          line: 12,
          column: 7,
          label: 'screen:HorseDetailScreen',
        ),
      ],
    );

    final horseEquipment = FileSignals(
      filePath: 'lib/features/horse/presentation/horse_equipment_view.dart',
      moduleKey: 'features/horse',
      featureKey: 'horse',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'HorseEquipmentView'},
      instantiatedWidgets: <String>{'EquipmentAssignmentDialog'},
      routes: const <String>{},
      navigationTransitions: const <String>{'/profile/add_equipment'},
      uiActions: const <String>{'onPressed:_assignEquipment'},
      forms: const <String>{},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{},
      repositoryCalls: <String>{'equipmentRepository.assignEquipment'},
      serviceCalls: const <String>{},
      stateChanges: const <String>{},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'update'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file: 'lib/features/horse/presentation/horse_equipment_view.dart',
          line: 20,
          column: 7,
          label: 'widget:HorseEquipmentView',
        ),
      ],
    );

    final assignmentDialog = FileSignals(
      filePath:
          'lib/features/equipment/presentation/widgets/equipment_assignment_dialog.dart',
      moduleKey: 'features/equipment',
      featureKey: 'equipment',
      isUiFile: true,
      screens: const <String>{},
      widgets: <String>{'EquipmentAssignmentDialog'},
      routes: const <String>{},
      navigationTransitions: const <String>{},
      uiActions: const <String>{'onPressed:_saveAssignment'},
      forms: <String>{'Form'},
      validations: const <String>{},
      guards: const <String>{},
      errorPaths: const <String>{'catch:dynamic'},
      repositoryCalls: <String>{'equipmentRepository.assignEquipment'},
      serviceCalls: const <String>{},
      stateChanges: const <String>{'setState'},
      supabaseInteractions: const <String>{},
      crudOperations: const <String>{'update'},
      authOperations: const <String>{},
      commentHints: const <String>{},
      references: const <SourceReference>[
        SourceReference(
          file:
              'lib/features/equipment/presentation/widgets/equipment_assignment_dialog.dart',
          line: 10,
          column: 7,
          label: 'widget:EquipmentAssignmentDialog',
        ),
      ],
    );

    final paths = PathInferer().infer(
      fileSignals: <FileSignals>[horseDetail, horseEquipment, assignmentDialog],
      documentationSignals: DocumentationSignals(
        moduleHints: const <String, List<String>>{},
        moduleRoutes: const <String, List<String>>{},
        globalHints: const <String>[],
        documentationFiles: const <String>[],
      ),
      routeBindings: const <String, List<String>>{
        'HorseDetailScreen': <String>['/horses/:id'],
      },
    );

    final assignmentPaths = paths.where(
      (path) =>
          path.primarySourceFile ==
              'lib/features/equipment/presentation/widgets/equipment_assignment_dialog.dart' &&
          path.variant == 'positive',
    );

    expect(assignmentPaths, isNotEmpty);
    expect(
      assignmentPaths.first.steps.any(
        (step) =>
            step.kind == 'action' &&
            step.description.contains('EquipmentAssignmentDialog'),
      ),
      isTrue,
    );
  });
}
