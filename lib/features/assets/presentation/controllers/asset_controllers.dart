import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final List<Asset> assets;
  final String searchQuery;
  final String? selectedCategory;
  final AssetCriticality? selectedCriticality;

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
  }) {
    return AssetListLoaded(
      assets: assets ?? this.assets,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory: clearCategory ? null : (selectedCategory ?? this.selectedCategory),
      selectedCriticality: clearCriticality ? null : (selectedCriticality ?? this.selectedCriticality),
    );
  }

  @override
  List<Object?> get props => [assets, searchQuery, selectedCategory, selectedCriticality];
}

class AssetListError extends AssetListState {
  const AssetListError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
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

  Future<void> fetchAssets({bool forceRefresh = false}) async {
    if (!forceRefresh && state is AssetListLoaded) return;

    state = const AssetListLoading();
    try {
      final assets = await _repository.fetchAssets();
      state = AssetListLoaded(assets: assets);
    } catch (e) {
      state = AssetListError('Failed to load assets: $e');
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
