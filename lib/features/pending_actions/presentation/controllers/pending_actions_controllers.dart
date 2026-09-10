import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_api_service.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/maintenance_schedules/data/maintenance_schedule_api_service.dart';
import 'package:gssms_mobile/features/maintenance_schedules/data/maintenance_schedule_repository.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

final deficiencyRepositoryProvider = Provider<IDeficiencyRepository>((ref) {
  final api = ref.watch(deficiencyApiServiceProvider);
  return DeficiencyRepository(api);
});

final maintenanceScheduleRepositoryProvider =
    Provider<IMaintenanceScheduleRepository>((ref) {
  final api = ref.watch(maintenanceScheduleApiServiceProvider);
  return MaintenanceScheduleRepository(api);
});

/// Which of the four Pending Actions tabs a batch-convert or reload targets.
enum PendingActionTab { schedules, complaints, inspections, deficiencies }

class PendingActionsState extends Equatable {
  const PendingActionsState({
    this.loading = true,
    this.error,
    this.schedules = const [],
    this.complaints = const [],
    this.inspections = const [],
    this.deficiencies = const [],
    this.selectedScheduleIds = const {},
    this.selectedComplaintIds = const {},
    this.selectedInspectionIds = const {},
    this.orgScope = OrgScopeSelection.empty,
    this.converting = false,
    this.actionMessage,
  });

  final bool loading;
  final String? error;
  final List<MaintenanceSchedule> schedules;
  final List<Complaint> complaints;
  final List<Inspection> inspections;
  final List<Deficiency> deficiencies;
  final Set<int> selectedScheduleIds;
  final Set<int> selectedComplaintIds;
  final Set<int> selectedInspectionIds;
  final OrgScopeSelection orgScope;
  final bool converting;
  final String? actionMessage;

  PendingActionsState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    List<MaintenanceSchedule>? schedules,
    List<Complaint>? complaints,
    List<Inspection>? inspections,
    List<Deficiency>? deficiencies,
    Set<int>? selectedScheduleIds,
    Set<int>? selectedComplaintIds,
    Set<int>? selectedInspectionIds,
    OrgScopeSelection? orgScope,
    bool? converting,
    String? actionMessage,
    bool clearActionMessage = false,
  }) {
    return PendingActionsState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      schedules: schedules ?? this.schedules,
      complaints: complaints ?? this.complaints,
      inspections: inspections ?? this.inspections,
      deficiencies: deficiencies ?? this.deficiencies,
      selectedScheduleIds: selectedScheduleIds ?? this.selectedScheduleIds,
      selectedComplaintIds: selectedComplaintIds ?? this.selectedComplaintIds,
      selectedInspectionIds:
          selectedInspectionIds ?? this.selectedInspectionIds,
      orgScope: orgScope ?? this.orgScope,
      converting: converting ?? this.converting,
      actionMessage:
          clearActionMessage ? null : (actionMessage ?? this.actionMessage),
    );
  }

  @override
  List<Object?> get props => [
        loading,
        error,
        schedules,
        complaints,
        inspections,
        deficiencies,
        selectedScheduleIds,
        selectedComplaintIds,
        selectedInspectionIds,
        orgScope,
        converting,
        actionMessage,
      ];
}

final pendingActionsControllerProvider =
    NotifierProvider<PendingActionsController, PendingActionsState>(() {
  return PendingActionsController();
});

/// Backs the four Pending Actions tabs (Scheduled Tasks / Complaints /
/// Inspection Notes / Deficiencies) — web-parity mirror of DashboardView.jsx
/// `loadPendingItems`: four independent sources loaded together, each with
/// its own selection set and (for the first three) a batch "create Job
/// Works from selected" action hitting its own all-or-nothing endpoint.
class PendingActionsController extends Notifier<PendingActionsState> {
  @override
  PendingActionsState build() => const PendingActionsState();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    final scope = state.orgScope;
    try {
      final results = await Future.wait([
        ref.read(maintenanceScheduleRepositoryProvider).fetchPendingSchedules(
              zoneId: scope.zoneId,
              divisionId: scope.divisionId,
              depotId: scope.depotId,
            ),
        ref.read(complaintRepositoryProvider).fetchComplaints(
              status: 'OPEN',
              zoneId: scope.zoneId,
              divisionId: scope.divisionId,
              depotId: scope.depotId,
            ),
        ref.read(inspectionRepositoryProvider).fetchInspections(
              pendingConversion: true,
              zoneId: scope.zoneId,
              divisionId: scope.divisionId,
              depotId: scope.depotId,
            ),
        ref.read(deficiencyRepositoryProvider).fetchPendingDeficiencies(
              zoneId: scope.zoneId,
              divisionId: scope.divisionId,
              depotId: scope.depotId,
            ),
      ]);
      state = state.copyWith(
        loading: false,
        schedules: results[0] as List<MaintenanceSchedule>,
        complaints: results[1] as List<Complaint>,
        inspections: results[2] as List<Inspection>,
        deficiencies: results[3] as List<Deficiency>,
        // A fresh load invalidates any selection made against the old rows.
        selectedScheduleIds: const {},
        selectedComplaintIds: const {},
        selectedInspectionIds: const {},
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Failed to load pending actions: ${workOrderReadableError(e)}',
      );
    }
  }

  Future<void> setOrgScope(OrgScopeSelection scope) async {
    state = state.copyWith(orgScope: scope);
    await load();
  }

  void toggleSelection(PendingActionTab tab, int id) {
    Set<int> toggle(Set<int> current) {
      final next = Set<int>.from(current);
      if (!next.remove(id)) next.add(id);
      return next;
    }

    switch (tab) {
      case PendingActionTab.schedules:
        state = state.copyWith(
            selectedScheduleIds: toggle(state.selectedScheduleIds));
        break;
      case PendingActionTab.complaints:
        state = state.copyWith(
            selectedComplaintIds: toggle(state.selectedComplaintIds));
        break;
      case PendingActionTab.inspections:
        state = state.copyWith(
            selectedInspectionIds: toggle(state.selectedInspectionIds));
        break;
      case PendingActionTab.deficiencies:
        break; // No selection concept on this tab — view-only.
    }
  }

  /// Converts the current selection for [tab] into Job Work(s) via the
  /// matching all-or-nothing batch endpoint, then reloads so converted rows
  /// (now excluded server-side by each `pending`/`OPEN`/`pending_conversion`
  /// filter) drop out of the list on their own.
  Future<bool> convertSelected(PendingActionTab tab) async {
    final ids = switch (tab) {
      PendingActionTab.schedules => state.selectedScheduleIds,
      PendingActionTab.complaints => state.selectedComplaintIds,
      PendingActionTab.inspections => state.selectedInspectionIds,
      PendingActionTab.deficiencies => const <int>{},
    };
    if (ids.isEmpty) return false;

    state = state.copyWith(converting: true, clearActionMessage: true);
    try {
      final idList = ids.toList();
      final result = switch (tab) {
        PendingActionTab.schedules => await ref
            .read(maintenanceScheduleRepositoryProvider)
            .createBatchWorkOrders(idList),
        PendingActionTab.complaints => await ref
            .read(workOrderRepositoryProvider)
            .createWorkOrdersFromComplaints(idList),
        PendingActionTab.inspections => await ref
            .read(workOrderRepositoryProvider)
            .createWorkOrdersFromInspections(idList),
        PendingActionTab.deficiencies => null,
      };
      state = state.copyWith(
        converting: false,
        actionMessage: result != null
            ? '${result.count} Job Work${result.count == 1 ? '' : 's'} created.'
            : null,
      );
      await load();
      return true;
    } catch (e) {
      state = state.copyWith(
        converting: false,
        actionMessage: 'Failed to convert: ${workOrderReadableError(e)}',
      );
      return false;
    }
  }
}
