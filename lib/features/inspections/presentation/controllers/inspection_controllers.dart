import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_api_service.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_effective_status.dart';

final inspectionRepositoryProvider = Provider<IInspectionRepository>((ref) {
  final api = ref.watch(inspectionApiServiceProvider);
  return InspectionRepository(api);
});

sealed class InspectionListState extends Equatable {
  const InspectionListState();
  @override
  List<Object?> get props => [];
}

class InspectionListInitial extends InspectionListState {
  const InspectionListInitial();
}

class InspectionListLoading extends InspectionListState {
  const InspectionListLoading();
}

class InspectionListLoaded extends InspectionListState {
  const InspectionListLoaded({
    required this.inspections,
    this.selectedStatus,
    this.selectedEffectiveStatus,
    this.searchQuery = '',
    this.dateFrom,
    this.dateTo,
    this.orgScope = OrgScopeSelection.empty,
  });

  final List<Inspection> inspections;

  /// Record-status filter (server-side narrowing, mirrors web `status` param).
  final InspectionStatus? selectedStatus;

  /// Effective-status filter (client-side, computed — backend does not store
  /// PARTIALLY_CONVERTED/ASSIGNED/... so web filters these client-side too).
  final EffectiveInspectionStatus? selectedEffectiveStatus;
  final String searchQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final OrgScopeSelection orgScope;

  List<Inspection> get filteredInspections {
    return inspections.where((i) {
      if (selectedStatus != null && i.status != selectedStatus) return false;
      if (selectedEffectiveStatus != null &&
          i.effectiveStatus != selectedEffectiveStatus) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        bool has(String? v) => v != null && v.toLowerCase().contains(q);
        final matches = has(i.title) ||
            has(i.reference) ||
            has(i.inspectionNumber) ||
            has(i.id.toString()) ||
            has(i.notes) ||
            has(i.locationLabel) ||
            has(i.createdByName) ||
            has(i.assetUniqueId);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  InspectionListLoaded copyWith({
    List<Inspection>? inspections,
    InspectionStatus? selectedStatus,
    bool clearStatus = false,
    EffectiveInspectionStatus? selectedEffectiveStatus,
    bool clearEffectiveStatus = false,
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateRange = false,
    OrgScopeSelection? orgScope,
  }) {
    return InspectionListLoaded(
      inspections: inspections ?? this.inspections,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      selectedEffectiveStatus: clearEffectiveStatus
          ? null
          : (selectedEffectiveStatus ?? this.selectedEffectiveStatus),
      searchQuery: searchQuery ?? this.searchQuery,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      orgScope: orgScope ?? this.orgScope,
    );
  }

  @override
  List<Object?> get props => [
        inspections,
        selectedStatus,
        selectedEffectiveStatus,
        searchQuery,
        dateFrom,
        dateTo,
        orgScope
      ];
}

class InspectionListError extends InspectionListState {
  const InspectionListError(this.message, {this.previousLoaded});
  final String message;

  /// Carries the last successfully loaded filters through the error so a
  /// retry/filter change issued from here doesn't silently reset them.
  final InspectionListLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}

final inspectionListControllerProvider =
    NotifierProvider<InspectionListController, InspectionListState>(InspectionListController.new);

class InspectionListController extends Notifier<InspectionListState> {
  @override
  InspectionListState build() => const InspectionListInitial();

  IInspectionRepository get _repository => ref.read(inspectionRepositoryProvider);

  /// The last successfully loaded filters, whether the current state is
  /// still that loaded state or an error that carried them forward.
  InspectionListLoaded? _resolvePrevious() {
    final s = state;
    if (s is InspectionListLoaded) return s;
    if (s is InspectionListError) return s.previousLoaded;
    return null;
  }

  /// Guards against an older, slower response overwriting a newer filter's.
  int _requestSeq = 0;

  Future<void> fetchInspections({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    if (!forceRefresh && previous != null) return;
    // Stale-while-refresh: keep rows visible during a pull-to-refresh.
    if (previous == null) state = const InspectionListLoading();
    await _load(
      base: previous,
      dateFrom: previous?.dateFrom,
      dateTo: previous?.dateTo,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      dateFrom: from,
      dateTo: to,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  /// Server-side Zone/Division/Depot filter (Inspections has no
  /// station-level filter server-side — see InspectionViewSet.get_queryset —
  /// so this bar is used with `enableStation: false`).
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      dateFrom: previous?.dateFrom,
      dateTo: previous?.dateTo,
      scope: scope,
    );
  }

  /// Clears status, search and date range; keeps the org scope.
  Future<void> clearFilters() async {
    final previous = _resolvePrevious();
    await _load(
      base: previous == null
          ? null
          : InspectionListLoaded(
              inspections: previous.inspections,
              orgScope: previous.orgScope,
            ),
      dateFrom: null,
      dateTo: null,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  /// Sends only record-status values server-side. Effective-only values
  /// (PARTIALLY_CONVERTED, ASSIGNED, ...) are computed, not stored, so web
  /// leaves them for client-side filtering — same here.
  static String? _recordStatusParam(InspectionStatus? status) {
    if (status == null || status == InspectionStatus.unknown) return null;
    return status.code;
  }

  Future<void> _load({
    required InspectionListLoaded? base,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required OrgScopeSelection scope,
  }) async {
    final seq = ++_requestSeq;
    try {
      final inspections = await _repository.fetchInspections(
        status: _recordStatusParam(base?.selectedStatus),
        dateFrom: formatApiDate(dateFrom),
        dateTo: formatApiDate(dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      if (seq != _requestSeq) return;
      state = InspectionListLoaded(
        inspections: inspections,
        selectedStatus: base?.selectedStatus,
        selectedEffectiveStatus: base?.selectedEffectiveStatus,
        searchQuery: base?.searchQuery ?? '',
        dateFrom: dateFrom,
        dateTo: dateTo,
        orgScope: scope,
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      state = InspectionListError(userFacingError(e), previousLoaded: base);
    }
  }

  /// M12: client-side filter setters also work from the Error state —
  /// the carried-forward [previousLoaded] becomes the filter target.
  InspectionListLoaded? _filterTarget() {
    final s = state;
    if (s is InspectionListLoaded) return s;
    if (s is InspectionListError) return s.previousLoaded;
    return null;
  }

  void setStatusFilter(InspectionStatus? status) {
    final target = _filterTarget();
    if (target == null) return;
    final previous = _resolvePrevious();
    state = target.copyWith(selectedStatus: status, clearStatus: status == null);
    // Record filter narrows server-side — reload to match web register.
    if (previous?.selectedStatus != status) {
      unawaited(_load(
        base: state is InspectionListLoaded
            ? state as InspectionListLoaded
            : previous,
        dateFrom: previous?.dateFrom,
        dateTo: previous?.dateTo,
        scope: previous?.orgScope ?? OrgScopeSelection.empty,
      ));
    }
  }

  void setEffectiveStatusFilter(EffectiveInspectionStatus? status) {
    final loaded = _filterTarget();
    if (loaded == null) return;
    state = loaded.copyWith(
        selectedEffectiveStatus: status,
        clearEffectiveStatus: status == null);
  }

  void setSearchQuery(String query) {
    final loaded = _filterTarget();
    if (loaded == null) return;
    state = loaded.copyWith(searchQuery: query.trim());
  }
}
