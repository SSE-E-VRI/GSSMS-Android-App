import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/org_scope_app_bar_filter.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_detail_screen.dart';
import 'package:gssms_mobile/features/deficiencies/domain/models/deficiency.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_detail_screen.dart';
import 'package:gssms_mobile/features/maintenance_schedules/domain/models/maintenance_schedule.dart';
import 'package:gssms_mobile/features/pending_actions/presentation/controllers/pending_actions_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/pending_action_status_labels.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:intl/intl.dart';

/// Mobile mirror of web's Dashboard "Pending Actions" 4-tab card
/// (DashboardView.jsx): Scheduled Tasks / Complaints / Inspection Notes /
/// Deficiencies, each its own server-scoped list with a batch "Create Job
/// Works from selected" action (Deficiencies is view-only on web too — it
/// just deep-links into the asset, mirrored here the same way).
class PendingActionsScreen extends ConsumerStatefulWidget {
  const PendingActionsScreen({super.key});

  @override
  ConsumerState<PendingActionsScreen> createState() =>
      _PendingActionsScreenState();
}

class _PendingActionsScreenState extends ConsumerState<PendingActionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)), 'maintenance.view')) {
        return;
      }
      ref.read(pendingActionsControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    if (!sessionAllows(session, 'maintenance.view')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending Actions')),
        body: const PermissionDeniedView(),
      );
    }

    final state = ref.watch(pendingActionsControllerProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pending Actions'),
          actions: [
            OrgScopeAppBarFilter(
              scope: session!.scope,
              selection: state.orgScope,
              // None of the four Pending Actions sources accept a
              // station-level query param server-side (schedules/pending/,
              // complaints/, inspections/, deficiencies/pending/ — each
              // takes only zone/division/depot) — same reasoning as
              // Complaints/Inspections' own list screens. Without this the
              // sheet offers a Station picker, once a Depot is chosen, that
              // silently does nothing: nothing downstream ever forwards it.
              enableStation: false,
              onChanged: (selection) => ref
                  .read(pendingActionsControllerProvider.notifier)
                  .setOrgScope(selection),
            ),
          ],
          // No fixed-height wrapper: TabBar sizes its own `preferredSize`
          // (taller automatically once tabs carry both an icon and text),
          // so hard-coding a height here would just re-clip it.
          bottom: TabBar(
            // Fixed, not scrollable: 4 tabs is few enough to lay out evenly
            // and read at a glance — a scrollable bar that hides 2 of 4
            // tabs off-screen with no visible cue you can swipe is worse
            // than short labels. The label text stays short; the icon takes
            // its own line above it (Tab's built-in icon+text layout) so the
            // label isn't fighting the icon for the same horizontal space.
            isScrollable: false,
            // TabBar's default M3 colours are tuned for a *light* surface —
            // this bar sits on the AppBar's `primaryDark` background, where
            // that default unselected-label grey was nearly unreadable
            // (the actual bug reported). Explicit high-contrast colours for
            // a dark bar, independent of the app's light ColorScheme.
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            tabs: [
              _tab(Icons.event_repeat, 'Schedules', state.filteredSchedules.length),
              _tab(Icons.campaign_outlined, 'Breakdowns', state.filteredComplaints.length),
              _tab(Icons.note_add_outlined, 'Inspections', state.filteredInspections.length),
              _tab(Icons.report_problem_outlined, 'Deficiencies', state.filteredDeficiencies.length),
            ],
          ),
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.error != null
                ? _errorView(state.error!)
                : Column(
                    children: [
                      const _SubFilterBar(),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _SchedulesTab(state: state),
                            _ComplaintsTab(state: state),
                            _InspectionsTab(state: state),
                            _DeficienciesTab(state: state),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// Icon-above-label two-line tab (Flutter's built-in `Tab(icon:, text:)`
  /// layout) rather than one long line of text — with 4 fixed-width tabs on
  /// a phone, "Deficiencies (12)" as a single line is the thing that forced
  /// scrolling in the first place. Splitting the icon onto its own line
  /// gives the label row its full tab-width to itself.
  Widget _tab(IconData icon, String label, int count) => Tab(
        icon: Icon(icon, size: 18),
        text: count > 0 ? '$label ($count)' : label,
        iconMargin: const EdgeInsets.only(bottom: 2),
      );

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.gssms.danger.foreground),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(pendingActionsControllerProvider.notifier).load(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip for the linked Job Work's status on converted rows, with the
/// technician's name when the server sent one (`wo_assigned_to_name`).
Widget? _woStatusChip(String? status, {String? assignedToName}) {
  if (status == null || status.trim().isEmpty) return null;
  return StatusChip(
      label: pendingActionStatusLabelWithAssignee(status, assignedToName));
}

/// Per-filter empty text, as on web ("No breakdowns need action." etc.).
String _emptyText(String all, String noun, PendingSubFilter f) => switch (f) {
      PendingSubFilter.all => all,
      PendingSubFilter.needsAction => 'No $noun need action.',
      PendingSubFilter.inProgress => 'No $noun in progress.',
      PendingSubFilter.awaitingClosure => 'No $noun awaiting closure.',
    };

/// Horizontal sub-filter chips (All / Needs action / In progress / Awaiting
/// closure) with counts for whichever tab is showing.
class _SubFilterBar extends ConsumerWidget {
  const _SubFilterBar();

  static const _tabs = PendingActionTab.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pendingActionsControllerProvider);
    final tabController = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: tabController,
      builder: (context, _) {
        final counts = state.countsFor(_tabs[tabController.index]);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
              GssmsSpacing.s12, GssmsSpacing.s8, GssmsSpacing.s12, 0),
          child: Row(
            children: [
              for (final f in PendingSubFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: GssmsSpacing.s8),
                  child: ChoiceChip(
                    key: Key(_filterKey(f)),
                    label: Text('${f.label} (${counts[f] ?? 0})'),
                    selected: state.subFilter == f,
                    onSelected: (_) => ref
                        .read(pendingActionsControllerProvider.notifier)
                        .setSubFilter(f),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _filterKey(PendingSubFilter f) => switch (f) {
        PendingSubFilter.all => 'pending_subfilter_all',
        PendingSubFilter.needsAction => 'pending_subfilter_needs_action',
        PendingSubFilter.inProgress => 'pending_subfilter_in_progress',
        PendingSubFilter.awaitingClosure => 'pending_subfilter_awaiting_closure',
      };
}

/// Shared "select rows, then convert" footer + empty state, parameterised
/// per tab so the four convertible tabs (Schedules/Breakdowns/Inspections/
/// Deficiencies) don't each hand-roll the same selection-count bar and
/// button. Deficiencies pass [actionNoun] 'rectification Job Work' plus an
/// [aboveButton] grouping switch and an [onConvert] override carrying the
/// switch value into `convertSelected`.
class _ConvertibleListScaffold extends ConsumerWidget {
  const _ConvertibleListScaffold({
    required this.tab,
    required this.itemCount,
    required this.selectedCount,
    required this.canConvert,
    required this.emptyLabel,
    required this.itemBuilder,
    this.actionNoun = 'Job Work',
    this.aboveButton,
    this.onConvert,
    this.confirmMessage,
  });

  final PendingActionTab tab;
  final int itemCount;
  final int selectedCount;
  final bool canConvert;
  final String emptyLabel;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final String actionNoun;
  final Widget? aboveButton;
  final Future<bool> Function()? onConvert;
  final String? confirmMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final converting =
        ref.watch(pendingActionsControllerProvider).converting;

    if (itemCount == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: context.gssms.success.foreground),
            const SizedBox(height: 12),
            Text(emptyLabel, style: TextStyle(color: context.gssms.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
        if (canConvert && selectedCount > 0)
          Material(
            elevation: 8,
            color: context.gssms.surfaceRaised,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (aboveButton != null) ...[
                    aboveButton!,
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('pending_actions_convert_button'),
                      onPressed: converting
                          ? null
                          : () async {
                              final plural = selectedCount == 1 ? '' : 's';
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Create $actionNoun$plural'),
                                  content: Text(confirmMessage ??
                                      'Create $selectedCount $actionNoun$plural from the selected items?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel')),
                                    ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Create')),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              final ok = onConvert != null
                                  ? await onConvert!()
                                  : await ref
                                      .read(pendingActionsControllerProvider
                                          .notifier)
                                      .convertSelected(tab);
                          final message = ref
                              .read(pendingActionsControllerProvider)
                              .actionMessage;
                          if (context.mounted && message != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(message),
                                backgroundColor:
                                    ok ? context.gssms.success.foreground : context.gssms.danger.foreground,
                              ),
                            );
                          }
                        },
                  icon: converting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.gpp_good_outlined, size: 18),
                  label: Text(converting
                      ? 'Creating...'
                      : 'Create $selectedCount $actionNoun${selectedCount == 1 ? '' : 's'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    );
  }
}

class _SchedulesTab extends ConsumerWidget {
  const _SchedulesTab({required this.state});
  final PendingActionsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    final canConvert = canBatchConvertSchedules(session);
    final dateFormat = DateFormat('dd MMM yyyy');
    final schedules = state.filteredSchedules;

    return _ConvertibleListScaffold(
      tab: PendingActionTab.schedules,
      itemCount: schedules.length,
      selectedCount: state.selectedScheduleIds.length,
      canConvert: canConvert,
      emptyLabel: _emptyText('No pending scheduled tasks.',
          'scheduled tasks', state.subFilter),
      itemBuilder: (context, index) {
        final s = schedules[index];
        final selected = state.selectedScheduleIds.contains(s.id);
        // C1: a terminated (SKIPPED) asset occurrence names its reason
        // instead of showing a bare "Skipped" chip with no context.
        final statusLabel =
            s.status == ScheduleStatus.skipped && s.terminationLabel != null
                ? '${s.status.displayName} — ${s.terminationLabel}'
                : s.status.displayName;
        return Card(
          key: Key('schedule_pending_card_${s.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            // Review finding B1: SKIPPED rows have no work order, so
            // `!s.isConverted` alone let them render a live checkbox and be
            // submitted for batch conversion - which the backend always
            // refuses (400), with no explanation surfaced back to the user.
            leading: canConvert && !s.isConverted && !s.isSkipped
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => ref
                        .read(pendingActionsControllerProvider.notifier)
                        .toggleSelection(PendingActionTab.schedules, s.id),
                  )
                : Icon(Icons.event_repeat, color: context.gssms.link),
            title: Text(s.templateName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([
              s.stationName ?? s.depotName ?? 'Station General',
              // C1: asset occurrences name their asset so two assets at one
              // station are distinguishable; station rows render as before.
              if (s.assetName != null) s.assetName!,
              if (s.dueDate != null) 'Due ${dateFormat.format(s.dueDate!)}',
            ].join(' • ')),
            trailing: s.isConverted
                ? (_woStatusChip(s.workOrderStatus) ??
                    Icon(Icons.link,
                        color: context.gssms.success.foreground, size: 18))
                : Chip(
                    label: Text(statusLabel,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
        );
      },
    );
  }
}

class _ComplaintsTab extends ConsumerWidget {
  const _ComplaintsTab({required this.state});
  final PendingActionsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    final canConvert = canBatchConvertToWorkOrder(session);
    final complaints = state.filteredComplaints;

    return _ConvertibleListScaffold(
      tab: PendingActionTab.complaints,
      itemCount: complaints.length,
      selectedCount: state.selectedComplaintIds.length,
      canConvert: canConvert,
      emptyLabel:
          _emptyText('No open breakdowns.', 'breakdowns', state.subFilter),
      itemBuilder: (context, index) {
        final Complaint c = complaints[index];
        final selected = state.selectedComplaintIds.contains(c.id);
        return Card(
          key: Key('complaint_pending_card_${c.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: canConvert && !c.isConverted && !c.isClosed
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => ref
                        .read(pendingActionsControllerProvider.notifier)
                        .toggleSelection(PendingActionTab.complaints, c.id),
                  )
                : Icon(Icons.campaign_outlined, color: context.gssms.danger.foreground),
            title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${c.reference} • ${c.locationLabel ?? c.depotName ?? 'Location not set'}'),
            trailing: c.isConverted
                ? _woStatusChip(c.workOrderStatus,
                    assignedToName: c.woAssignedToName)
                : null,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ComplaintDetailScreen(complaint: c))),
          ),
        );
      },
    );
  }
}

class _InspectionsTab extends ConsumerWidget {
  const _InspectionsTab({required this.state});
  final PendingActionsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    final canConvert = canBatchConvertToWorkOrder(session);
    final inspections = state.filteredInspections;

    return _ConvertibleListScaffold(
      tab: PendingActionTab.inspections,
      itemCount: inspections.length,
      selectedCount: state.selectedInspectionIds.length,
      canConvert: canConvert,
      emptyLabel: _emptyText('No inspection notes pending.',
          'inspection notes', state.subFilter),
      itemBuilder: (context, index) {
        final Inspection insp = inspections[index];
        final selected = state.selectedInspectionIds.contains(insp.id);
        return Card(
          key: Key('inspection_pending_card_${insp.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            // Point-wise inspections can't be converted whole (since 1.9.0):
            // only point-less, unconverted notes are selectable; the rest
            // open the detail screen on tap.
            leading: canConvert && insp.pointsCount == 0 && !insp.isConverted
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => ref
                        .read(pendingActionsControllerProvider.notifier)
                        .toggleSelection(PendingActionTab.inspections, insp.id),
                  )
                : Icon(Icons.note_add_outlined, color: context.gssms.link),
            title:
                Text(insp.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${insp.reference} • ${insp.locationLabel ?? insp.depotName ?? 'Location not set'}'),
            trailing: insp.isConverted
                ? _woStatusChip(insp.workOrderStatus,
                    assignedToName: insp.woAssignedToName)
                : null,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InspectionDetailScreen(inspection: insp))),
          ),
        );
      },
    );
  }
}

/// Tap deep-links to the asset's own Deficiencies tab (AssetDetailScreen),
/// matching `navigate(/assets/{id}?tab=deficiencies)` on web as closely as
/// the mobile asset screen allows today — or to the linked Job Work first,
/// following the same priority web's `openDeficiency`/"View report" use.
/// RESOLVED/CLOSED green, everything else amber — same two-bucket logic as
/// web's `deficiencyStatusBadgeClass` (OPEN/ASSIGNED/IN_PROGRESS all read
/// amber there too, not a distinct colour per status).
Color _deficiencyStatusColor(BuildContext context, DeficiencyStatus status) {
  switch (status) {
    case DeficiencyStatus.resolved:
    case DeficiencyStatus.closed:
      return context.gssms.success.foreground;
    case DeficiencyStatus.open:
    case DeficiencyStatus.assigned:
    case DeficiencyStatus.inProgress:
    case DeficiencyStatus.unknown:
      return context.gssms.warning.foreground;
  }
}

/// Card version of web's Deficiencies table (Date / Job Work / Asset-
/// Equipment / Checkpoint / Deficiency Finding / Status columns) — a wide
/// data table doesn't fit a phone, so each row's columns become labelled
/// lines on a card instead, in the same left-to-right reading order.
/// Rows are selectable for grouped rectification Job Work creation,
/// mirroring web's Deficiencies tab (`createRectification`, one Job Work
/// per location by default, one per deficiency on toggle).
class _DeficienciesTab extends ConsumerStatefulWidget {
  const _DeficienciesTab({required this.state});
  final PendingActionsState state;

  @override
  ConsumerState<_DeficienciesTab> createState() => _DeficienciesTabState();
}

class _DeficienciesTabState extends ConsumerState<_DeficienciesTab> {
  bool _onePerDeficiency = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = sessionFromAuth(ref.watch(authControllerProvider));
    final canConvert = canCreateRectification(session);
    final dateFormat = DateFormat('dd MMM yyyy');
    final deficiencies = state.filteredDeficiencies;
    return _ConvertibleListScaffold(
      tab: PendingActionTab.deficiencies,
      itemCount: deficiencies.length,
      selectedCount: state.selectedDeficiencyIds.length,
      canConvert: canConvert,
      emptyLabel: _emptyText(
          'No pending deficiencies.', 'deficiencies', state.subFilter),
      actionNoun: 'rectification Job Work',
      aboveButton: Row(
        children: [
          Expanded(
            child: Text(
              _onePerDeficiency
                  ? 'One Job Work per deficiency'
                  : 'One Job Work per location (grouped)',
              style: TextStyle(
                  fontSize: 13, color: context.gssms.textSecondary),
            ),
          ),
          Switch(
            key: const Key('rectification_grouping_switch'),
            value: _onePerDeficiency,
            onChanged: (v) => setState(() => _onePerDeficiency = v),
          ),
        ],
      ),
      onConvert: () => ref
          .read(pendingActionsControllerProvider.notifier)
          .convertSelected(
            PendingActionTab.deficiencies,
            onePerDeficiency: _onePerDeficiency,
          ),
      confirmMessage: _onePerDeficiency
          ? 'Create one rectification Job Work for each of the ${state.selectedDeficiencyIds.length} selected deficiencies?'
          : 'Create rectification Job Work(s) for the ${state.selectedDeficiencyIds.length} selected deficiencies, grouped by location?',
      itemBuilder: (context, index) {
        final Deficiency d = deficiencies[index];
        final selected = state.selectedDeficiencyIds.contains(d.id);
        final statusColor = _deficiencyStatusColor(context, d.status);
        // With a live remedial Job Work the badge tracks it (web's
        // deficiencyStatusKey: remedial status + its assignee); otherwise
        // the deficiency's own status reads exactly as before.
        final statusLabel = d.hasActiveRemedial &&
                (d.activeRemedialWorkOrderStatus?.trim().isNotEmpty ?? false)
            ? pendingActionStatusLabelWithAssignee(
                d.activeRemedialWorkOrderStatus,
                d.activeRemedialWorkOrderAssignedToName,
              )
            : d.status.displayName;
        // Same priority web's `openDeficiency`/"View report" use: the
        // linked Job Work first (there's no mobile "Reports" screen to open
        // a report by work-order id the way web's `/reports?work_order=`
        // does, so this opens the Work Order detail instead — the closest
        // equivalent screen mobile actually has), else the asset.
        final VoidCallback? onTap = d.workOrderId != null
            ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WorkOrderDetailScreen(workOrderId: d.workOrderId!)))
            : d.assetId != null
                ? () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AssetDetailScreen(assetId: d.assetId!)))
                : null;

        return Card(
          key: Key('deficiency_pending_card_${d.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title is the Checkpoint (what was being checked) — the
                  // identifying line — not the Deficiency Finding, which is
                  // an observation/remark *about* that checkpoint and reads
                  // better at the bottom, after the reader already knows
                  // what/where (see the red alert strip below).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (canConvert &&
                          deficiencyBucket(d) == PendingBucket.needsAction)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Checkbox(
                            key: Key(
                                'deficiency_pending_check_${d.id}'),
                            value: selected,
                            visualDensity: VisualDensity.compact,
                            onChanged: (_) => ref
                                .read(pendingActionsControllerProvider
                                    .notifier)
                                .toggleSelection(
                                    PendingActionTab.deficiencies, d.id),
                          ),
                        ),
                      Expanded(
                        child: Text(
                            d.reportCheckpoint ?? d.displayAssetEquipment,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(statusLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (d.workOrderTicket != null) ...[
                    Row(
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 14, color: context.gssms.link),
                        const SizedBox(width: 4),
                        Text(d.workOrderTicket!,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.gssms.link)),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Icon(Icons.build_outlined,
                          size: 14, color: context.gssms.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(d.displayAssetEquipment,
                            style: TextStyle(
                                fontSize: 13, color: context.gssms.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // The actual defect — an alert strip, not a title, and the
                  // only red on the card: it's the one line that genuinely
                  // needs attention, unlike the earlier misuse of red for an
                  // unrelated "optional section" elsewhere in this app.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.gssms.danger.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.gssms.danger.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: context.gssms.danger.foreground),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(d.displayFinding,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.gssms.danger.foreground)),
                        ),
                      ],
                    ),
                  ),
                  if (d.detectedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(dateFormat.format(d.detectedAt!),
                        style: TextStyle(
                            fontSize: 11, color: context.gssms.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
