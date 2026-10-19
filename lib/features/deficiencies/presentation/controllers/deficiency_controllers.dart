import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/deficiencies/data/deficiency_repository.dart';
import 'package:gssms_mobile/features/deficiencies/domain/deficiency_bucket.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/batch_convert_result.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

// --- Deficiency List State & Notifier ---

sealed class DeficiencyListState extends Equatable {
  const DeficiencyListState();

  @override
  List<Object?> get props => [];
}

class DeficiencyListInitial extends DeficiencyListState {
  const DeficiencyListInitial();
}

class DeficiencyListLoading extends DeficiencyListState {
  const DeficiencyListLoading();
}

class DeficiencyListLoaded extends DeficiencyListState {
  const DeficiencyListLoaded({
    required this.deficiencies,
    this.selectedBucket = PendingBucket.needsAction,
    this.searchQuery = '',
    this.orgScope = OrgScopeSelection.empty,
    this.selectedDeficiencyIds = const {},
    this.creating = false,
  });

  final List<Deficiency> deficiencies;
  final PendingBucket? selectedBucket;
  final String searchQuery;
  final OrgScopeSelection orgScope;
  final Set<int> selectedDeficiencyIds;
  final bool creating;

  /// Items filtered by search and org scope, before bucket filtering.
  /// Used for non-collapsing dynamic counts on bucket chips.
  List<Deficiency> get baseFilteredDeficiencies {
    if (searchQuery.isEmpty) return deficiencies;
    final q = searchQuery.toLowerCase();
    bool has(String? v) => v != null && v.toLowerCase().contains(q);
    return deficiencies.where((d) {
      return has(d.code) ||
          has(d.id.toString()) ||
          has(d.description) ||
          has(d.deficiencyFinding) ||
          has(d.assetUniqueId) ||
          has(d.equipmentName) ||
          has(d.reportAssetEquipment) ||
          has(d.reportCheckpoint) ||
          has(d.depotName) ||
          has(d.workOrderTicket) ||
          has(d.activeRemedialWorkOrderStatus);
    }).toList();
  }

  /// Bucket counts computed after search but before bucket filter.
  Map<PendingBucket?, int> get bucketCounts {
    final base = baseFilteredDeficiencies;
    final counts = <PendingBucket?, int>{
      null: base.length,
      PendingBucket.needsAction: 0,
      PendingBucket.inProgress: 0,
      PendingBucket.awaitingClosure: 0,
    };
    for (final d in base) {
      final b = deficiencyBucket(d);
      counts[b] = (counts[b] ?? 0) + 1;
    }
    return counts;
  }

  /// Final list of deficiencies shown on screen.
  List<Deficiency> get filteredDeficiencies {
    final base = baseFilteredDeficiencies;
    if (selectedBucket == null) return base;
    return base.where((d) => deficiencyBucket(d) == selectedBucket).toList();
  }

  DeficiencyListLoaded copyWith({
    List<Deficiency>? deficiencies,
    PendingBucket? selectedBucket,
    bool clearBucket = false,
    String? searchQuery,
    OrgScopeSelection? orgScope,
    Set<int>? selectedDeficiencyIds,
    bool? creating,
  }) {
    return DeficiencyListLoaded(
      deficiencies: deficiencies ?? this.deficiencies,
      selectedBucket:
          clearBucket ? null : (selectedBucket ?? this.selectedBucket),
      searchQuery: searchQuery ?? this.searchQuery,
      orgScope: orgScope ?? this.orgScope,
      selectedDeficiencyIds:
          selectedDeficiencyIds ?? this.selectedDeficiencyIds,
      creating: creating ?? this.creating,
    );
  }

  @override
  List<Object?> get props => [
        deficiencies,
        selectedBucket,
        searchQuery,
        orgScope,
        selectedDeficiencyIds,
        creating,
      ];
}

class DeficiencyListError extends DeficiencyListState {
  const DeficiencyListError(this.message, {this.previousLoaded});
  final String message;

  /// Carries the last successfully loaded state so a retry or filter change
  /// doesn't wipe previously visible rows or active filters prematurely.
  final DeficiencyListLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}

final deficiencyListControllerProvider =
    NotifierProvider<DeficiencyListController, DeficiencyListState>(() {
  return DeficiencyListController();
});

class DeficiencyListController extends Notifier<DeficiencyListState> {
  @override
  DeficiencyListState build() {
    return const DeficiencyListInitial();
  }

  IDeficiencyRepository get _repository => ref.read(deficiencyRepositoryProvider);

  DeficiencyListLoaded? _resolvePrevious() {
    final s = state;
    if (s is DeficiencyListLoaded) return s;
    if (s is DeficiencyListError) return s.previousLoaded;
    return null;
  }

  int _requestSeq = 0;

  Future<void> fetchDeficiencies({bool forceRefresh = false}) async {
    final previous = _resolvePrevious();
    if (!forceRefresh && previous != null) return;

    if (previous == null) state = const DeficiencyListLoading();
    await _load(
      base: previous,
      scope: previous?.orgScope ?? OrgScopeSelection.empty,
    );
  }

  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    await _load(
      base: previous,
      scope: scope,
    );
  }

  Future<void> clearFilters() async {
    final previous = _resolvePrevious();
    if (previous != null) {
      state = previous.copyWith(
        selectedBucket: PendingBucket.needsAction,
        searchQuery: '',
        selectedDeficiencyIds: const {},
      );
    }
  }

  Future<void> _load({
    required DeficiencyListLoaded? base,
    required OrgScopeSelection scope,
  }) async {
    final seq = ++_requestSeq;
    try {
      final deficiencies = await _repository.fetchPendingDeficiencies(
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
      );
      if (seq != _requestSeq) return;
      state = DeficiencyListLoaded(
        deficiencies: deficiencies,
        selectedBucket: base?.selectedBucket ?? PendingBucket.needsAction,
        searchQuery: base?.searchQuery ?? '',
        orgScope: scope,
        selectedDeficiencyIds: const {},
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      state = DeficiencyListError(userFacingError(e), previousLoaded: base);
    }
  }

  void setBucketFilter(PendingBucket? bucket) {
    if (state is DeficiencyListLoaded) {
      final loaded = state as DeficiencyListLoaded;
      state = loaded.copyWith(
        selectedBucket: bucket,
        clearBucket: bucket == null,
        selectedDeficiencyIds: const {},
      );
    }
  }

  void setSearchQuery(String query) {
    if (state is DeficiencyListLoaded) {
      final loaded = state as DeficiencyListLoaded;
      state = loaded.copyWith(
        searchQuery: query.trim(),
        selectedDeficiencyIds: const {},
      );
    }
  }

  void toggleSelection(int id) {
    if (state is DeficiencyListLoaded) {
      final loaded = state as DeficiencyListLoaded;
      final next = Set<int>.from(loaded.selectedDeficiencyIds);
      if (!next.remove(id)) {
        next.add(id);
      }
      state = loaded.copyWith(selectedDeficiencyIds: next);
    }
  }

  void selectAll(List<int> visibleNeedsActionIds) {
    if (state is DeficiencyListLoaded) {
      final loaded = state as DeficiencyListLoaded;
      final allSelected = visibleNeedsActionIds.isNotEmpty &&
          visibleNeedsActionIds.every(loaded.selectedDeficiencyIds.contains);
      state = loaded.copyWith(
        selectedDeficiencyIds: allSelected ? const {} : visibleNeedsActionIds.toSet(),
      );
    }
  }

  void clearSelection() {
    if (state is DeficiencyListLoaded) {
      final loaded = state as DeficiencyListLoaded;
      state = loaded.copyWith(selectedDeficiencyIds: const {});
    }
  }

  /// Calls createRectification via WorkOrderRepository.
  /// Returns BatchConvertResult on success, or throws on failure.
  Future<BatchConvertResult> createJobWork(
    List<int> ids, {
    bool onePerDeficiency = false,
  }) async {
    if (ids.isEmpty) {
      return const BatchConvertResult();
    }
    final previous = _resolvePrevious();
    if (previous != null) {
      state = previous.copyWith(creating: true);
    }
    try {
      final result = await ref
          .read(workOrderRepositoryProvider)
          .createRectification(ids, onePerDeficiency: onePerDeficiency);
      await fetchDeficiencies(forceRefresh: true);
      return result;
    } finally {
      final current = _resolvePrevious();
      if (current != null && current.creating) {
        state = current.copyWith(creating: false);
      }
    }
  }
}

/// Loads pending deficiencies via [IDeficiencyRepository] and counts items
/// in the [PendingBucket.needsAction] bucket.
final deficiencyNeedsActionCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(deficiencyRepositoryProvider);
  final deficiencies = await repo.fetchPendingDeficiencies();
  return deficiencies
      .where((d) => deficiencyBucket(d) == PendingBucket.needsAction)
      .length;
});

