import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final List<Inspection> inspections;
  final InspectionStatus? selectedStatus;
  final String searchQuery;

  List<Inspection> get filteredInspections {
    return inspections.where((i) {
      if (selectedStatus != null && i.status != selectedStatus) return false;
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchTitle = i.title.toLowerCase().contains(q);
        final matchNumber = i.inspectionNumber.toLowerCase().contains(q);
        final matchStation = i.stationName?.toLowerCase().contains(q) ?? false;
        final matchAsset = i.assetName?.toLowerCase().contains(q) ?? false;
        if (!matchTitle && !matchNumber && !matchStation && !matchAsset) return false;
      }
      return true;
    }).toList();
  }

  InspectionListLoaded copyWith({
    List<Inspection>? inspections,
    InspectionStatus? selectedStatus,
    bool clearStatus = false,
    String? searchQuery,
  }) {
    return InspectionListLoaded(
      inspections: inspections ?? this.inspections,
      selectedStatus: clearStatus ? null : (selectedStatus ?? this.selectedStatus),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [inspections, selectedStatus, searchQuery];
}

class InspectionListError extends InspectionListState {
  const InspectionListError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

final inspectionListControllerProvider =
    NotifierProvider<InspectionListController, InspectionListState>(InspectionListController.new);

class InspectionListController extends Notifier<InspectionListState> {
  @override
  InspectionListState build() => const InspectionListInitial();

  IInspectionRepository get _repository => ref.read(inspectionRepositoryProvider);

  Future<void> fetchInspections({bool forceRefresh = false}) async {
    if (!forceRefresh && state is InspectionListLoaded) return;
    state = const InspectionListLoading();
    try {
      final inspections = await _repository.fetchInspections();
      state = InspectionListLoaded(inspections: inspections);
    } catch (e) {
      state = InspectionListError('Failed to load inspections: $e');
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
