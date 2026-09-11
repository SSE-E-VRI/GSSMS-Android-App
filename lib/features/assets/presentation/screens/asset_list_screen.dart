import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/severity_chip.dart';
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
  const AssetListScreen({super.key, this.initialSearch});

  /// Pre-fills the search (e.g. a scanned code that matched no asset exactly,
  /// opened from the Home "Scan Asset" action).
  final String? initialSearch;

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
    final initial = widget.initialSearch?.trim();
    if (initial != null && initial.isNotEmpty) {
      _searchController.text = initial;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'assets.view')) {
        return;
      }
      final controller = ref.read(assetListControllerProvider.notifier);
      await controller.fetchAssets();
      if (mounted && initial != null && initial.isNotEmpty) {
        controller.setSearchQuery(initial);
      }
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
        backgroundColor: failure != null ? context.gssms.danger.foreground : null,
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
      // Filters are leading slivers ahead of the card list, not a fixed
      // Column above it, so the whole filter block scrolls away with the
      // list instead of permanently eating screen space — same change as
      // WorkOrderListScreen/ComplaintListScreen/InspectionListScreen.
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(assetListControllerProvider.notifier)
            .fetchAssets(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SyncStatusBadge()),
            if (_isLookingUp)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  key: Key('asset_lookup_progress'),
                  minHeight: 2,
                ),
              ),
            SliverToBoxAdapter(child: _buildSearchBar()),
            if (listState is AssetListLoaded && listState.truncated)
              SliverToBoxAdapter(child: _buildTruncationNotice()),
            SliverToBoxAdapter(child: _buildCategoryFilter(listState)),
            ..._buildListSlivers(listState),
          ],
        ),
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
        color: context.gssms.warning.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.gssms.warning.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: context.gssms.warning.foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing part of the register. Narrow by depot or station to see '
              'the rest — search and category filters only apply to what is '
              'listed here.',
              style: TextStyle(fontSize: 11, color: context.gssms.textSecondary),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSearchBar() {
    return Container(
      color: context.gssms.surfaceRaised,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search asset code, name, serial #...',
          prefixIcon: Icon(Icons.search, color: context.gssms.textSecondary),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(assetListControllerProvider.notifier)
                        .setSearchQuery('');
                  },
                ),
              IconButton(
                icon: Icon(Icons.qr_code_scanner, color: context.gssms.link),
                tooltip: 'Scan Barcode / QR',
                onPressed: _openQrScanner,
              ),
            ],
          ),
          filled: true,
          fillColor: context.gssms.surfaceInset,
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

  /// Category filter as a dropdown rather than a wrapping row of
  /// ChoiceChips — same reasoning as the other list screens' status/type
  /// dropdowns: with 11 real categories (AC Plants, CLS Panels, DG Sets,
  /// Escalators, HT Structure & Switch Yard, LT Panel Boards, Lifts,
  /// Submersible Pump, Substations, Transformers, Water Coolers) a chip
  /// Wrap ran to five full rows before the list even started.
  Widget _buildCategoryFilter(AssetListState state) {
    if (state is! AssetListLoaded) return const SizedBox.shrink();

    final categories = state.availableCategories;
    if (categories.isEmpty) return const SizedBox.shrink();

    final selected = state.selectedCategory;
    final totalCount = state.assets.length;

    int countFor(String cat) =>
        state.assets.where((a) => a.assetCategoryName == cat).length;

    return Container(
      color: context.gssms.surfaceRaised,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DropdownButtonFormField<String?>(
        key: const Key('asset_category_filter_dropdown'),
        isExpanded: true,
        value: selected,
        decoration: const InputDecoration(
          labelText: 'Category',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<String?>(
              value: null, child: Text('All Categories ($totalCount)')),
          ...categories.map((cat) => DropdownMenuItem(
              value: cat,
              child: Text('$cat (${countFor(cat)})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)))),
        ],
        onChanged: (cat) => ref
            .read(assetListControllerProvider.notifier)
            .setCategoryFilter(cat),
      ),
    );
  }

  /// Slivers for the scrollable body below the filter block (see build()).
  /// One `RefreshIndicator` wraps the whole `CustomScrollView` — filters
  /// included — so none of these branches carry their own.
  List<Widget> _buildListSlivers(AssetListState state) {
    if (state is AssetListLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (state is AssetListError) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: context.gssms.danger.foreground),
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
          ),
        ),
      ];
    }

    if (state is AssetListLoaded) {
      final assets = state.filteredAssets;

      if (assets.isEmpty) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No assets found matching criteria.')),
          ),
        ];
      }

      return [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                // Odd indices are the 12px separators between cards — same
                // spacing the old ListView.separated used.
                if (i.isOdd) return const SizedBox(height: 12);
                final asset = assets[i ~/ 2];
                return _AssetCard(
                  asset: asset,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AssetDetailScreen(assetId: asset.id),
                      ),
                    );
                  },
                );
              },
              childCount: assets.length * 2 - 1,
            ),
          ),
        ),
      ];
    }

    return const [SliverToBoxAdapter(child: SizedBox.shrink())];
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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.gssms.info.background,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        asset.uniqueId,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: context.gssms.link,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                  style: TextStyle(fontSize: 12, color: context.gssms.textSecondary),
                ),
              ],
              const Divider(height: 16),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: context.gssms.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      asset.stationName ?? asset.depotName ?? 'Location N/A',
                      style: TextStyle(fontSize: 12, color: context.gssms.textSecondary),
                      overflow: TextOverflow.ellipsis,
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
    final severity = switch (criticality) {
      AssetCriticality.critical => GssmsSeverity.critical,
      AssetCriticality.high => GssmsSeverity.high,
      AssetCriticality.medium => GssmsSeverity.medium,
      AssetCriticality.low => GssmsSeverity.low,
    };
    return SeverityChip(severity: severity, label: criticality.displayName);
  }
}
