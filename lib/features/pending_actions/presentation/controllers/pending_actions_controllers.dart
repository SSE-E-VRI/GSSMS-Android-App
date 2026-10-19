import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_api_service.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';

export 'package:gssms_mobile/features/deficiencies/domain/deficiency_bucket.dart'
    show PendingBucket, deficiencyBucket;
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_effective_status.dart';
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

/// Sub-filter chips under the Pending Actions tabs (web DashboardView.jsx
/// `pendingSubFilter`).
enum PendingSubFilter {
  all('All'),
  needsAction('Needs action'),
  inProgress('In progress'),
  awaitingClosure('Awaiting closure');

  const PendingSubFilter(this.label);
  final String label;
}

/// Lifecycle bucket a pending row falls into (web DashboardView.jsx:972-1041).
enum PendingBucket { needsAction, inProgress, awaitingClosure }

bool _woStatusIs(String? status, String code) =>
    status != null && status.trim().toUpperCase() == code;

bool _woStatusIn(String? status, Set<String> codes) =>
    status != null && codes.contains(status.trim().toUpperCase());

/// Schedules: no Job Work yet -> needs action; Job Work verified -> awaiting
/// closure; otherwise a live Job Work is in progress (null once closed).
PendingBucket? scheduleBucket(MaintenanceSchedule s) {
  if (s.workOrderId == null) return PendingBucket.needsAction;
  if (_woStatusIs(s.workOrderStatus, 'VERIFIED')) {
    return PendingBucket.awaitingClosure;
  }
  // Web DashboardView.jsx:977: keyed on the Job Work status, not the schedule's.
  if (!_woStatusIn(s.workOrderStatus, const {'CLOSED', 'VERIFIED'})) {
    return PendingBucket.inProgress;
  }
  return null;
}

/// Complaints: unconverted open -> needs action; converted with a live Job
/// Work -> in progress; converted + VERIFIED Job Work -> awaiting closure.
PendingBucket? complaintBucket(Complaint c) {
  if (!c.isConverted) {
    return c.status != ComplaintStatus.closed ? PendingBucket.needsAction : null;
  }
  if (_woStatusIs(c.workOrderStatus, 'VERIFIED')) {
    return PendingBucket.awaitingClosure;
  }
  if (!_woStatusIn(c.workOrderStatus, const {'VERIFIED', 'CLOSED'})) {
    return PendingBucket.inProgress;
  }
  return null;
}

/// Effective status code of an inspection: the computed aggregate unless the
/// backend omitted it, then the persisted record status.
String inspectionEffectiveCode(Inspection i) =>
    i.effectiveStatus == EffectiveInspectionStatus.unknown
        ? i.status.code
        : i.effectiveStatus.code;

/// Closed inspections are dropped from every sub-filter, including "All".
bool inspectionIsActive(Inspection i) => inspectionEffectiveCode(i) != 'CLOSED';

/// Bucket for an *active* inspection (see [inspectionIsActive]).
PendingBucket inspectionBucket(Inspection i) {
  final code = inspectionEffectiveCode(i);
  if (i.unassignedPointsCount > 0 ||
      code == 'REPLACEMENT_PENDING_APPROVAL' ||
      code == 'REPLACEMENT_APPROVED' ||
      (i.pointsCount == 0 && !i.isConverted)) {
    return PendingBucket.needsAction;
  }
  if (i.pointsCount == 0 && _woStatusIs(i.workOrderStatus, 'VERIFIED')) {
    return PendingBucket.awaitingClosure;
  }
  return PendingBucket.inProgress;
}

/// Web `utils/deficiencyBucket.js`.
PendingBucket deficiencyBucket(Deficiency d) {
  if (d.status == DeficiencyStatus.resolved) return PendingBucket.awaitingClosure;
  if (d.hasActiveRemedial || d.status == DeficiencyStatus.inProgress) {
    return PendingBucket.inProgress;
  }
  return PendingBucket.needsAction;
}

bool _matchesSub(PendingSubFilter f, PendingBucket? b) => switch (f) {
      PendingSubFilter.all => true,
      PendingSubFilter.needsAction => b == PendingBucket.needsAction,
      PendingSubFilter.inProgress => b == PendingBucket.inProgress,
      PendingSubFilter.awaitingClosure => b == PendingBucket.awaitingClosure,
    };

/// Applies [f] to [schedules]. Breakdown-backing rows are excluded so the
/// Schedules tab agrees with the dashboard's scheduled-task count.
List<MaintenanceSchedule> filterSchedules(
        List<MaintenanceSchedule> schedules, PendingSubFilter f) =>
    schedules
        .where((s) => !s.isBreakdown && _matchesSub(f, scheduleBucket(s)))
        .toList();

List<Complaint> filterComplaints(
        List<Complaint> complaints, PendingSubFilter f) =>
    complaints.where((c) => _matchesSub(f, complaintBucket(c))).toList();

List<Inspection> filterInspections(
        List<Inspection> inspections, PendingSubFilter f) =>
    inspections
        .where((i) => inspectionIsActive(i) && _matchesSub(f, inspectionBucket(i)))
        .toList();

List<Deficiency> filterDeficiencies(
        List<Deficiency> deficiencies, PendingSubFilter f) =>
    deficiencies.where((d) => _matchesSub(f, deficiencyBucket(d))).toList();

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
    this.selectedDeficiencyIds = const {},
    this.orgScope = OrgScopeSelection.empty,
    this.converting = false,
    this.actionMessage,
    this.subFilter = PendingSubFilter.all,
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
  final Set<int> selectedDeficiencyIds;
  final OrgScopeSelection orgScope;
  final bool converting;
  final String? actionMessage;
  final PendingSubFilter subFilter;

  List<MaintenanceSchedule> get filteredSchedules =>
      filterSchedules(schedules, subFilter);
  List<Complaint> get filteredComplaints =>
      filterComplaints(complaints, subFilter);
  List<Inspection> get filteredInspections =>
      filterInspections(inspections, subFilter);
  List<Deficiency> get filteredDeficiencies =>
      filterDeficiencies(deficiencies, subFilter);

  /// Row counts per sub-filter for [tab], for the chips and tab badges.
  Map<PendingSubFilter, int> countsFor(PendingActionTab tab) {
    int count(PendingSubFilter f) => switch (tab) {
          PendingActionTab.schedules => filterSchedules(schedules, f).length,
          PendingActionTab.complaints => filterComplaints(complaints, f).length,
          PendingActionTab.inspections =>
            filterInspections(inspections, f).length,
          PendingActionTab.deficiencies =>
            filterDeficiencies(deficiencies, f).length,
        };
    return {for (final f in PendingSubFilter.values) f: count(f)};
  }

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
    Set<int>? selectedDeficiencyIds,
    OrgScopeSelection? orgScope,
    bool? converting,
    String? actionMessage,
    bool clearActionMessage = false,
    PendingSubFilter? subFilter,
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
      selectedDeficiencyIds:
          selectedDeficiencyIds ?? this.selectedDeficiencyIds,
      orgScope: orgScope ?? this.orgScope,
      converting: converting ?? this.converting,
      actionMessage:
          clearActionMessage ? null : (actionMessage ?? this.actionMessage),
      subFilter: subFilter ?? this.subFilter,
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
        selectedDeficiencyIds,
        orgScope,
        converting,
        actionMessage,
        subFilter,
      ];
}

final pendingActionsControllerProvider =
    NotifierProvider<PendingActionsController, PendingActionsState>(() {
  return PendingActionsController();
});

/// Backs the four Pending Actions tabs (Scheduled Tasks / Breakdowns /
/// Inspection Notes / Deficiencies) — web-parity mirror of DashboardView.jsx
/// `loadPendingItems`: four independent sources loaded together, each with
/// its own selection set and a batch "create Job Works from selected" action
/// hitting its own all-or-nothing endpoint (rectification for deficiencies).
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
              excludeStatus: 'CLOSED',
              zoneId: scope.zoneId,
              divisionId: scope.divisionId,
              depotId: scope.depotId,
            ),
        ref.read(inspectionRepositoryProvider).fetchInspections(
              excludeStatus: 'CLOSED',
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
        selectedDeficiencyIds: const {},
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'Failed to load pending actions: ${workOrderReadableError(e)}',
      );
    }
  }

  /// Switches the sub-filter; row sets change, so selections are cleared.
  void setSubFilter(PendingSubFilter f) {
    state = state.copyWith(
      subFilter: f,
      selectedScheduleIds: const {},
      selectedComplaintIds: const {},
      selectedInspectionIds: const {},
      selectedDeficiencyIds: const {},
    );
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
        state = state.copyWith(
            selectedDeficiencyIds: toggle(state.selectedDeficiencyIds));
    }
  }

  /// Converts the current selection for [tab] into Job Work(s) via the
  /// matching all-or-nothing batch endpoint, then reloads so converted rows
  /// (now excluded server-side by each `pending`/`OPEN`/`pending_conversion`
  /// filter) drop out of the list on their own. Deficiencies create grouped
  /// rectification Job Works (one per location) unless [onePerDeficiency]
  /// asks for one per deficiency — mirroring web's Deficiencies tab.
  Future<bool> convertSelected(
    PendingActionTab tab, {
    bool onePerDeficiency = false,
  }) async {
    final ids = switch (tab) {
      PendingActionTab.schedules => state.selectedScheduleIds,
      PendingActionTab.complaints => state.selectedComplaintIds,
      PendingActionTab.inspections => state.selectedInspectionIds,
      PendingActionTab.deficiencies => state.selectedDeficiencyIds,
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
        PendingActionTab.deficiencies => await ref
            .read(workOrderRepositoryProvider)
            .createRectification(idList, onePerDeficiency: onePerDeficiency),
      };
      state = state.copyWith(
        converting: false,
        actionMessage:
            '${result.count} Job Work${result.count == 1 ? '' : 's'} created.',
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
