import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/assets/presentation/widgets/qr_scanner_dialog.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';

class AssetListScreen extends ConsumerStatefulWidget {
  const AssetListScreen({super.key});

  @override
  ConsumerState<AssetListScreen> createState() => _AssetListScreenState();
}

class _AssetListScreenState extends ConsumerState<AssetListScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// True while a scanned code is being resolved to an asset.
  bool _isLookingUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'assets.view')) {
        return;
      }
      ref.read(assetListControllerProvider.notifier).fetchAssets();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Scans (or accepts a typed) asset code and opens that asset directly.
  ///
  /// A scan is a request for one specific asset, so it resolves the code
  /// against the register and navigates. It only falls back to filtering the
  /// list when the code matches nothing, which is the useful behaviour when a
  /// label is worn or mistyped.
  Future<void> _openQrScanner() async {
    final scannedCode = await showDialog<String>(
      context: context,
      builder: (_) => const QrScannerDialog(),
    );

    if (scannedCode == null || scannedCode.trim().isEmpty || !mounted) return;
    final code = scannedCode.trim();

    setState(() => _isLookingUp = true);
    Asset? match;
    Object? failure;
    try {
      match = await ref.read(assetRepositoryProvider).scanOrFindAssetByCode(code);
    } catch (e) {
      failure = e;
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }

    if (!mounted) return;

    if (match != null) {
      unawaited(Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AssetDetailScreen(assetId: match!.id),
        ),
      ));
      return;
    }

    _searchController.text = code;
    ref.read(assetListControllerProvider.notifier).setSearchQuery(code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure != null
              ? 'Could not look up "$code". Showing search results instead.'
              : 'No asset matches "$code". Showing search results instead.',
        ),
        backgroundColor: failure != null ? AppTheme.errorRed : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(assetListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'assets.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Asset Registry')),
        body: const PermissionDeniedView(),
      );
    }

    final loaded = listState is AssetListLoaded ? listState : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Registry'),
        actions: [
          if (session != null)
            OrgScopeAppBarFilter(
              scope: session.scope,
              selection: loaded?.orgScope ?? OrgScopeSelection.empty,
              onChanged: (selection) {
                ref
                    .read(assetListControllerProvider.notifier)
                    .setOrgScope(selection);
              },
            ),
          IconButton(
            key: const Key('action_scan_qr'),
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan Barcode / QR',
            onPressed: _openQrScanner,
          ),
        ],
      ),
      body: Column(
        children: [
          const SyncStatusBadge(),
          if (_isLookingUp)
            const LinearProgressIndicator(
              key: Key('asset_lookup_progress'),
              minHeight: 2,
            ),
          _buildSearchBar(),
          if (listState is AssetListLoaded && listState.truncated)
            _buildTruncationNotice(),
          _buildCategoryChips(listState),
          Expanded(child: _buildListBody(listState)),
        ],
      ),
    );
  }

  /// The register was too long to fetch whole. Say so — the search box and
  /// category chips below only filter what was actually downloaded, so a user
  /// who trusts an empty result here would conclude an asset doesn't exist.
  Widget _buildTruncationNotice() {
    return Container(
      key: const Key('asset_truncation_notice'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.warningAmber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warningAmber.withOpacity(0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.warningAmber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing part of the register. Narrow by depot or station to see '
              'the rest — search and category filters only apply to what is '
              'listed here.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search asset code, name, serial #...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(assetListControllerProvider.notifier)
                        .setSearchQuery('');
                  },
                ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: AppTheme.railwayBlue),
                onPressed: _openQrScanner,
              ),
            ],
          ),
          filled: true,
          fillColor: AppTheme.backgroundLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          ref.read(assetListControllerProvider.notifier).setSearchQuery(val);
        },
      ),
    );
  }

  Widget _buildCategoryChips(AssetListState state) {
    if (state is! AssetListLoaded) return const SizedBox.shrink();

    final categories = state.availableCategories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final selected = state.selectedCategory;
    final totalCount = state.assets.length;

    return Container(
      width: double.infinity,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text('All Categories ($totalCount)'),
            selected: selected == null,
            onSelected: (_) => ref
                .read(assetListControllerProvider.notifier)
                .setCategoryFilter(null),
          ),
          ...categories.map((cat) {
            final isSelected = selected == cat;
            final count =
                state.assets.where((a) => a.assetCategoryName == cat).length;
            return ChoiceChip(
              label: Text('$cat ($count)'),
              selected: isSelected,
              onSelected: (_) => ref
                  .read(assetListControllerProvider.notifier)
                  .setCategoryFilter(cat),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildListBody(AssetListState state) {
    if (state is AssetListLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AssetListError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(state.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(assetListControllerProvider.notifier)
                    .fetchAssets(forceRefresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is AssetListLoaded) {
      final assets = state.filteredAssets;

      if (assets.isEmpty) {
        return const Center(
          child: Text('No assets found matching criteria.'),
        );
      }

      return RefreshIndicator(
        onRefresh: () => ref
            .read(assetListControllerProvider.notifier)
            .fetchAssets(forceRefresh: true),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: assets.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _AssetCard(
              asset: assets[index],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AssetDetailScreen(assetId: assets[index].id),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset, required this.onTap});

  final Asset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('asset_card_${asset.id}'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.railwayBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      asset.uniqueId,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.railwayBlue,
                      ),
                    ),
                  ),
                  _criticalityBadge(asset.criticality),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                asset.displayName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (asset.assetCategoryName != null) ...[
                const SizedBox(height: 2),
                Text(
                  asset.assetCategoryName!,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      asset.stationName ?? asset.depotName ?? 'Location N/A',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (asset.criticality == AssetCriticality.critical)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'CRITICAL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.errorRed,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Criticality badge. The register has no per-asset operational status
  /// column, so criticality is what actually distinguishes assets at a glance.
  Widget _criticalityBadge(AssetCriticality criticality) {
    Color color;
    switch (criticality) {
      case AssetCriticality.critical:
        color = Colors.red.shade900;
        break;
      case AssetCriticality.high:
        color = AppTheme.errorRed;
        break;
      case AssetCriticality.medium:
        color = Colors.orange.shade700;
        break;
      case AssetCriticality.low:
        color = AppTheme.railwayGreen;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        criticality.displayName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
