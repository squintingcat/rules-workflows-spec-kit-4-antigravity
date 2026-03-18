import 'package:flutter_test/flutter_test.dart';

import '../../framework/pathing/src/path_utils.dart';

void main() {
  test('maps journeys to stable coverage reference ids', () {
    expect(
      coverageReferenceIdForPath(
        'UP_features_group_add_facility_screen_positive_01',
      ),
      'coverage-ref://up_features_group_add_facility_screen_positive_01',
    );
  });

  test('resolves module keys from project structure', () {
    expect(
      moduleKeyFromPath('lib/features/auth/presentation/login_screen.dart'),
      'features/auth',
    );
    expect(
      moduleKeyFromPath('lib/shared/ui_kit/buttons/app_button.dart'),
      'shared/ui_kit',
    );
    expect(
      moduleKeyFromPath('lib/core/services/log_service.dart'),
      'core/services',
    );
    expect(moduleKeyFromPath('lib/config/router.dart'), 'config');
  });

  test('builds relative imports for explorer files', () {
    final importPath = relativeImportPath(
      fromFile: 'patrol_test/explorer/blind_explorer_e2e_test.dart',
      toFile: 'testing/e2e/framework/explorer/src/project_adapter.dart',
    );

    expect(
      importPath,
      '../../testing/e2e/framework/explorer/src/project_adapter.dart',
    );
  });

  test('detects valid journey entry files in supported presentation roots', () {
    expect(
      isJourneyEntryFilePath(
        'lib/features/auth/presentation/login_screen.dart',
      ),
      isTrue,
    );
    expect(
      isJourneyEntryFilePath('lib/features/feed/presentation/feed_view.dart'),
      isTrue,
    );
    expect(
      isJourneyEntryFilePath(
        'lib/features/horse/presentation/create_horse_wizard.dart',
      ),
      isTrue,
    );
    expect(
      isJourneyEntryFilePath(
        'lib/core/presentation/developer_settings_screen.dart',
      ),
      isTrue,
    );
    expect(
      isJourneyEntryFilePath(
        'lib/features/equipment/presentation/widgets/equipment_detail_dialog.dart',
      ),
      isTrue,
    );
    expect(
      isJourneyEntryFilePath(
        'lib/features/group/presentation/widgets/facility_tab.dart',
      ),
      isFalse,
    );
    expect(
      isJourneyEntryFilePath(
        'lib/shared/ui_kit/inputs/app_text_form_field.dart',
      ),
      isFalse,
    );
  });
}
