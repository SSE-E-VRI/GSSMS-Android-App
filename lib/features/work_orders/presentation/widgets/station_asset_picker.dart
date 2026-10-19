import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/gssms_search_field.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';

/// Opens a searchable, station-scoped asset picker. Resolves to the chosen
/// asset, or null when dismissed. The list is always scoped to the Job Work's
/// station (and infrastructure); without a station nothing is listed.
Future<Asset?> showStationAssetPicker(
  BuildContext context, {
  required IReplacementRepository repository,
  required ReplacementJobWork jobWork,
  String title = 'Select Asset to Replace',
  int? selectedAssetId,
}) {
  return showModalBottomSheet<Asset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: StationAssetPicker(
        repository: repository,
        jobWork: jobWork,
        title: title,
        selectedAssetId: selectedAssetId,
      ),
    ),
  );
}

class StationAssetPicker extends StatefulWidget {
  const StationAssetPicker({
    super.key,
    required this.repository,
    required this.jobWork,
    this.title = 'Select Asset to Replace',
    this.selectedAssetId,
  });

  final IReplacementRepository repository;
  final ReplacementJobWork jobWork;
  final String title;
  final int? selectedAssetId;

  /// Case-insensitive match on id, name, category, make, model and serial.
  static bool matches(Asset a, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      a.uniqueId,
      a.displayName,
      a.assetCategoryName,
      a.make,
      a.model,
      a.serialNumber,
    ].any((s) => s != null && s.toLowerCase().contains(q));
  }

  @override
  State<StationAssetPicker> createState() => _StationAssetPickerState();
}

class _StationAssetPickerState extends State<StationAssetPicker> {
  final _searchController = TextEditingController();
  Future<AssetPage>? _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final stationId = widget.jobWork.stationId;
    // Never fall back to an unscoped list.
    if (stationId == null) {
      _future = null;
      return;
    }
    final f = Future<AssetPage>.sync(
      () => widget.repository.fetchStationAssets(
        stationId: stationId,
        infrastructureId: widget.jobWork.infrastructureId,
      ),
    );
    f.ignore();
    _future = f;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);
    final stationName = widget.jobWork.stationName?.trim();
    final future = _future;

    Widget body;
    if (future == null) {
      body = const EmptyStateView(
        key: Key('station_asset_no_station'),
        icon: Icon(Icons.location_off_outlined, size: GssmsSize.iconXl),
        title:
            "This Job Work has no station, so registered assets can't be listed.",
      );
    } else {
      body = FutureBuilder<AssetPage>(
        future: future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Center(
              key: const Key('station_asset_loading'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: GssmsSpacing.s12),
                  Text('Searching...', style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return EmptyStateView.error(
              key: const Key('station_asset_error'),
              title:
                  'Failed to load registered assets for this maintenance location.',
              message: replacementErrorText(snap.error!),
              onRetry: () => setState(_load),
            );
          }
          final page = snap.data!;
          if (page.assets.isEmpty) {
            return const EmptyStateView(
              key: Key('station_asset_empty'),
              icon: Icon(Icons.inbox_outlined, size: GssmsSize.iconXl),
              title:
                  'No registered assets are available at this maintenance location.',
            );
          }
          final shown = [
            for (final a in page.assets)
              if (StationAssetPicker.matches(a, _query)) a,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.truncated)
                Padding(
                  padding: const EdgeInsets.only(bottom: GssmsSpacing.s8),
                  child: Text(
                    key: const Key('station_asset_truncated'),
                    'Showing the first ${page.assets.length} assets. '
                    'Type to narrow the list.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: tokens.warning.foreground),
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text(
                          key: const Key('station_asset_no_match'),
                          'No assets found matching "${_query.trim()}".',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final a = shown[i];
                          final selected = a.id == widget.selectedAssetId;
                          final detail = a.makeModel;
                          return ListTile(
                            key: Key('station_asset_tile_${a.id}'),
                            selected: selected,
                            title: Text(
                              a.uniqueId,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              detail.isEmpty
                                  ? a.displayName
                                  : '${a.displayName} - $detail',
                            ),
                            trailing: Icon(
                              selected ? Icons.check : Icons.arrow_forward,
                            ),
                            onTap: () => Navigator.of(ctx).pop(a),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            key: const Key('station_asset_picker_title'),
            style: theme.textTheme.titleLarge,
          ),
          if (future != null && stationName != null && stationName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: GssmsSpacing.s4),
              child: Text(
                'Assets at $stationName',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tokens.textSecondary),
              ),
            ),
          const SizedBox(height: GssmsSpacing.s12),
          if (future != null) ...[
            GssmsSearchField(
              fieldKey: const Key('station_asset_search'),
              controller: _searchController,
              hintText: 'Search by Asset ID or Name...',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: GssmsSpacing.s8),
          ],
          Expanded(child: body),
          const SizedBox(height: GssmsSpacing.s8),
          TextButton(
            key: const Key('station_asset_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
