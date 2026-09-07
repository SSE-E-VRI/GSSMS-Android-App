import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        final matchTitle = c.title.toLowerCase().contains(q);
        final matchNumber = c.complaintNumber.toLowerCase().contains(q);
        final matchStation = c.stationName?.toLowerCase().contains(q) ?? false;
        final matchAsset = c.assetName?.toLowerCase().contains(q) ?? false;
        if (!matchTitle && !matchNumber && !matchStation && !matchAsset) {
          return false;
        }
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

  Future<void> fetchComplaints({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    if (!forceRefresh && previous != null) return;

    state = const ComplaintListLoading();
    final scope = previous?.orgScope ?? OrgScopeSelection.empty;
    try {
      final complaints = await _repository.fetchComplaints(
        dateFrom: formatApiDate(previous?.dateFrom),
        dateTo: formatApiDate(previous?.dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      state = ComplaintListLoaded(
        complaints: complaints,
        selectedStatus: previous?.selectedStatus,
        searchQuery: previous?.searchQuery ?? '',
        dateFrom: previous?.dateFrom,
        dateTo: previous?.dateTo,
        orgScope: scope,
      );
    } catch (e) {
      state = ComplaintListError('Failed to load complaints: $e', previousLoaded: previous);
    }
  }

  Future<void> setDateRange(DateTime? from, DateTime? to) async {
    final previous = _resolvePrevious();
    final scope = previous?.orgScope ?? OrgScopeSelection.empty;
    try {
      final complaints = await _repository.fetchComplaints(
        dateFrom: formatApiDate(from),
        dateTo: formatApiDate(to),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      state = ComplaintListLoaded(
        complaints: complaints,
        selectedStatus: previous?.selectedStatus,
        searchQuery: previous?.searchQuery ?? '',
        dateFrom: from,
        dateTo: to,
        orgScope: scope,
      );
    } catch (e) {
      state = ComplaintListError('Failed to load complaints: $e', previousLoaded: previous);
    }
  }

  /// Server-side Zone/Division/Depot filter (Complaints has no station-level
  /// filter server-side — see ComplaintViewSet.get_queryset — so this bar is
  /// used with `enableStation: false`).
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    try {
      final complaints = await _repository.fetchComplaints(
        dateFrom: formatApiDate(previous?.dateFrom),
        dateTo: formatApiDate(previous?.dateTo),
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      state = ComplaintListLoaded(
        complaints: complaints,
        selectedStatus: previous?.selectedStatus,
        searchQuery: previous?.searchQuery ?? '',
        dateFrom: previous?.dateFrom,
        dateTo: previous?.dateTo,
        orgScope: scope,
      );
    } catch (e) {
      state = ComplaintListError('Failed to load complaints: $e', previousLoaded: previous);
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
