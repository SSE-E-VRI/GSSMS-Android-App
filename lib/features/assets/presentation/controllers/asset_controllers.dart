import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/data/asset_repository.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

final assetRepositoryProvider = Provider<IAssetRepository>((ref) {
  final api = ref.watch(assetApiServiceProvider);
  return AssetRepository(api);
});

// --- Asset List State & Notifier ---

sealed class AssetListState extends Equatable {
  const AssetListState();

  @override
  List<Object?> get props => [];
}

class AssetListInitial extends AssetListState {
  const AssetListInitial();
}

class AssetListLoading extends AssetListState {
  const AssetListLoading();
}

class AssetListLoaded extends AssetListState {
  const AssetListLoaded({
    required this.assets,
    this.searchQuery = '',
    this.selectedCategory,
    this.selectedCriticality,
    this.orgScope = OrgScopeSelection.empty,
    this.truncated = false,
  });

  final List<Asset> assets;
  final String searchQuery;
  final String? selectedCategory;
  final AssetCriticality? selectedCriticality;

  /// The register was longer than one bounded fetch could walk, so [assets] is
  /// a prefix of it. The chips and search below filter that prefix, not the
  /// whole register, which is why the screen has to say so.
  final bool truncated;

  /// Server-side Zone/Division/Depot/Station narrowing (AssetViewSet applies
  /// all four independently), as opposed to the category/criticality/search
  /// filters below, which run against the rows already fetched.
  final OrgScopeSelection orgScope;

  List<String> get availableCategories {
    final cats = assets
        .map((a) => a.assetCategoryName)
        .where((c) => c != null && c.isNotEmpty)
        .map((c) => c!)
        .toSet()
        .toList();
    cats.sort();
    return cats;
  }

  List<Asset> get filteredAssets {
    return assets.where((a) {
      if (selectedCriticality != null && a.criticality != selectedCriticality) {
        return false;
      }
      if (selectedCategory != null && a.assetCategoryName != selectedCategory) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        final matchName = a.displayName.toLowerCase().contains(q);
        final matchCode = a.uniqueId.toLowerCase().contains(q);
        final matchStation = a.stationName?.toLowerCase().contains(q) ?? false;
        final matchSerial = a.serialNumber?.toLowerCase().contains(q) ?? false;
        if (!matchName && !matchCode && !matchStation && !matchSerial) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  AssetListLoaded copyWith({
    List<Asset>? assets,
    String? searchQuery,
    String? selectedCategory,
    bool clearCategory = false,
    AssetCriticality? selectedCriticality,
    bool clearCriticality = false,
    OrgScopeSelection? orgScope,
    bool? truncated,
  }) {
    return AssetListLoaded(
      assets: assets ?? this.assets,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: clearCategory ? null : (selectedCategory ?? this.selectedCategory),
      selectedCriticality: clearCriticality ? null : (selectedCriticality ?? this.selectedCriticality),
      orgScope: orgScope ?? this.orgScope,
      truncated: truncated ?? this.truncated,
    );
  }

  @override
  List<Object?> get props =>
      [assets, searchQuery, selectedCategory, selectedCriticality, orgScope, truncated];
}

class AssetListError extends AssetListState {
  const AssetListError(this.message, {this.previousLoaded});
  final String message;

  /// The last good list, kept so a failed refresh or filter change doesn't
  /// silently reset the filter bar the user is still looking at.
  final AssetListLoaded? previousLoaded;

  @override
  List<Object?> get props => [message, previousLoaded];
}

final assetListControllerProvider =
    NotifierProvider<AssetListController, AssetListState>(() {
  return AssetListController();
});

class AssetListController extends Notifier<AssetListState> {
  @override
  AssetListState build() {
    return const AssetListInitial();
  }

  IAssetRepository get _repository => ref.read(assetRepositoryProvider);

  AssetListLoaded? _resolvePrevious() {
    final s = state;
    if (s is AssetListLoaded) return s;
    if (s is AssetListError) return s.previousLoaded;
    return null;
  }

  Future<void> fetchAssets({bool forceRefresh = false}) async {
    if (!forceRefresh && state is AssetListLoaded) return;

    final previous = _resolvePrevious();
    state = const AssetListLoading();
    await _load(previous?.orgScope ?? OrgScopeSelection.empty, previous);
  }

  /// Server-side Zone/Division/Depot/Station filter. Unlike the category and
  /// criticality chips, this re-queries rather than filtering in memory — the
  /// list is fetched depot-by-depot, so narrowing has to happen server-side to
  /// be worth anything.
  Future<void> setOrgScope(OrgScopeSelection scope) async {
    final previous = _resolvePrevious();
    await _load(scope, previous);
  }

  Future<void> _load(OrgScopeSelection scope, AssetListLoaded? previous) async {
    try {
      final page = await _repository.fetchAssets(
        zoneId: scope.zoneId,
        divisionId: scope.divisionId,
        depotId: scope.depotId,
        stationId: scope.stationId,
      );
      // Carry the in-memory filters across the refetch: the search field and
      // chips on screen still show them, so rebuilding from scratch would
      // leave the list contradicting the visible filter.
      state = AssetListLoaded(
        assets: page.assets,
        truncated: page.truncated,
        searchQuery: previous?.searchQuery ?? '',
        selectedCategory: previous?.selectedCategory,
        selectedCriticality: previous?.selectedCriticality,
        orgScope: scope,
      );
    } catch (e) {
      state = AssetListError(
        'Failed to load assets: $e',
        previousLoaded: previous?.copyWith(orgScope: scope),
      );
    }
  }

  void setSearchQuery(String query) {
    if (state is AssetListLoaded) {
      final loaded = state as AssetListLoaded;
      state = loaded.copyWith(searchQuery: query.trim());
    }
  }

  void setCategoryFilter(String? category) {
    if (state is AssetListLoaded) {
      final loaded = state as AssetListLoaded;
      state = loaded.copyWith(
        selectedCategory: category,
        clearCategory: category == null,
      );
    }
  }

  void setCriticalityFilter(AssetCriticality? criticality) {
    if (state is AssetListLoaded) {
      final loaded = state as AssetListLoaded;
      state = loaded.copyWith(
        selectedCriticality: criticality,
        clearCriticality: criticality == null,
      );
    }
  }
}

// --- Asset Detail State & Notifier ---

sealed class AssetDetailState extends Equatable {
  const AssetDetailState();

  @override
  List<Object?> get props => [];
}

class AssetDetailLoading extends AssetDetailState {
  const AssetDetailLoading();
}

class AssetDetailLoaded extends AssetDetailState {
  const AssetDetailLoaded(this.asset);
  final Asset asset;

  @override
  List<Object?> get props => [asset];
}

class AssetDetailError extends AssetDetailState {
  const AssetDetailError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

final assetDetailControllerProvider =
    NotifierProvider.family<AssetDetailController, AssetDetailState, int>(() {
  return AssetDetailController();
});

class AssetDetailController extends FamilyNotifier<AssetDetailState, int> {
  @override
  AssetDetailState build(int arg) {
    return const AssetDetailLoading();
  }

  IAssetRepository get _repository => ref.read(assetRepositoryProvider);

  Future<void> loadAsset() async {
    state = const AssetDetailLoading();
    try {
      final asset = await _repository.fetchAssetById(arg);
      state = AssetDetailLoaded(asset);
    } catch (e) {
      state = AssetDetailError('Failed to load asset details: $e');
    }
  }
}
