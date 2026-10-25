import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/deficiency_severity_option.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/group_inclusion_result.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/technician.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_action.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/verification_workspace_screen.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockWorkOrderRepository mockRepo;

  const newOrder = WorkOrder(
    id: 101,
    status: WorkOrderStatus.newOrder,
    type: WorkOrderType.preventive,
    title: 'Monthly Transformer Inspection',
  );

  const techCompleted = WorkOrder(
    id: 101,
    status: WorkOrderStatus.techCompleted,
    type: WorkOrderType.preventive,
    title: 'Monthly Transformer Inspection',
  );

  setUp(() {
    mockRepo = MockWorkOrderRepository();
    when(() => mockRepo.fetchAudit(101)).thenAnswer(
      (_) async => const WorkOrderAudit(workOrderId: 101),
    );
    when(() => mockRepo.fetchWorkOrders()).thenAnswer((_) async => [newOrder]);
  });

  Widget wrap(
    Widget home, {
    AuthRole role = AuthRole.depotIncharge,
    List<String> permissions = const ['maintenance.view', 'maintenance.edit'],
  }) {
    return ProviderScope(
      overrides: [
        workOrderRepositoryProvider.overrideWithValue(mockRepo),
        authControllerProvider.overrideWith(
          () => FakeAuthenticatedController(
            fakeSession(role: role, permissions: permissions),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: home,
      ),
    );
  }

  group('Assign technician dialog', () {
    testWidgets('opens a technician dropdown for ASSIGNED', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => newOrder);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'NEW',
          allowed: [
            WorkOrderAction(
              targetStatus: 'ASSIGNED',
              label: 'Assigned',
              enabled: true,
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAssignableTechnicians()).thenAnswer(
        (_) async => const [
          Technician(id: 4, name: 'tech_ramesh'),
          Technician(id: 5, name: 'tech_anita'),
        ],
      );

      await tester.pumpWidget(wrap(const WorkOrderDetailScreen(workOrderId: 101)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_assigned')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign_technician_dropdown')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the users.view error instead of an empty dropdown', (tester) async {
      when(() => mockRepo.fetchWorkOrderById(101)).thenAnswer((_) async => newOrder);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          currentStatus: 'NEW',
          allowed: [
            WorkOrderAction(
              targetStatus: 'ASSIGNED',
              label: 'Assigned',
              enabled: true,
            ),
          ],
        ),
      );
      when(() => mockRepo.fetchAssignableTechnicians()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/users/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/users/'),
            statusCode: 403,
            data: const {'detail': 'You do not have permission to view users.'},
          ),
        ),
      );

      await tester.pumpWidget(wrap(const WorkOrderDetailScreen(workOrderId: 101)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_assigned')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assign_technician_error')), findsOneWidget);
      expect(find.textContaining('permission to view users'), findsOneWidget);
      expect(find.byKey(const Key('assign_technician_dropdown')), findsNothing);
    });
  });

  group('VerificationWorkspaceScreen', () {
    void stubDetail() {
      when(() => mockRepo.fetchWorkOrderById(101))
          .thenAnswer((_) async => techCompleted);
      when(() => mockRepo.fetchAllowedActions(101)).thenAnswer(
        (_) async => const WorkOrderActionSet(
          workOrderId: 101,
          allowed: [
            WorkOrderAction(
              targetStatus: 'REWORK_REQUIRED',
              label: 'Return to Technician',
              enabled: true,
              requiresReason: true,
            ),
          ],
        ),
      );
    }

    testWidgets('disables Verify when canVerify is false and shows banners', (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => const VerificationWorkspace(
          canVerify: false,
          disabledReasons: ['Checklist incomplete'],
          deficiencies: ['Oil leak'],
          deficiencyCount: 1,
          record: MaintenanceRecord(
            id: 55,
            workOrderId: 101,
            lines: [
              MaintenanceRecordLine(
                id: 1,
                itemName: 'TR-01',
                inspectionPoint: 'Oil level',
                recordedValue: 'Low',
                status: 'FAIL',
                observationAction: 'Top up required',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('verify_blocked_banner')), findsOneWidget);
      expect(find.text('Checklist incomplete'), findsOneWidget);
      expect(find.byKey(const Key('deficiency_banner')), findsOneWidget);
      expect(find.text('Oil leak'), findsOneWidget);
      expect(find.text('Oil level'), findsOneWidget);

      final verifyButton = tester.widget<ElevatedButton>(
        find.byKey(const Key('verify_confirm_button')),
      );
      expect(verifyButton.onPressed, isNull);
    });

    testWidgets('a Depot Incharge sees the checklist line photo evidence',
        (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => const VerificationWorkspace(
          canVerify: true,
          record: MaintenanceRecord(
            id: 55,
            workOrderId: 101,
            lines: [
              MaintenanceRecordLine(
                id: 1,
                itemName: 'EB Bunk',
                inspectionPoint: 'Check and clean the EB meter',
                recordedValue: 'OK',
                status: 'OK',
                attachments: [
                  LineAttachment(
                      id: 7,
                      kind: 'BEFORE',
                      url: 'https://backend.example/media/maintenance_line_evidence/b.jpg'),
                  LineAttachment(
                      id: 8,
                      kind: 'AFTER',
                      url: 'https://backend.example/media/maintenance_line_evidence/a.jpg'),
                  // Still in the technician's outbox: nothing to show yet.
                  LineAttachment(id: -1, kind: 'AFTER'),
                ],
              ),
              MaintenanceRecordLine(
                id: 2,
                itemName: 'EB Bunk',
                inspectionPoint: 'Earth resistance',
                status: 'OK',
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verify_line_photos_1')), findsOneWidget);
      expect(find.byKey(const Key('verify_line_photos_2')), findsNothing);
      expect(find.text('Before photos (1/5)'), findsOneWidget);
      expect(find.text('After photos (1/5)'), findsOneWidget);
      expect(find.byKey(const Key('preview_exec_photo_7')), findsOneWidget);
      expect(find.byKey(const Key('preview_exec_photo_8')), findsOneWidget);
      // Read-only for the supervisor.
      expect(find.byKey(const Key('delete_exec_photo_7')), findsNothing);
      expect(find.byKey(const Key('add_before_photo_button')), findsNothing);
    });

    testWidgets(
        'a Depot Incharge sees a PM record\'s proof-of-execution photo',
        (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => VerificationWorkspace.fromJson({
          'can_verify': true,
          'work_order': {'status': 'TECH_COMPLETED', 'execution_mode': 'CHECKLIST'},
          'record': {
            'id': 55,
            'proof_of_execution':
                'https://backend.example/media/maintenance_proofs/proof.jpg',
            'lines': [
              {
                'id': 1,
                'item_name': 'EB Bunk',
                'inspection_point': 'Check and clean the EB meter',
                'status': 'OK',
                'checked_out': true,
              },
            ],
          },
        }),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verify_proof_of_execution')), findsOneWidget);
      expect(find.byKey(const Key('preview_proof_of_execution')), findsOneWidget);
    });

    testWidgets(
        'a Depot Incharge sees the inspector\'s and the technician\'s inspection photos',
        (tester) async {
      stubDetail();
      const media = 'https://backend.example/media';
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => VerificationWorkspace.fromJson({
          'can_verify': true,
          'work_order': {
            'status': 'TECH_COMPLETED',
            'execution_mode': 'INSPECTION',
            // Shaped like build_pointwise_inspection_execution_data.
            'inspection_execution': {
              'is_pointwise': true,
              'inspection_details': {
                'inspection_number': 'INSP-1',
                'general_evidence_photos': [
                  {'id': 31, 'image': '$media/inspection_evidence_photos/g.jpg', 'caption': 'Yard view'},
                ],
              },
              'points': [
                {
                  'point_job_work_id': 5,
                  'point_number': 1,
                  'observation': 'Loose terminal',
                  'execution': {
                    'id': 9,
                    'initial_findings': 'Terminal loose',
                    'photos': [
                      {'id': 41, 'photo_type': 'AFTER', 'image': '$media/inspection_execution_photos/a.jpg'},
                    ],
                    'inspection_evidence_photos': [
                      {'id': 32, 'image': '$media/inspection_evidence_photos/p.jpg'},
                    ],
                  },
                },
              ],
            },
          },
        }),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verify_inspection_general_evidence')),
          findsOneWidget);
      expect(find.byKey(const Key('inspector_photo_31')), findsOneWidget);
      expect(find.byKey(const Key('verify_point_inspector_photos_5')),
          findsOneWidget);
      expect(find.byKey(const Key('inspector_photo_32')), findsOneWidget);
      expect(find.text('From the inspection (1)'), findsOneWidget);
      // The technician's own After photo, read-only.
      expect(find.byKey(const Key('preview_exec_photo_41')), findsOneWidget);
      expect(find.byKey(const Key('delete_exec_photo_41')), findsNothing);
    });

    testWidgets(
        'a Depot Incharge sees each deficiency\'s rectification photos',
        (tester) async {
      stubDetail();
      const media = 'https://backend.example/media/rectification_evidence';
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => VerificationWorkspace.fromJson({
          'can_verify': true,
          'work_order': {
            'status': 'TECH_COMPLETED',
            'execution_mode': 'RECTIFICATION',
          },
          // Shaped like RectificationService.payload / _item_dict.
          'rectification': {
            'final_remarks': 'All rectified',
            'items': [
              {
                'id': 3,
                'deficiency_id': 77,
                'is_active': true,
                'asset': 'EB Bunk',
                'checkpoint': 'Earth pit',
                'finding': 'Earth pit cover missing',
                'severity': 'Medium',
                'action_taken': 'New cover fixed',
                'outcome': 'RECTIFIED',
                'photos': [
                  {'id': 61, 'kind': 'BEFORE', 'url': '$media/b.jpg', 'image': '$media/b.jpg', 'locked': true},
                  {'id': 62, 'kind': 'AFTER', 'url': '$media/a.jpg', 'image': '$media/a.jpg', 'locked': true},
                ],
                // The checklist photo the deficiency was raised with.
                'source_photos': [
                  {'id': 71, 'kind': 'BEFORE', 'url': 'https://backend.example/media/maintenance_line_evidence/f.jpg', 'locked': true, 'source': 'CHECKLIST'},
                ],
              },
              {
                // Removed from the Job Work: not shown.
                'id': 4,
                'is_active': false,
                'asset': 'Old item',
                'photos': [
                  {'id': 63, 'kind': 'BEFORE', 'url': '$media/x.jpg'},
                ],
              },
            ],
          },
        }),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verify_kind_rectification')), findsOneWidget);
      expect(find.text('Earth pit cover missing'), findsOneWidget);
      expect(find.byKey(const Key('preview_exec_photo_61')), findsOneWidget);
      expect(find.byKey(const Key('preview_exec_photo_62')), findsOneWidget);
      expect(find.byKey(const Key('preview_exec_photo_63')), findsNothing);
      expect(find.byKey(const Key('delete_exec_photo_61')), findsNothing);
      expect(find.byKey(const Key('verify_rect_source_photos_3')), findsOneWidget);
      expect(find.byKey(const Key('inspector_photo_71')), findsOneWidget);
      expect(find.text('Original evidence (checklist) (1)'), findsOneWidget);
    });

    testWidgets('a legacy inspection Job Work shows its execution photos',
        (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => VerificationWorkspace.fromJson({
          'can_verify': true,
          'work_order': {
            'execution_mode': 'INSPECTION',
            'inspection_execution': {
              'is_pointwise': false,
              'points': [],
              'photos': [
                {'id': 51, 'photo_type': 'BEFORE', 'image': 'https://backend.example/media/inspection_execution_photos/b.jpg'},
              ],
              'inspection_details': {},
            },
          },
        }),
      );

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('preview_exec_photo_51')), findsOneWidget);
      expect(find.text('No points recorded.'), findsNothing);
    });

    testWidgets('Return to Technician still uses generic REWORK_REQUIRED', (tester) async {
      stubDetail();
      when(() => mockRepo.fetchVerificationWorkspace(101)).thenAnswer(
        (_) async => const VerificationWorkspace(canVerify: true),
      );
      when(
        () => mockRepo.transitionStatus(
          101,
          status: 'REWORK_REQUIRED',
          remarks: any(named: 'remarks'),
        ),
      ).thenAnswer((_) async => techCompleted.copyWith(status: WorkOrderStatus.reworkRequired));

      await tester.pumpWidget(
        wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(VerificationWorkspaceScreen));
      await ProviderScope.containerOf(context)
          .read(workOrderDetailControllerProvider(101).notifier)
          .loadDetail();
      await tester.pump();

      await tester.tap(find.byKey(const Key('return_to_technician_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('transition_remarks_field')),
        'Rework the oil top-up',
      );
      await tester.tap(find.byKey(const Key('transition_confirm_button')));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.transitionStatus(
          101,
          status: 'REWORK_REQUIRED',
          remarks: 'Rework the oil top-up',
        ),
      ).called(1);
      verifyNever(() => mockRepo.verifyWorkOrder(any(), remarks: any(named: 'remarks')));
    });

    group('severity, groups and modes', () {
      const severities = [
        DeficiencySeverityOption(id: 1, code: 'MINOR', label: 'Minor'),
        DeficiencySeverityOption(id: 2, code: 'MAJOR', label: 'Major'),
      ];

      VerificationWorkspace workspaceWith({
        String mode = 'CHECKLIST',
        String status = 'TECH_COMPLETED',
        Map<String, dynamic>? complaint,
      }) {
        return VerificationWorkspace.fromJson({
          'can_verify': true,
          'work_order': {'status': status, 'execution_mode': mode},
          'record': {'id': 55, 'work_order': 101, 'lines': []},
          'deficiency_rows': [
            {
              'id': 7,
              'asset': 'TR-01',
              'checkpoint': 'Oil level',
              'finding': 'Low oil',
              'severity': 'Minor',
              'deficiency_id': 12,
              'deficiency_version': 3,
              'severity_id': 1,
            },
          ],
          'remark_deficiency_rows': [],
          'asset_groups': [
            {
              'key': 'g1',
              'asset_category_id': 4,
              'asset_name': 'TR-01',
              'display_name': 'Transformer TR-01',
              'checked_out': true,
              'checkout_source': 'SUPERVISOR',
            },
          ],
          'complaint_execution': complaint,
        });
      }

      void arrange(WidgetTester tester, VerificationWorkspace ws) {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        stubDetail();
        when(() => mockRepo.fetchVerificationWorkspace(101))
            .thenAnswer((_) async => ws);
        when(() => mockRepo.getDeficiencySeverities())
            .thenAnswer((_) async => severities);
      }

      testWidgets('shows severity dropdown for DEPOT_INCHARGE', (tester) async {
        arrange(tester, workspaceWith());
        await tester.pumpWidget(
          wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('severity_dropdown_7')), findsOneWidget);
      });

      testWidgets('shows severity text for DIV_ADMIN', (tester) async {
        arrange(tester, workspaceWith());
        await tester.pumpWidget(
          wrap(
            const VerificationWorkspaceScreen(workOrderId: 101),
            role: AuthRole.divAdmin,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('severity_dropdown_7')), findsNothing);
        expect(find.byKey(const Key('severity_text_7')), findsOneWidget);
      });

      Future<void> pickMajor(WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('severity_dropdown_7')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Major').last);
        await tester.pumpAndSettle();
      }

      testWidgets('changing severity sends expectedVersion', (tester) async {
        arrange(tester, workspaceWith());
        when(
          () => mockRepo.updateDeficiencySeverity(
            12,
            severityId: 2,
            expectedVersion: 3,
          ),
        ).thenAnswer(
          (_) async => const DeficiencySeverityUpdate(id: 12, severityId: 2),
        );
        await tester.pumpWidget(
          wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
        );
        await tester.pumpAndSettle();

        await pickMajor(tester);

        verify(
          () => mockRepo.updateDeficiencySeverity(
            12,
            severityId: 2,
            expectedVersion: 3,
          ),
        ).called(1);
      });

      testWidgets('a 409 on severity shows the conflict message', (tester) async {
        arrange(tester, workspaceWith());
        when(
          () => mockRepo.updateDeficiencySeverity(
            12,
            severityId: 2,
            expectedVersion: 3,
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/deficiencies/12/'),
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: RequestOptions(path: '/api/v1/deficiencies/12/'),
              statusCode: 409,
              data: const {'detail': 'stale'},
            ),
          ),
        );
        await tester.pumpWidget(
          wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
        );
        await tester.pumpAndSettle();

        await pickMajor(tester);

        expect(
          find.text(
            'This deficiency was updated by someone else. The latest state has been reloaded.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('Un-check needs group_uncheckout and TECH_COMPLETED', (tester) async {
        arrange(tester, workspaceWith());
        await tester.pumpWidget(
          wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('uncheck_group_g1')), findsNothing);

        arrange(tester, workspaceWith(status: 'VERIFIED'));
        await tester.pumpWidget(
          wrap(
            const VerificationWorkspaceScreen(workOrderId: 101),
            permissions: const [
              'maintenance.view',
              'maintenance.edit',
              'maintenance.group_uncheckout',
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('uncheck_group_g1')), findsNothing);
      });

      testWidgets('Un-check asks for a reason then calls setGroupInclusion', (tester) async {
        arrange(tester, workspaceWith());
        when(
          () => mockRepo.setGroupInclusion(
            55,
            assetCategoryId: 4,
            assetName: 'TR-01',
            included: false,
            reason: 'Wrong asset',
          ),
        ).thenAnswer(
          (_) async => const GroupInclusionResult(returnedToTechnician: true),
        );
        await tester.pumpWidget(
          wrap(
            const VerificationWorkspaceScreen(workOrderId: 101),
            permissions: const [
              'maintenance.view',
              'maintenance.edit',
              'maintenance.group_uncheckout',
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('uncheck_group_g1')));
        await tester.pumpAndSettle();
        expect(find.text('Reason for un-checking "Transformer TR-01"'),
            findsOneWidget);

        // Reason is required.
        await tester.tap(find.byKey(const Key('uncheck_confirm_button')));
        await tester.pumpAndSettle();
        verifyNever(
          () => mockRepo.setGroupInclusion(
            any(),
            assetCategoryId: any(named: 'assetCategoryId'),
            assetName: any(named: 'assetName'),
            included: any(named: 'included'),
            reason: any(named: 'reason'),
          ),
        );

        await tester.enterText(
            find.byKey(const Key('uncheck_reason_field')), 'Wrong asset');
        await tester.tap(find.byKey(const Key('uncheck_confirm_button')));
        await tester.pumpAndSettle();

        verify(
          () => mockRepo.setGroupInclusion(
            55,
            assetCategoryId: 4,
            assetName: 'TR-01',
            included: false,
            reason: 'Wrong asset',
          ),
        ).called(1);
      });

      testWidgets('COMPLAINT mode shows findings and hides Checklist', (tester) async {
        arrange(
          tester,
          workspaceWith(
            mode: 'COMPLAINT',
            complaint: const {
              'id': 9,
              'initial_findings': 'Loud humming noise',
              'action_taken': 'Tightened bolts',
              'final_remarks': 'Resolved',
            },
          ),
        );
        await tester.pumpWidget(
          wrap(const VerificationWorkspaceScreen(workOrderId: 101)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Loud humming noise'), findsOneWidget);
        expect(find.text('Tightened bolts'), findsOneWidget);
        expect(find.text('Checklist'), findsNothing);
      });
    });
  });
}
