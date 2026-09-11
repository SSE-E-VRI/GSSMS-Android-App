import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_api_service.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';

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
    this.searchQuery = '',
    this.dateFrom,
    this.dateTo,
    this.orgScope = OrgScopeSelection.empty,
  });

  final List<Inspection> inspections;
  final InspectionStatus? selectedStatus;
  final String searchQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final OrgScopeSelection orgScope;

  List<Inspection> get filteredInspections {
    return inspections.where((i) {
      if (selectedStatus != null && i.status != selectedStatus) return false;
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        bool has(String? v) => v != null && v.toLowerCase().contains(q);
        final matches = has(i.title) ||
            has(i.reference) ||
            has(i.id.toString()) ||
            has(i.notes) ||
            has(i.locationLabel) ||
            has(i.createdByName);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  InspectionListLoaded copyWith({
    List<Inspection>? inspections,
    InspectionStatus? selectedStatus,
    bool clearStatus = false,
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateRange = false,
    OrgScopeSelection? orgScope,
  }) {
    return InspectionListLoaded(
      inspections: inspections ?? this.inspections,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      searchQuery: searchQuery ?? this.searchQuery,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      orgScope: orgScope ?? this.orgScope,
    );
  }

  @override
  List<Object?> get props =>
      [inspections, selectedStatus, searchQuery, dateFrom, dateTo, orgScope];
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

  Future<void> _load({
    required InspectionListLoaded? base,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required OrgScopeSelection scope,
  }) async {
    final seq = ++_requestSeq;
    try {
      final inspections = await _repository.fetchInspections(
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

  void setStatusFilter(InspectionStatus? status) {
    if (state is InspectionListLoaded) {
      final loaded = state as InspectionListLoaded;
      state = loaded.copyWith(selectedStatus: status, clearStatus: status == null);
    }
  }

  void setSearchQuery(String query) {
    if (state is InspectionListLoaded) {
      final loaded = state as InspectionListLoaded;
      state = loaded.copyWith(searchQuery: query.trim());
    }
  }
}
