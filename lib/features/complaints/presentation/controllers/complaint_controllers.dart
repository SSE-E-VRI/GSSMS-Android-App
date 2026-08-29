import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final List<Complaint> complaints;
  final ComplaintStatus? selectedStatus;
  final String searchQuery;

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
  }) {
    return ComplaintListLoaded(
      complaints: complaints ?? this.complaints,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [complaints, selectedStatus, searchQuery];
}

class ComplaintListError extends ComplaintListState {
  const ComplaintListError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
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

  Future<void> fetchComplaints({bool forceRefresh = false}) async {
    if (!forceRefresh && state is ComplaintListLoaded) return;

    state = const ComplaintListLoading();
    try {
      final complaints = await _repository.fetchComplaints();
      state = ComplaintListLoaded(complaints: complaints);
    } catch (e) {
      state = ComplaintListError('Failed to load complaints: $e');
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
