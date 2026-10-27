import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/supervisor_mandate.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';

/// Supervisor control over which checklist asset groups a PM Job Work will
/// check at technician START. Collapsed until the user opens it, so nothing is
/// fetched for Job Works that never use it.
class PreStartMandatePanel extends ConsumerStatefulWidget {
  const PreStartMandatePanel({super.key, required this.workOrder});

  final WorkOrder workOrder;

  /// Whether the panel applies to [wo] for [s] (mounted by the detail screen).
  static bool isVisibleFor(WorkOrder wo, UserSession? s) =>
      canManagePreStartMandates(s) &&
      wo.isPmWorkOrder &&
      wo.originalScheduleId != null &&
      !wo.isModeExecution &&
      (wo.status == WorkOrderStatus.newOrder ||
          wo.status == WorkOrderStatus.assigned) &&
      wo.linkedRecordId == null;

  @override
  ConsumerState<PreStartMandatePanel> createState() =>
      _PreStartMandatePanelState();
}

class _PreStartMandatePanelState extends ConsumerState<PreStartMandatePanel> {
  bool _opened = false;
  bool _loading = false;
  String? _error;
  String? _notice;
  List<ChecklistGroupPreview> _groups = const [];
  List<SupervisorMandate> _mandates = const [];
  final Map<int, TextEditingController> _reasons = {};
  final Set<int> _saving = {};
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_opened || _loading || _refreshing || _saving.isNotEmpty) return;
      _refreshing = true;
      final before = _mandates;
      try {
        final mandates = await ref.read(workOrderRepositoryProvider)
            .getSupervisorMandates(widget.workOrder.id);
        if (mounted && _saving.isEmpty && identical(_mandates, before)) {
          setState(() => _mandates = mandates);
        }
      } catch (_) {
        // Keep the last confirmed state while offline.
      } finally {
        _refreshing = false;
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final c in _reasons.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _reasonFor(int i) =>
      _reasons.putIfAbsent(i, TextEditingController.new);

  Future<void> _load() async {
    final repo = ref.read(workOrderRepositoryProvider);
    final wo = widget.workOrder;
    setState(() {
      _opened = true;
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await repo.prepareChecklist(wo.id);
      final mode = res.executionMode?.toUpperCase();
      if (mode == 'COMPLAINT' ||
          mode == 'RECTIFICATION' ||
          mode == 'INSPECTION') {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _notice = 'Not applicable to this Job Work.';
        });
        return;
      }
      if (res.recordId != null && !res.preview) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _notice =
              'Checklist lines already exist — the technician has started.';
        });
        return;
      }
      final masterId = res.masterId ?? wo.maintenanceMasterId;
      if (masterId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No checklist is attached to this Job Work.';
        });
        return;
      }
      final results = await Future.wait<Object>([
        repo.getSupervisorMandates(wo.id),
        repo.getMasterChecklistGroups(masterId),
      ]);
      if (!mounted) return;
      setState(() {
        _mandates = results[0] as List<SupervisorMandate>;
        _groups = results[1] as List<ChecklistGroupPreview>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(e);
      });
    }
  }

  bool _matches(SupervisorMandate m, ChecklistGroupPreview g) =>
      m.assetCategoryId == g.assetCategoryId && m.assetName == g.assetName;

  SupervisorMandate? _mandateFor(ChecklistGroupPreview g) {
    for (final m in _mandates) {
      if (_matches(m, g)) return m;
    }
    return null;
  }

  Future<void> _toggle(int index, ChecklistGroupPreview g) async {
    final current = _mandateFor(g);
    final action = current?.action == 'INCLUDE' ? 'EXCLUDE' : 'INCLUDE';
    setState(() => _saving.add(index));
    try {
      final saved =
          await ref.read(workOrderRepositoryProvider).setSupervisorMandate(
                widget.workOrder.id,
                assetCategoryId: g.assetCategoryId,
                assetName: g.assetName,
                action: action,
                reason: _reasonFor(index).text.trim(),
              );
      if (!mounted) return;
      setState(() {
        _saving.remove(index);
        _mandates = [
          for (final m in _mandates)
            if (!_matches(m, g)) m,
          saved,
        ];
        _reasonFor(index).clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(index));
      showGssmsSnackBar(context, userFacingError(e), tone: GssmsTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      key: const Key('pre_start_panel'),
      title: 'Pre-START Checklist Control',
      icon: Icons.shield_outlined,
      children: [
        if (!_opened)
          OutlinedButton(
            key: const Key('pre_start_open'),
            onPressed: _load,
            child: const Text('Review checklist groups'),
          )
        else if (_loading)
          const Padding(
            padding: EdgeInsets.all(GssmsSpacing.s16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _buildError(context)
        else if (_notice != null)
          Text(_notice!, style: Theme.of(context).textTheme.bodyMedium)
        else
          ..._buildGroups(context),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final tokens = context.gssms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error!,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: tokens.danger.foreground),
        ),
        const SizedBox(height: GssmsSpacing.s8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const Key('pre_start_retry'),
            onPressed: _load,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGroups(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.gssms;
    return [
      Text(
        'This PM Job Work has not yet been started by the technician. '
        'Checklist lines will materialize at technician START. '
        'You can skip groups before START.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: GssmsSpacing.s8),
      Text(
        'Groups start unchecked. Check out each group required for this visit.',
        style: theme.textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
      ),
      const SizedBox(height: GssmsSpacing.s12),
      for (var i = 0; i < _groups.length; i++) ...[
        _buildRow(context, i, _groups[i]),
        const SizedBox(height: GssmsSpacing.s8),
      ],
    ];
  }

  Widget _buildRow(BuildContext context, int index, ChecklistGroupPreview g) {
    final theme = Theme.of(context);
    final tokens = context.gssms;
    final mandate = _mandateFor(g);
    final excluded = mandate?.action != 'INCLUDE';
    final saving = _saving.contains(index);
    final enabled = g.canMandate && !saving;
    final subtitle = [
      if (g.assetName.isNotEmpty && g.assetCategoryName != null)
        '(${g.assetName})',
      '${g.itemCount} items',
    ].join(' ');

    final StatusChip badge;
    if (excluded) {
      badge = const StatusChip(
        label: 'Not checked out',
        tone: GssmsTone.danger,
        icon: Icons.block,
      );
    } else if (mandate != null) {
      badge = const StatusChip(
        label: 'Will be checked · pinned by supervisor',
        tone: GssmsTone.success,
        icon: Icons.check_circle_outline,
      );
    } else {
      badge = const StatusChip(
        label: 'Will be checked',
        tone: GssmsTone.success,
        icon: Icons.check_circle_outline,
      );
    }

    return Container(
      key: Key('pre_start_group_$index'),
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(GssmsRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g.title, style: theme.textTheme.titleSmall),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: GssmsSpacing.s8),
          Align(alignment: Alignment.centerLeft, child: badge),
          if (mandate != null && mandate.reason.isNotEmpty) ...[
            const SizedBox(height: GssmsSpacing.s4),
            Text('Reason: ${mandate.reason}', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: GssmsSpacing.s8),
          TextField(
            controller: _reasonFor(index),
            enabled: enabled,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              isDense: true,
            ),
          ),
          const SizedBox(height: GssmsSpacing.s8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: enabled ? () => _toggle(index, g) : null,
              child:
                  Text(excluded ? 'Check out this group' : 'Un-check this group'),
            ),
          ),
          if (!g.canMandate) ...[
            const SizedBox(height: GssmsSpacing.s4),
            Text(
              '(Uncategorized items cannot be mandated individually)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
