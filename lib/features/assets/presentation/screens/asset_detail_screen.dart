import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_maintenance_summary.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_replacement_event.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_specification.dart';
import 'package:gssms_mobile/features/assets/domain/models/reliability_metrics.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:intl/intl.dart';

/// Mobile mirror of web's Asset Master Data page: Master Data /
/// Specifications / Components / Maintenance / Deficiencies / Replacement
/// History tabs, plus (within Master Data) the Asset Maintenance Status and
/// Reliability Analysis (ISO 55000) panels. Every tab past Master Data is
/// read-only on mobile — none of web's edit affordances (spec value entry,
/// component replacement, etc.) exist here, same reasoning as Deficiencies
/// already being view-only in Pending Actions.
class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});

  final int assetId;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
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
      ref.read(assetDetailControllerProvider(widget.assetId).notifier).loadAsset();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'assets.view')) {
      return Scaffold(
        appBar: AppBar(title: Text('Asset #${widget.assetId}')),
        body: const PermissionDeniedView(),
      );
    }

    final state = ref.watch(assetDetailControllerProvider(widget.assetId));

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titleFor(state)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh asset details',
              onPressed: () => ref
                  .read(assetDetailControllerProvider(widget.assetId).notifier)
                  .loadAsset(),
            ),
          ],
          bottom: state is AssetDetailLoaded
              ? const TabBar(
                  isScrollable: true,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: TextStyle(fontSize: 12),
                  tabs: [
                    Tab(text: 'Master Data'),
                    Tab(text: 'Specifications'),
                    Tab(text: 'Components'),
                    Tab(text: 'Maintenance'),
                    Tab(text: 'Deficiencies'),
                    Tab(text: 'Replacement History'),
                  ],
                )
              : null,
        ),
        body: _buildBody(state),
      ),
    );
  }

  /// The asset's own category (e.g. "CLS Panels") once loaded — that's what
  /// identifies the asset to someone opening this screen, not its internal
  /// id. Falls back to the id while loading or on error, when there's no
  /// category to show yet.
  String _titleFor(AssetDetailState state) {
    if (state is AssetDetailLoaded) {
      final category = state.asset.assetCategoryName;
      if (category != null && category.trim().isNotEmpty) return category;
    }
    return 'Asset #${widget.assetId}';
  }

  Widget _buildBody(AssetDetailState state) {
    if (state is AssetDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AssetDetailError) {
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
                    .read(assetDetailControllerProvider(widget.assetId).notifier)
                    .loadAsset(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is AssetDetailLoaded) {
      return TabBarView(
        children: [
          _MasterDataTab(asset: state.asset, assetId: widget.assetId),
          _SpecificationsTab(assetId: widget.assetId),
          _ComponentsTab(assetId: widget.assetId),
          _MaintenanceTab(assetId: widget.assetId),
          _DeficienciesTab(assetId: widget.assetId),
          _ReplacementHistoryTab(assetId: widget.assetId),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  // "Log Complaint for Asset" was removed from here — creating a complaint
  // now lives only in the Complaints module (its own list screen's FAB),
  // not duplicated as a per-asset shortcut here too.
}

Widget _sectionCard({required String title, required List<Widget> children}) {
  return Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

/// Generic error/loading wrapper for a tab whose data comes from one
/// `FutureProvider` — every tab past Master Data follows this same shape.
class _TabAsyncBody<T> extends StatelessWidget {
  const _TabAsyncBody({
    required this.value,
    required this.builder,
    required this.onRetry,
    this.emptyCheck,
    this.emptyLabel = 'Nothing here yet.',
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final bool Function(T data)? emptyCheck;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppTheme.errorRed),
              const SizedBox(height: 10),
              Text('$err', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Try Again')),
            ],
          ),
        ),
      ),
      data: (data) {
        if (emptyCheck != null && emptyCheck!(data)) {
          return Center(
            child: Text(emptyLabel, style: const TextStyle(color: AppTheme.textSecondary)),
          );
        }
        return builder(context, data);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Master Data tab
// ---------------------------------------------------------------------------

class _MasterDataTab extends ConsumerWidget {
  const _MasterDataTab({required this.asset, required this.assetId});
  final Asset asset;
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(asset),
          const SizedBox(height: 16),
          _sectionCard(title: 'Location & Installation', children: [
            _infoRow('Station', asset.stationName ?? 'N/A'),
            _infoRow('Depot', asset.depotName ?? 'N/A'),
            if (asset.infrastructureName != null)
              _infoRow('Infrastructure', asset.infrastructureName!),
            if (asset.installationDate != null)
              _infoRow('Installed Date', DateFormat('dd MMM yyyy').format(asset.installationDate!)),
          ]),
          _sectionCard(title: 'Technical Specifications', children: [
            _infoRow('Manufacturer', asset.make ?? 'N/A'),
            _infoRow('Model Number', asset.model ?? 'N/A'),
            _infoRow('Serial Number', asset.serialNumber ?? 'N/A'),
            _infoRow('Criticality', asset.criticality.displayName),
            if (asset.capacity != null) _infoRow('Capacity', asset.capacity!),
            if (asset.warrantyExpiryDate != null)
              _infoRow('Warranty Expiry', DateFormat('dd MMM yyyy').format(asset.warrantyExpiryDate!)),
            if (asset.lastMaintenanceDate != null)
              _infoRow('Last Maintenance', DateFormat('dd MMM yyyy').format(asset.lastMaintenanceDate!)),
          ]),
          if (asset.remarks != null && asset.remarks!.trim().isNotEmpty)
            _sectionCard(title: 'Remarks', children: [
              Text(asset.remarks!, style: const TextStyle(fontSize: 14)),
            ]),
          _buildMaintenanceStatusCard(ref),
          _buildReliabilityCard(ref),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Asset asset) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              asset.uniqueId,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.railwayBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              asset.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (asset.assetCategoryName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Category: ${asset.assetCategoryName}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _cadences = [
    ('MONTHLY', 'Monthly Schedule'),
    ('QUARTERLY', 'Quarterly Schedule'),
    ('HALF_YEARLY', 'Half Yearly Schedule'),
    ('YEARLY', 'Yearly Schedule'),
  ];

  Widget _buildMaintenanceStatusCard(WidgetRef ref) {
    final summary = ref.watch(assetMaintenanceSummaryProvider(assetId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return _sectionCard(
      title: 'Asset Maintenance Status',
      children: [
        _TabAsyncBody<AssetMaintenanceSummary>(
          value: summary,
          onRetry: () => ref.invalidate(assetMaintenanceSummaryProvider(assetId)),
          builder: (context, data) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _cadences.map((c) {
                final status = data.scheduleTypeSummary[c.$1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.$2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        'Last done: ${status?.lastDoneDate != null ? dateFormat.format(status!.lastDoneDate!) : '—'}   '
                        'Next due: ${status?.nextDueDate != null ? dateFormat.format(status!.nextDueDate!) : '—'}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildReliabilityCard(WidgetRef ref) {
    final metrics = ref.watch(assetReliabilityMetricsProvider(assetId));

    return _sectionCard(
      title: 'Reliability Analysis (ISO 55000)',
      children: [
        _TabAsyncBody<ReliabilityMetrics>(
          value: metrics,
          onRetry: () => ref.invalidate(assetReliabilityMetricsProvider(assetId)),
          builder: (context, data) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.periodStart != null && data.periodEnd != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Last 30 days: ${DateFormat('dd MMM').format(data.periodStart!)} – ${DateFormat('dd MMM yyyy').format(data.periodEnd!)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _metricTile('MTBF', data.displayMtbf, AppTheme.railwayBlue,
                          'Avg uptime between failures'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricTile('MTTR', data.displayMttr, AppTheme.errorRed,
                          'Avg downtime per failure'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metricTile('Availability', data.displayAvailability,
                          AppTheme.railwayGreen, 'Target 99.5%'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricTile('Failures', '${data.failures}', AppTheme.railwayBlue,
                          '${data.completedFailures} done / ${data.failures - data.completedFailures} open'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _infoRow('Calendar Exposure', '${data.exposureHours.toStringAsFixed(0)} hrs'),
                _infoRow('Operating Hours', '${data.operatingHours.toStringAsFixed(0)} hrs'),
                _infoRow('Observed Downtime', '${data.downtimeHours.toStringAsFixed(0)} hrs'),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, Color color, String caption) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(caption,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Specifications tab
// ---------------------------------------------------------------------------

class _SpecificationsTab extends ConsumerWidget {
  const _SpecificationsTab({required this.assetId});
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(assetSpecificationsProvider(assetId));
    return _TabAsyncBody<AssetSpecificationWorkspace>(
      value: workspace,
      onRetry: () => ref.invalidate(assetSpecificationsProvider(assetId)),
      emptyCheck: (data) => data.fields.isEmpty,
      emptyLabel: 'No specification template assigned to this asset.',
      builder: (context, data) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (data.templateName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(data.templateName!,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ...data.fields.map((f) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(f.label),
                    subtitle: f.notAvailableReason != null && f.notAvailableReason!.isNotEmpty
                        ? Text('Not available: ${f.notAvailableReason}',
                            style: const TextStyle(color: AppTheme.errorRed, fontSize: 12))
                        : null,
                    trailing: Text(
                      [
                        if (f.installedValue != null) f.installedValue!,
                        if (f.unit != null) f.unit!,
                      ].join(' '),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Components tab
// ---------------------------------------------------------------------------

class _ComponentsTab extends ConsumerWidget {
  const _ComponentsTab({required this.assetId});
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final components = ref.watch(assetComponentsProvider(assetId));
    return _TabAsyncBody<List<AssetComponent>>(
      value: components,
      onRetry: () => ref.invalidate(assetComponentsProvider(assetId)),
      emptyCheck: (data) => data.isEmpty,
      emptyLabel: 'No components recorded for this asset.',
      builder: (context, data) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final c = data[i];
            return Card(
              child: ListTile(
                leading: Icon(Icons.memory,
                    color: c.isActive ? AppTheme.railwayBlue : AppTheme.textSecondary),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  if (c.make != null) c.make!,
                  if (c.model != null) c.model!,
                  if (c.serialNumber != null) 'S/N ${c.serialNumber}',
                ].join(' • ')),
                trailing: c.status != null
                    ? Chip(
                        label: Text(c.status!, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Maintenance tab — same `maintenance-summary` data as the Master Data
// panel, tab-formatted with the actual schedule/work-order lists.
// ---------------------------------------------------------------------------

class _MaintenanceTab extends ConsumerWidget {
  const _MaintenanceTab({required this.assetId});
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(assetMaintenanceSummaryProvider(assetId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return _TabAsyncBody<AssetMaintenanceSummary>(
      value: summary,
      onRetry: () => ref.invalidate(assetMaintenanceSummaryProvider(assetId)),
      emptyCheck: (data) =>
          data.openWorkOrders.isEmpty && data.completedWorkOrders.isEmpty,
      emptyLabel: 'No maintenance activity recorded for this asset.',
      builder: (context, data) {
        Widget woTile(AssetMaintenanceWorkOrder wo) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(wo.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  if (wo.ticketNumber != null) wo.ticketNumber!,
                  if (wo.dueDate != null) 'Due ${dateFormat.format(wo.dueDate!)}',
                ].join(' • ')),
                trailing: Chip(
                  label: Text(wo.status, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (data.openWorkOrders.isNotEmpty) ...[
              const Text('Open', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...data.openWorkOrders.map(woTile),
              const SizedBox(height: 12),
            ],
            if (data.completedWorkOrders.isNotEmpty) ...[
              const Text('Completed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              ...data.completedWorkOrders.map(woTile),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Deficiencies tab
// ---------------------------------------------------------------------------

class _DeficienciesTab extends ConsumerWidget {
  const _DeficienciesTab({required this.assetId});
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deficiencies = ref.watch(assetDeficienciesProvider(assetId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return _TabAsyncBody<List<Deficiency>>(
      value: deficiencies,
      onRetry: () => ref.invalidate(assetDeficienciesProvider(assetId)),
      emptyCheck: (data) => data.isEmpty,
      emptyLabel: 'No deficiencies recorded for this asset.',
      builder: (context, data) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = data[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(d.reportCheckpoint ?? d.displayAssetEquipment,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Chip(
                          label: Text(d.status.displayName, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.errorLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.errorBorder),
                      ),
                      child: Text(d.displayFinding,
                          style: const TextStyle(fontSize: 12, color: AppTheme.errorRed)),
                    ),
                    if (d.detectedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(dateFormat.format(d.detectedAt!),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Replacement History tab
// ---------------------------------------------------------------------------

class _ReplacementHistoryTab extends ConsumerWidget {
  const _ReplacementHistoryTab({required this.assetId});
  final int assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(assetReplacementHistoryProvider(assetId));
    final dateFormat = DateFormat('dd MMM yyyy');

    return _TabAsyncBody<List<AssetReplacementEvent>>(
      value: history,
      onRetry: () => ref.invalidate(assetReplacementHistoryProvider(assetId)),
      emptyCheck: (data) => data.isEmpty,
      emptyLabel: 'No replacement history for this asset.',
      builder: (context, data) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: data.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final e = data[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz, color: AppTheme.railwayBlue),
                title: Text(e.displayLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  if (e.oldIdentitySummary != null || e.newIdentitySummary != null)
                    '${e.oldIdentitySummary ?? '—'} → ${e.newIdentitySummary ?? 'Removed'}',
                  if (e.reason != null && e.reason!.isNotEmpty) e.reason!,
                  if (e.date != null) dateFormat.format(e.date!),
                ].join('\n')),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}
