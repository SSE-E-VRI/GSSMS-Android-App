import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/authenticated_image_thumbnail.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';

UserSession _session({String token = 'test-token-123'}) => UserSession(
      accessToken: token,
      username: 'tech',
      firstName: 'Technician',
      lastName: '',
      roles: const [AuthRole.depotIncharge],
      primaryRole: AuthRole.depotIncharge,
      permissions: const ['*'],
      scope: const OrgScope(level: OrgScopeLevel.depot),
    );

void main() {
  Widget buildFrame({
    required String? url,
    String? token,
    Key? tapKey,
  }) {
    final session = token != null ? _session(token: token) : null;
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(session != null ? Authenticated(session) : const Unauthenticated()),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AuthenticatedImageThumbnail(
            url: url,
            previewTitle: 'Test Photo #42',
            tapKey: tapKey,
          ),
        ),
      ),
    );
  }

  testWidgets('renders placeholder when url is null', (tester) async {
    await tester.pumpWidget(buildFrame(url: null));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('renders placeholder when url is empty', (tester) async {
    await tester.pumpWidget(buildFrame(url: '   '));
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('renders Image.network with auth header and opens preview on tap', (tester) async {
    const tapKey = Key('test_photo_thumb');
    await tester.pumpWidget(buildFrame(
      url: 'https://example.com/media/photos/photo_42.jpg',
      token: 'jwt-auth-header-check',
      tapKey: tapKey,
    ));

    final imageFinder = find.byType(Image);
    expect(imageFinder, findsOneWidget);

    final imageWidget = tester.widget<Image>(imageFinder);
    expect(imageWidget.image, isA<NetworkImage>());
    final netImage = imageWidget.image as NetworkImage;
    expect(netImage.headers?['Authorization'], 'Bearer jwt-auth-header-check');

    // Tap to open preview
    await tester.tap(find.byKey(tapKey));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoPreviewScaffold), findsOneWidget);
    expect(find.text('Test Photo #42'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}
