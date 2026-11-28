import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/utils/gallery_permission.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/checklist_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthRepository extends Mock implements IAuthRepository {}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._initial);
  final AuthState _initial;
  @override
  AuthState build() => _initial;
}

class _FakeGalleryPermissionService extends GalleryPermissionService {
  @override
  Future<bool> request(BuildContext context) async => true;
}

class _FakeEvidenceService extends EvidenceService {
  _FakeEvidenceService(this._file);
  final EvidenceFile _file;
  @override
  Future<EvidenceFile?> capture({
    required EvidenceKind kind,
    ImageSource source = ImageSource.camera,
    bool captureLocation = false,
    int imageQuality = 80,
    double maxWidth = 1600,
    double maxHeight = 1600,
  }) async =>
      _file;
}

class _CapturedRequest {
  _CapturedRequest(this.method, this.path, this.fieldKeys, this.fields, this.fileKeys);
  final String method;
  final String path;
  final Set<String> fieldKeys;
  final Map<String, String> fields;
  final Set<String> fileKeys;
}

class _RecordingAdapter implements HttpClientAdapter {
  final List<_CapturedRequest> calls = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final fields = <String, String>{};
    final fileKeys = <String>{};
    if (options.data is FormData) {
      final fd = options.data as FormData;
      for (final e in fd.fields) {
        fields[e.key] = e.value;
      }
      for (final f in fd.files) {
        fileKeys.add(f.key);
      }
    }
    calls.add(_CapturedRequest(
      options.method,
      options.path,
      fields.keys.toSet(),
      fields,
      fileKeys,
    ));

    if (options.path == '/api/v1/maintenance/records/55/' &&
        options.method == 'GET') {
      return _json({
        'id': 55,
        'work_order': 77,
        'work_order_status': 'IN_PROGRESS',
        'station': 10,
        'station_name': 'MAS',
        'status': 'PENDING',
        'lines': [
          {
            'id': 101,
            'item_name': 'Track Relay',
            'inspection_point': 'Coil Check',
            'value_type': 'TEXT',
            'recorded_value': 'ok',
            'status': 'OK',
            'required': true,
            'checked_out': true,
            'excluded': false,
          }
        ],
      });
    }
    if (options.path == '/api/v1/maintenance/records/55/' &&
        options.method == 'PATCH') {
      return _json({'id': 55, 'status': 'PENDING'});
    }
    if (options.path == '/api/v1/maintenance/records/55/complete/' &&
        options.method == 'POST') {
      return _json({'status': 'completed'});
    }
    return _json({'detail': 'unexpected ${options.path}'}, status: 404);
  }

  ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

UserSession _session({required bool isContractStaff}) => UserSession(
      accessToken: 'tok',
      userId: 13,
      username: isContractStaff ? 'cs_tech' : 'dept_tech',
      firstName: 'Test',
      lastName: 'User',
      primaryRole: AuthRole.maintenanceStaff,
      roles: const [AuthRole.maintenanceStaff],
      permissions: const ['maintenance.view', 'maintenance.edit'],
      scope: const OrgScope(level: OrgScopeLevel.depot),
      isContractStaff: isContractStaff,
    );

Future<void> _openCompletionSheet(
  WidgetTester tester, {
  required bool isContractStaff,
  required _RecordingAdapter adapter,
  required IAuthRepository authRepo,
  required EvidenceFile proofFile,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    ..httpClientAdapter = adapter;
  final session = _session(isContractStaff: isContractStaff);
  when(() => authRepo.currentSession).thenReturn(session);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheServiceProvider
            .overrideWithValue(InMemoryLocalCacheService()),
        authRepositoryProvider.overrideWithValue(authRepo),
        authControllerProvider
            .overrideWith(() => _FakeAuthController(Authenticated(session))),
        authenticatedDioProvider.overrideWithValue(dio),
        galleryPermissionServiceProvider
            .overrideWithValue(_FakeGalleryPermissionService()),
        evidenceServiceProvider
            .overrideWithValue(_FakeEvidenceService(proofFile)),
      ],
      child: const MaterialApp(
        home: ChecklistFormScreen(recordId: 55),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('complete_checklist_button')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('completion_confirm_button')), findsOneWidget);
}

void main() {
  late _MockAuthRepository mockRepo;
  late File tempJpg;
  late EvidenceFile proofFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockRepo = _MockAuthRepository();
    tempJpg = File('${Directory.systemTemp.path}/s8_3e_proof.jpg');
    await tempJpg.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    proofFile = EvidenceFile(
      path: tempJpg.path,
      kind: EvidenceKind.proof,
      sizeBytes: 4,
    );
  });

  tearDown(() async {
    if (await tempJpg.exists()) {
      await tempJpg.delete();
    }
  });

  group('S8-3e _CompletionSheet Other Staff Involved', () {
    testWidgets('(a) cs=true: completion sheet has no completion_other_staff_field',
        (tester) async {
      final adapter = _RecordingAdapter();
      await _openCompletionSheet(
        tester,
        isContractStaff: true,
        adapter: adapter,
        authRepo: mockRepo,
        proofFile: proofFile,
      );

      expect(
        find.byKey(const Key('completion_other_staff_field')),
        findsNothing,
      );
    });

    testWidgets(
        '(b) cs=true: completing with proof photo sends no other_staff key in PATCH',
        (tester) async {
      final adapter = _RecordingAdapter();
      await _openCompletionSheet(
        tester,
        isContractStaff: true,
        adapter: adapter,
        authRepo: mockRepo,
        proofFile: proofFile,
      );

      await tester.tap(find.byKey(const Key('completion_pick_photo')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('completion_remarks_field')),
        'All checklist items verified',
      );
      final confirmBtn = find.byKey(const Key('completion_confirm_button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pump(const Duration(milliseconds: 50));

      final patches = adapter.calls
          .where((c) => c.method == 'PATCH' && c.path.endsWith('/records/55/'))
          .toList();
      expect(patches, hasLength(1));
      expect(patches.single.fieldKeys.contains('other_staff'), isFalse);
      expect(patches.single.fileKeys.contains('proof_of_execution_upload'), isTrue);
    });

    testWidgets(
        '(c) cs=false: completion_other_staff_field is shown and other_staff is sent when filled',
        (tester) async {
      final adapter = _RecordingAdapter();
      await _openCompletionSheet(
        tester,
        isContractStaff: false,
        adapter: adapter,
        authRepo: mockRepo,
        proofFile: proofFile,
      );

      final otherField = find.byKey(const Key('completion_other_staff_field'));
      expect(otherField, findsOneWidget);
      await tester.enterText(otherField, 'Helper A');
      await tester.enterText(
        find.byKey(const Key('completion_remarks_field')),
        'All checklist items verified',
      );
      final confirmBtn = find.byKey(const Key('completion_confirm_button'));
      await tester.ensureVisible(confirmBtn);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      final patches = adapter.calls
          .where((c) => c.method == 'PATCH' && c.path.endsWith('/records/55/'))
          .toList();
      expect(patches, hasLength(1));
      expect(patches.single.fields['other_staff'], 'Helper A');
    });
  });
}
