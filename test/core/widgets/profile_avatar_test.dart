import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/services/profile_photo_cache.dart';
import 'package:gssms_mobile/core/widgets/profile_avatar.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  // 1x1 transparent PNG byte stream for offline test
  final samplePngBytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ];

  group('ProfileAvatar Widget Tests', () {
    testWidgets('renders initials when photoUrl is null', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: 'Ramesh Kumar',
                photoUrl: null,
                radius: 24,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);
      expect(find.text('RK'), findsOneWidget);
      expect(find.byKey(const Key('profile_avatar_image')), findsNothing);
    });

    testWidgets('renders single initial for single-word display name', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: 'Admin',
                photoUrl: null,
                radius: 24,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('renders fallback "U" for empty display name', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: '',
                photoUrl: null,
                radius: 24,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_initials')), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
    });

    testWidgets('renders camera badge when onCameraTap is provided and triggers callback', (tester) async {
      var cameraTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: 'Ramesh',
                photoUrl: null,
                onCameraTap: () => cameraTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_camera_badge')), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile_avatar_camera_badge')));
      expect(cameraTapped, isTrue);
    });

    testWidgets('does not render camera badge when onCameraTap is null', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: 'Ramesh',
                photoUrl: null,
                onCameraTap: null,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_camera_badge')), findsNothing);
    });

    testWidgets('renders upload progress overlay when isUploading is true', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ProfileAvatar(
                displayName: 'Ramesh',
                photoUrl: null,
                isUploading: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('profile_avatar_uploading')), findsOneWidget);
    });

    testWidgets('renders image from local disk cache offline without network call', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('profile_cache_test_');
      try {
        final cache = ProfilePhotoCache(
          baseUrl: 'http://localhost:8000',
          storageDir: tempDir,
        );
        // Pre-populate disk cache
        await cache.savePhotoBytes(99, samplePngBytes, ext: 'png');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              profilePhotoCacheProvider.overrideWithValue(cache),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ProfileAvatar(
                  userId: 99,
                  photoUrl: '/media/profile_pictures/user_99.png',
                  displayName: 'Ramesh Kumar',
                  radius: 30,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Image must be rendered from disk cache
        expect(find.byKey(const Key('profile_avatar_image')), findsOneWidget);
        expect(find.byKey(const Key('profile_avatar_initials')), findsNothing);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('ProfilePhotoCache storage hygiene', () {
    Directory createTempDir() =>
        Directory.systemTemp.createTempSync('profile_cache_hygiene_');

    test('replacing a photo clears stale other-extension files', () async {
      final tempDir = createTempDir();
      try {
        final cache = ProfilePhotoCache(
          baseUrl: 'http://localhost:8000',
          storageDir: tempDir,
        );
        await cache.savePhotoBytes(7, samplePngBytes, ext: 'jpg');
        expect(
          File('${tempDir.path}${Platform.pathSeparator}profile_7.jpg').existsSync(),
          isTrue,
        );

        await cache.savePhotoBytes(7, samplePngBytes, ext: 'png');
        // The stale jpg must not survive to win the lookup order.
        expect(
          File('${tempDir.path}${Platform.pathSeparator}profile_7.jpg').existsSync(),
          isFalse,
        );
        final got = await cache.getCachedPhoto(7);
        expect(got?.path.endsWith('profile_7.png'), isTrue);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('refuses to cache non-image responses (no cache poisoning)', () async {
      final tempDir = createTempDir();
      try {
        final dio = MockDio();
        when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
            .thenAnswer(
          (_) async => Response<List<int>>(
            requestOptions: RequestOptions(path: '/media/profile_pictures/u8.jpg'),
            statusCode: 403,
            headers: Headers.fromMap({
              'content-type': ['text/html'],
            }),
            data: utf8.encode('<html>forbidden</html>'),
          ),
        );
        final cache = ProfilePhotoCache(
          baseUrl: 'http://localhost:8000',
          storageDir: tempDir,
          dio: dio,
        );

        final result =
            await cache.downloadAndCache(8, '/media/profile_pictures/u8.jpg');
        expect(result, isNull);
        expect(await cache.getCachedPhoto(8), isNull);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });

    test('caches image responses', () async {
      final tempDir = createTempDir();
      try {
        final dio = MockDio();
        when(() => dio.get<List<int>>(any(), options: any(named: 'options')))
            .thenAnswer(
          (_) async => Response<List<int>>(
            requestOptions: RequestOptions(path: '/media/profile_pictures/u9.jpg'),
            statusCode: 200,
            headers: Headers.fromMap({
              'content-type': ['image/jpeg'],
            }),
            data: samplePngBytes,
          ),
        );
        final cache = ProfilePhotoCache(
          baseUrl: 'http://localhost:8000',
          storageDir: tempDir,
          dio: dio,
        );

        final result =
            await cache.downloadAndCache(9, '/media/profile_pictures/u9.jpg');
        expect(result, isNotNull);
        expect(await cache.getCachedPhoto(9), isNotNull);
      } finally {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });
}
