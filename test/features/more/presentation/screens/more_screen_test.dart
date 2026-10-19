import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/more/presentation/screens/more_screen.dart';

import '../../../../helpers/fake_auth.dart';

void main() {
  group('MoreScreen Widget Tests', () {
    testWidgets('hides Deficiencies module for technician with assets.view', (tester) async {
      final session = fakeSession(
        role: AuthRole.maintenanceStaff,
        permissions: const [
          'maintenance.view',
          'maintenance.edit',
          'assets.view',
          'assets.replace',
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: MoreScreen(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('more_menu_deficiencies')), findsNothing);
    });

    testWidgets('shows Deficiencies module for Depot Incharge with assets.view', (tester) async {
      final session = fakeSession(
        role: AuthRole.depotIncharge,
        permissions: const [
          'maintenance.view',
          'maintenance.edit',
          'assets.view',
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: MoreScreen(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('more_menu_deficiencies')), findsOneWidget);
    });
  });
}

