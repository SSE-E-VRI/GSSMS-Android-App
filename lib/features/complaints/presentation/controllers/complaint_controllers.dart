import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/widgets/date_range_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_api_service.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';

final complaintRepositoryProvider = Provider<IComplaintRepository>((ref) {
  final api = ref.watch(complaintApiServiceProvider);
  return ComplaintRepository(api);
});

// --- Complaint List State & Notifier ---

sealed class ComplaintListState extends Equatable {
  const ComplaintListState();

  @override
  List<Object?> get props => [];
}

class ComplaintListInitial extends ComplaintListState {
  const ComplaintListInitial();
}

class ComplaintListLoading extends ComplaintListState {
  const ComplaintListLoading();
}

class ComplaintListLoaded extends ComplaintListState {
  const ComplaintListLoaded({
    required this.complaints,
    this.selectedStatus,
    this.searchQuery = '',
    this.dateFrom,
    this.dateTo,
    this.orgScope = OrgScopeSelection.empty,
  });

  final List<Complaint> complaints;
  final ComplaintStatus? selectedStatus;
  final String searchQuery;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final OrgScopeSelection orgScope;

  List<Complaint> get filteredComplaints {
    return complaints.where((c) {
      if (selectedStatus != null && c.status != selectedStatus) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        bool has(String? v) => v != null && v.toLowerCase().contains(q);
        final matches = has(c.title) ||
            has(c.reference) ||
            has(c.id.toString()) ||
            has(c.description) ||
            has(c.locationLabel) ||
            has(c.assetUniqueId) ||
            has(c.workOrderTicketNumber);
        if (!matches) return false;
      }
      return true;
    }).toList();
  }

  ComplaintListLoaded copyWith({
    List<Complaint>? complaints,
    ComplaintStatus? selectedStatus,
    bool clearStatus = false,
    String? searchQuery,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateRange = false,
    OrgScopeSelection? orgScope,
  }) {
    return ComplaintListLoaded(
      complaints: complaints ?? this.complaints,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      searchQuery: searchQuery ?? this.searchQuery,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      orgScope: orgScope ?? this.orgScope,
    );
  }

  @override
  List<Object?> get props =>
      [complaints, selectedStatus, searchQuery, dateFrom, dateTo, orgScope];
}

class ComplaintListError extends ComplaintListState {
  const ComplaintListError(this.message, {this.previousLoaded});
  final String message;

  /// Carries the last successfully loaded filters through the error so a
  /// retry/filter change issued from here doesn't silently reset them.
  final ComplaintListLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}

final complaintListControllerProvider =
    NotifierProvider<ComplaintListController, ComplaintListState>(() {
  return ComplaintListController();
});

class ComplaintListController extends Notifier<ComplaintListState> {
  @override
  ComplaintListState build() {
    return const ComplaintListInitial();
  }

  IComplaintRepository get _repository => ref.read(complaintRepositoryProvider);

  /// The last successfully loaded filters, whether the current state is
  /// still that loaded state or an error that carried them forward.
  ComplaintListLoaded? _resolvePrevious() {
    final s = state;
    if (s is ComplaintListLoaded) return s;
    if (s is ComplaintListError) return s.previousLoaded;
    return null;
  }

  /// Guards against an older, slower response overwriting a newer filter's.
  int _requestSeq = 0;

  Future<void> fetchComplaints({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    if (!forceRefresh && previous != null) return;

    // Stale-while-refresh: keep rows visible during a pull-to-refresh.
    if (previous == null) state = const ComplaintListLoading();
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

  /// Server-side Zone/Division/Depot filter (Complaints has no station-level
  /// filter server-side — see ComplaintViewSet.get_queryset — so this bar is
  /// used with `enableStation: false`).
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      dateFrom: previous?.dateFrom,
      dateTo: previous?.dateTo,
      scope: scope,
    );
  }

  /// Clears status, search and date range (org scope is kept — it is the
  /// user's working context, set from the app bar).
  Future<void> clearFilters() async {
    final previous = _resolvePrevious();
    await _load(
      base: previous == null
          ? null
          : ComplaintListLoaded(
              complaints: previous.complaints,
              orgScope: previous.orgScope,
            ),
      dateFrom: null,
      dateTo: null,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  Future<void> _load({
    required ComplaintListLoaded? base,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required OrgScopeSelection scope,
  }) async {
    final seq = ++_requestSeq;
    try {
      final complaints = await _repository.fetchComplaints(
        dateFrom: formatApiDate(dateFrom),
        dateTo: formatApiDate(dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      if (seq != _requestSeq) return;
      state = ComplaintListLoaded(
        complaints: complaints,
        selectedStatus: base?.selectedStatus,
        searchQuery: base?.searchQuery ?? '',
        dateFrom: dateFrom,
        dateTo: dateTo,
        orgScope: scope,
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      state = ComplaintListError(userFacingError(e), previousLoaded: base);
    }
  }

  void setStatusFilter(ComplaintStatus? status) {
    if (state is ComplaintListLoaded) {
      final loaded = state as ComplaintListLoaded;
      state = loaded.copyWith(
        selectedStatus: status,
        clearStatus: status == null,
      );
    }
  }

  void setSearchQuery(String query) {
    if (state is ComplaintListLoaded) {
      final loaded = state as ComplaintListLoaded;
      state = loaded.copyWith(searchQuery: query.trim());
    }
  }
}
