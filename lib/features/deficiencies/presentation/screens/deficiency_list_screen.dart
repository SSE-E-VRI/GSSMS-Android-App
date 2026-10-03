import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/sync/widgets/sync_status_badge.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/error_banner.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/gssms_search_field.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/severity_chip.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/deficiencies/domain/deficiency_bucket.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/deficiencies/presentation/controllers/deficiency_controllers.dart';
import 'package:gssms_mobile/features/deficiencies/presentation/deficiency_status_style.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:intl/intl.dart';

class DeficiencyListScreen extends ConsumerStatefulWidget {
  const DeficiencyListScreen({
    super.key,
    this.isEmbedded = false,
  });

  final bool isEmbedded;

  @override
  ConsumerState<DeficiencyListScreen> createState() =>
      _DeficiencyListScreenState();
}

class _DeficiencyListScreenState extends ConsumerState<DeficiencyListScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _onePerDeficiency = false;

  DeficiencyListController get _controller =>
      ref.read(deficiencyListControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'assets.view')) {
        return;
      }
      final current = ref.read(deficiencyListControllerProvider);
      if (current is DeficiencyListLoaded) {
        _searchController.text = current.searchQuery;
      }
      _controller.fetchDeficiencies();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _hasActiveFilters(DeficiencyListLoaded? s) =>
      s != null &&
      (s.selectedBucket != PendingBucket.needsAction ||
          s.searchQuery.isNotEmpty);

  Future<void> _clearFilters() async {
    _searchController.clear();
    await _controller.clearFilters();
  }

  void _onItemTapped(Deficiency d) {
    if (d.assetId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AssetDetailScreen(
            assetId: d.assetId!,
            initialTabIndex: 4,
          ),
        ),
      );
    } else {
      _showDeficiencyDetailsSheet(context, d);
    }
  }

  Future<void> _handleCreateSingle(Deficiency d) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Create Job Work',
      message: 'Create a Job Work for this deficiency?',
      confirmLabel: 'Create',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true) return;

    try {
      final res = await _controller.createJobWork([d.id], onePerDeficiency: false);
      if (!mounted) return;
      final tickets = res.tickets;
      final String successMsg;
      if (tickets.length == 1) {
        successMsg = 'Job Work ${tickets.first} created.';
      } else if (tickets.length > 1) {
        successMsg = '${tickets.length} Job Works created: ${tickets.join(", ")}.';
      } else {
        successMsg = 'Job Work created.';
      }
      showGssmsSnackBar(context, successMsg, tone: GssmsTone.success);
    } catch (e) {
      if (!mounted) return;
      if (classifyApiFailure(e) == ApiFailureKind.conflict) {
        final conflictMsg = userFacingError(e);
        showGssmsSnackBar(context, conflictMsg, tone: GssmsTone.danger);
        await _controller.fetchDeficiencies(forceRefresh: true);
      } else {
        showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
      }
    }
  }

  Future<void> _handleCreateBulk(List<int> ids) async {
    if (ids.isEmpty) return;
    final String prompt = _onePerDeficiency
        ? 'Create ${ids.length} Job Works, one per deficiency?'
        : 'Create rectification Job Work(s) for ${ids.length} deficiencies, grouped by location?';

    final confirmed = await showConfirmationDialog(
      context,
      title: 'Create Job Work',
      message: prompt,
      confirmLabel: 'Create',
      cancelLabel: 'Cancel',
    );
    if (confirmed != true) return;

    try {
      final res = await _controller.createJobWork(ids, onePerDeficiency: _onePerDeficiency);
      if (!mounted) return;
      final tickets = res.tickets;
      final String successMsg;
      if (tickets.length == 1) {
        successMsg = 'Job Work ${tickets.first} created.';
      } else if (tickets.length > 1) {
        successMsg = '${tickets.length} Job Works created: ${tickets.join(", ")}.';
      } else {
        successMsg = 'Job Work created.';
      }
      showGssmsSnackBar(context, successMsg, tone: GssmsTone.success);
    } catch (e) {
      if (!mounted) return;
      if (classifyApiFailure(e) == ApiFailureKind.conflict) {
        final conflictMsg = userFacingError(e);
        showGssmsSnackBar(context, conflictMsg, tone: GssmsTone.danger);
        await _controller.fetchDeficiencies(forceRefresh: true);
      } else {
        showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(deficiencyListControllerProvider);
    final session = sessionFromAuth(ref.watch(authControllerProvider));

    if (!sessionAllows(session, 'assets.view')) {
      return widget.isEmbedded
          ? const PermissionDeniedView()
          : Scaffold(
              appBar: AppBar(title: const Text('Deficiencies')),
              body: const PermissionDeniedView(),
            );
    }

    final canCreate = canCreateRectification(session);
    final loaded = listState is DeficiencyListLoaded
        ? listState
        : (listState is DeficiencyListError ? listState.previousLoaded : null);

    final isNeedsActionActive = loaded?.selectedBucket == PendingBucket.needsAction;
    final selectedCount = loaded?.selectedDeficiencyIds.length ?? 0;
    final isCreating = loaded?.creating ?? false;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text('Deficiencies'),
              actions: [
                if (session != null)
                  OrgScopeAppBarFilter(
                    scope: session.scope,
                    selection: loaded?.orgScope ?? OrgScopeSelection.empty,
                    enableStation: false,
                    onChanged: _controller.setOrgScope,
                  ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () => _controller.fetchDeficiencies(forceRefresh: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: SyncStatusBadge()),
            SliverToBoxAdapter(
              child: FilterStrip(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GssmsSearchField(
                      controller: _searchController,
                      hintText: 'Search by code, finding, asset, depot…',
                      onChanged: _controller.setSearchQuery,
                    ),
                    const SizedBox(height: GssmsSpacing.s8),
                    _BucketFilterChips(
                      selectedBucket: loaded?.selectedBucket,
                      counts: loaded?.bucketCounts ?? const {},
                      onChanged: _controller.setBucketFilter,
                    ),
                    if (canCreate && isNeedsActionActive && loaded != null) ...[
                      const SizedBox(height: GssmsSpacing.s8),
                      _SelectAllRow(
                        loaded: loaded,
                        onSelectAll: () {
                          final visibleNeeds = loaded.filteredDeficiencies
                              .where((d) => deficiencyBucket(d) == PendingBucket.needsAction)
                              .map((d) => d.id)
                              .toList();
                          _controller.selectAll(visibleNeeds);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (loaded != null)
              SliverToBoxAdapter(
                child: ListResultHeader(
                  shown: loaded.filteredDeficiencies.length,
                  total: loaded.baseFilteredDeficiencies.length,
                  noun: 'deficiencies',
                  onClearFilters:
                      _hasActiveFilters(loaded) ? _clearFilters : null,
                ),
              ),
            ..._buildListSlivers(listState, canCreate: canCreate),
          ],
        ),
      ),
      bottomNavigationBar: (canCreate && isNeedsActionActive && selectedCount > 0)
          ? _BottomActionBar(
              selectedCount: selectedCount,
              onePerDeficiency: _onePerDeficiency,
              isCreating: isCreating,
              onGroupingChanged: (v) => setState(() => _onePerDeficiency = v),
              onCreateBulk: () => _handleCreateBulk(
                loaded?.selectedDeficiencyIds.toList() ?? [],
              ),
            )
          : null,
    );
  }

  List<Widget> _buildListSlivers(DeficiencyListState state, {required bool canCreate}) {
    if (state is DeficiencyListInitial || state is DeficiencyListLoading) {
      return const [SliverSkeletonList()];
    }

    if (state is DeficiencyListError) {
      final previous = state.previousLoaded;
      if (previous != null) {
        return [
          SliverToBoxAdapter(
            child: ErrorBanner(
              message: state.message,
              onRetry: () => _controller.fetchDeficiencies(forceRefresh: true),
            ),
          ),
          ..._buildLoadedSlivers(previous, canCreate: canCreate),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.error(
            title: 'Could not load deficiencies',
            message: state.message,
            onRetry: () => _controller.fetchDeficiencies(forceRefresh: true),
          ),
        ),
      ];
    }

    if (state is DeficiencyListLoaded) {
      return _buildLoadedSlivers(state, canCreate: canCreate);
    }

    return const [SliverToBoxAdapter(child: SizedBox.shrink())];
  }

  List<Widget> _buildLoadedSlivers(DeficiencyListLoaded state, {required bool canCreate}) {
    final deficiencies = state.filteredDeficiencies;

    if (deficiencies.isEmpty) {
      final filtered = _hasActiveFilters(state);
      final emptyText = switch (state.selectedBucket) {
        null => 'No deficiencies found.',
        PendingBucket.needsAction => 'No deficiencies need action.',
        PendingBucket.inProgress => 'No deficiencies are in progress.',
        PendingBucket.awaitingClosure => 'No deficiencies are awaiting closure.',
      };
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateView.noResults(
            title: filtered ? emptyText : 'No deficiencies recorded yet',
            icon: Icons.rule_outlined,
            onClearFilters: filtered ? _clearFilters : null,
          ),
        ),
      ];
    }

    final isNeedsActionActive = state.selectedBucket == PendingBucket.needsAction;

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          0,
          GssmsSpacing.s4,
          0,
          GssmsSpacing.fabClearance,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final d = deficiencies[i];
              final isNeeds = deficiencyBucket(d) == PendingBucket.needsAction;
              final isSelected = state.selectedDeficiencyIds.contains(d.id);

              return _DeficiencyCard(
                deficiency: d,
                showCheckboxAndCreate: canCreate && isNeedsActionActive && isNeeds,
                isSelected: isSelected,
                isCreating: state.creating,
                onCheckboxChanged: () => _controller.toggleSelection(d.id),
                onCreateSingle: () => _handleCreateSingle(d),
                onTap: () => _onItemTapped(d),
              );
            },
            childCount: deficiencies.length,
          ),
        ),
      ),
    ];
  }
}

class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.loaded,
    required this.onSelectAll,
  });

  final DeficiencyListLoaded loaded;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final visibleNeeds = loaded.filteredDeficiencies
        .where((d) => deficiencyBucket(d) == PendingBucket.needsAction)
        .toList();
    if (visibleNeeds.isEmpty) return const SizedBox.shrink();

    final allSelected = visibleNeeds.isNotEmpty &&
        visibleNeeds.every((d) => loaded.selectedDeficiencyIds.contains(d.id));

    return Row(
      children: [
        Checkbox(
          value: allSelected,
          onChanged: (_) => onSelectAll(),
        ),
        Text(
          allSelected ? 'Deselect visible' : 'Select all visible',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BucketFilterChips extends StatelessWidget {
  const _BucketFilterChips({
    required this.selectedBucket,
    required this.counts,
    required this.onChanged,
  });

  final PendingBucket? selectedBucket;
  final Map<PendingBucket?, int> counts;
  final ValueChanged<PendingBucket?> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = <(String, PendingBucket?, Key)>[
      ('All', null, const Key('filter_chip_all')),
      (
        'Needs action',
        PendingBucket.needsAction,
        const Key('filter_chip_needs_action')
      ),
      (
        'In progress',
        PendingBucket.inProgress,
        const Key('filter_chip_in_progress')
      ),
      (
        'Awaiting closure',
        PendingBucket.awaitingClosure,
        const Key('filter_chip_awaiting_closure')
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, bucket, key) in chips) ...[
            FilterChip(
              key: key,
              label: Text('$label (${counts[bucket] ?? 0})'),
              selected: selectedBucket == bucket,
              onSelected: (_) => onChanged(bucket),
            ),
            const SizedBox(width: GssmsSpacing.s8),
          ],
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.selectedCount,
    required this.onePerDeficiency,
    required this.isCreating,
    required this.onGroupingChanged,
    required this.onCreateBulk,
  });

  final int selectedCount;
  final bool onePerDeficiency;
  final bool isCreating;
  final ValueChanged<bool> onGroupingChanged;
  final VoidCallback onCreateBulk;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      color: tokens.surfaceRaised,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GssmsSpacing.s16,
            GssmsSpacing.s8,
            GssmsSpacing.s16,
            GssmsSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$selectedCount selected • ${onePerDeficiency ? "One per deficiency" : "Grouped by location"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    key: const Key('rectification_grouping_switch'),
                    value: onePerDeficiency,
                    onChanged: isCreating ? null : onGroupingChanged,
                  ),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s8),
              ElevatedButton.icon(
                key: const Key('deficiency_create_bulk'),
                onPressed: isCreating ? null : onCreateBulk,
                icon: isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.build_circle_outlined, size: 18),
                label: Text(
                  isCreating
                      ? 'Creating...'
                      : 'Create rectification Job Work',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeficiencyCard extends StatelessWidget {
  const _DeficiencyCard({
    required this.deficiency,
    required this.showCheckboxAndCreate,
    required this.isSelected,
    required this.isCreating,
    required this.onCheckboxChanged,
    required this.onCreateSingle,
    required this.onTap,
  });

  final Deficiency deficiency;
  final bool showCheckboxAndCreate;
  final bool isSelected;
  final bool isCreating;
  final VoidCallback onCheckboxChanged;
  final VoidCallback onCreateSingle;
  final VoidCallback onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final metaStyle =
        textTheme.bodySmall?.copyWith(color: tokens.textSecondary);
    final severity = parseDeficiencySeverity(deficiency.severityLabel);

    final String assetEquipmentText;
    if (deficiency.assetUniqueId != null &&
        deficiency.assetUniqueId!.isNotEmpty) {
      if (deficiency.equipmentName != null &&
          deficiency.equipmentName!.isNotEmpty) {
        assetEquipmentText =
            '${deficiency.assetUniqueId} • ${deficiency.equipmentName}';
      } else {
        assetEquipmentText = deficiency.assetUniqueId!;
      }
    } else if (deficiency.assetId != null) {
      assetEquipmentText = 'Asset #${deficiency.assetId}';
    } else {
      assetEquipmentText = deficiency.displayAssetEquipment;
    }

    final bucket = deficiencyBucket(deficiency);

    return Card(
      key: Key('deficiency_card_${deficiency.id}'),
      margin: const EdgeInsets.symmetric(
        horizontal: GssmsSpacing.s16,
        vertical: GssmsSpacing.s6,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top line: Leading checkbox (if applicable) + Code + Badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showCheckboxAndCreate) ...[
                    Checkbox(
                      key: Key('deficiency_check_${deficiency.id}'),
                      value: isSelected,
                      onChanged: isCreating ? null : (_) => onCheckboxChanged(),
                    ),
                    const SizedBox(width: GssmsSpacing.s4),
                  ],
                  Expanded(
                    child: Text(
                      deficiency.code ?? 'DEF-${deficiency.id}',
                      style: textTheme.labelMedium?.copyWith(
                        color: tokens.link,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (severity != null) ...[
                    SeverityChip(
                      severity: severity,
                      label: severity.defaultLabel,
                    ),
                    const SizedBox(width: GssmsSpacing.s6),
                  ],
                  DeficiencyStatusChip(status: deficiency.status),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s8),

              // Description / finding — 2 lines max
              Text(
                deficiency.displayFinding,
                style: textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: GssmsSpacing.s12),

              // Metadata: Asset & equipment, depot, detected date
              Wrap(
                spacing: GssmsSpacing.s16,
                runSpacing: GssmsSpacing.s6,
                children: [
                  _Meta(
                    icon: Icons.precision_manufacturing_outlined,
                    text: assetEquipmentText,
                    style: metaStyle?.copyWith(
                      color: tokens.link,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (deficiency.depotName != null &&
                      deficiency.depotName!.isNotEmpty)
                    _Meta(
                      icon: Icons.location_on_outlined,
                      text: deficiency.depotName!,
                      style: metaStyle,
                    ),
                  if (deficiency.detectedAt != null)
                    _Meta(
                      icon: Icons.schedule,
                      text:
                          _dateFormat.format(deficiency.detectedAt!.toLocal()),
                      style: metaStyle,
                    ),
                ],
              ),

              // Linked Job Work / rectification in progress
              if (deficiency.workOrderTicket != null ||
                  deficiency.hasActiveRemedial ||
                  bucket == PendingBucket.inProgress) ...[
                const SizedBox(height: GssmsSpacing.s8),
                Wrap(
                  spacing: GssmsSpacing.s12,
                  runSpacing: GssmsSpacing.s6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (deficiency.workOrderTicket != null)
                      InkWell(
                        onTap: deficiency.workOrderId != null
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WorkOrderDetailScreen(
                                      workOrderId: deficiency.workOrderId!,
                                    ),
                                  ),
                                )
                            : null,
                        child: _Meta(
                          icon: Icons.assignment_outlined,
                          text: 'Job Work: ${deficiency.workOrderTicket}',
                          style: metaStyle?.copyWith(
                            color: deficiency.workOrderId != null ? tokens.link : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (deficiency.hasActiveRemedial)
                      InkWell(
                        onTap: deficiency.activeRemedialWorkOrderId != null
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WorkOrderDetailScreen(
                                      workOrderId:
                                          deficiency.activeRemedialWorkOrderId!,
                                    ),
                                  ),
                                )
                            : null,
                        child: StatusChip(
                          label:
                              'Rectification: ${deficiency.activeRemedialWorkOrderStatus ?? "In Progress"}',
                          tone: GssmsTone.info,
                          icon: Icons.build_circle_outlined,
                        ),
                      ),
                  ],
                ),
              ],

              // Per-card Create Job Work button
              if (showCheckboxAndCreate) ...[
                const SizedBox(height: GssmsSpacing.s12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: Key('deficiency_create_${deficiency.id}'),
                    onPressed: isCreating ? null : onCreateSingle,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(isCreating ? 'Creating...' : 'Create Job Work'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: GssmsSpacing.s4),
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

void _showDeficiencyDetailsSheet(BuildContext context, Deficiency d) {
  final dateFormat = DateFormat('dd MMM yyyy, HH:mm');
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GssmsSpacing.s16,
            0,
            GssmsSpacing.s16,
            GssmsSpacing.s16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SectionCard(
                  title: d.code ?? 'Deficiency #${d.id}',
                  icon: Icons.rule_outlined,
                  trailing: DeficiencyStatusChip(status: d.status),
                  children: [
                    InfoRow(
                      label: 'Code',
                      value: d.code ?? 'DEF-${d.id}',
                    ),
                    if (d.severityLabel != null)
                      InfoRow(
                        label: 'Severity',
                        value: d.severityLabel,
                      ),
                    if (d.sourceLabel != null)
                      InfoRow(
                        label: 'Source',
                        value: d.sourceLabel,
                      ),
                    InfoRow(
                      label: 'Asset / Equipment',
                      value: d.displayAssetEquipment,
                    ),
                    if (d.equipmentName != null)
                      InfoRow(
                        label: 'Equipment Name',
                        value: d.equipmentName,
                      ),
                    if (d.reportCheckpoint != null)
                      InfoRow(
                        label: 'Checkpoint',
                        value: d.reportCheckpoint,
                      ),
                    if (d.depotName != null)
                      InfoRow(
                        label: 'Depot',
                        value: d.depotName,
                      ),
                    if (d.detectedAt != null)
                      InfoRow(
                        label: 'Detected At',
                        value: dateFormat.format(d.detectedAt!.toLocal()),
                      ),
                    if (d.workOrderTicket != null)
                      InfoRow(
                        label: 'Linked Job Work',
                        value: d.workOrderTicket,
                      ),
                    if (d.hasActiveRemedial)
                      InfoRow(
                        label: 'Rectification Status',
                        value: d.activeRemedialWorkOrderStatus ?? 'In Progress',
                      ),
                    const SizedBox(height: GssmsSpacing.s8),
                    Text(
                      'Finding / Description',
                      style: Theme.of(ctx)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: ctx.gssms.textSecondary),
                    ),
                    const SizedBox(height: GssmsSpacing.s4),
                    TextWell(text: d.displayFinding),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
