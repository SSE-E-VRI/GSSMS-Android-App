import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_action_bar.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_header.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key, required this.recordId});

  final int recordId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!canWriteChecklist(
          sessionFromAuth(ref.read(authControllerProvider)))) {
        return;
      }
      ref.read(checklistControllerProvider(widget.recordId).notifier).loadRecord();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!canWriteChecklist(sessionOf(ref))) {
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Checklist'),
              Text(
                '#${widget.recordId}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
          ),
        ),
        body: const PermissionDeniedView(),
      );
    }

    final state = ref.watch(checklistControllerProvider(widget.recordId));

    ref.listen(checklistControllerProvider(widget.recordId), (prev, next) {
      if (next is ChecklistCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maintenance execution completed successfully!'),
            backgroundColor: AppTheme.railwayGreen,
          ),
        );
        Navigator.of(context).pop();
      } else if (next is ChecklistLoaded && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    });

    // After any outbox drain settles, reconcile queued photo placeholders
    // with server truth (uploaded rows replace placeholders; failures
    // surface on the thumbnails). A full reload would lose scroll/focus.
    ref.listen(
      syncManagerProvider.select((s) => s.lastSyncTime),
      (prev, next) {
        if (!mounted) return;
        if (prev != null && next != null && next.isAfter(prev)) {
          unawaited(ref
              .read(checklistControllerProvider(widget.recordId).notifier)
              .reconcileAttachmentSyncState());
        }
      },
    );

    return Scaffold(
      appBar: state is ChecklistLoaded
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Checklist'),
                  Text(
                    '#${widget.recordId}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
      body: _buildBody(state),
      bottomNavigationBar: state is ChecklistLoaded
          ? ChecklistActionBar(
              state: state,
              onSignAndSubmit: _showCompletionDialog,
            )
          : null,
    );
  }

  Widget _buildBody(ChecklistState state) {
    if (state is ChecklistLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is ChecklistError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(
                state.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .loadRecord(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is ChecklistLoaded) {
      final record = state.record;
      final lines = state.displayedLines;
      final categories = state.subCategories;

      return CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            actions: [
              _buildOverflowMenu(state),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: record.progress,
                  backgroundColor: Colors.white24,
                  color: record.progress == 1.0
                      ? AppTheme.railwayGreen
                      : AppTheme.accentOrange,
                ),
              ),
            ),
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final top = constraints.biggest.height;
                final isCollapsed = top <=
                    (kToolbarHeight + MediaQuery.of(context).padding.top + 24);
                return FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: ChecklistHeader(record: record),
                  titlePadding: const EdgeInsetsDirectional.only(
                    start: 56,
                    bottom: 10,
                    end: 48,
                  ),
                  title: isCollapsed
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${record.stationName ?? 'Station'} · ${record.templateName ?? 'Schedule'} · ${(record.progress * 100).toInt()}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${record.completedLines} of ${record.totalLines}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
          if (categories.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _SubsystemChipsDelegate(
                categories: categories,
                activeCategory: state.activeSubCategory,
                totalLines: record.activeLines.length,
                lineCounts: {
                  for (final cat in categories)
                    cat: record.activeLines
                        .where((l) => l.assetCategory == cat)
                        .length,
                },
                onSelected: (cat) => ref
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .setActiveSubCategory(cat),
              ),
            ),
          if (lines.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('No checklist items in this category.'),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ChecklistLineCard(
                        key: ValueKey(lines[index].id),
                        line: lines[index],
                        recordId: widget.recordId,
                        isPastTechCompleted: state.record.isPastTechCompleted,
                        onSave: (edit) {
                          unawaited(ref
                              .read(checklistControllerProvider(widget.recordId).notifier)
                              .submitLineObservation(
                                lineId: lines[index].id,
                                value: edit.value,
                                status: edit.status,
                                statusOptionId: edit.statusOptionId,
                                actionOptionId: edit.actionOptionId,
                                remarks: edit.remarks,
                              ));
                        },
                      ),
                    );
                  },
                  childCount: lines.length,
                ),
              ),
            ),
        ],
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildOverflowMenu(ChecklistLoaded state) {
    return PopupMenuButton<String>(
      key: const Key('checklist_overflow_menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'asset':
            _showReplacedAssetSheet();
            break;
          case 'component':
            _showReplacedComponentSheet();
            break;
          case 'preview':
            _showPreviewSheet(state);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'asset',
          child: Row(
            children: [
              Icon(Icons.autorenew, color: AppTheme.errorRed, size: 20),
              SizedBox(width: 12),
              Text('Enter Replaced Asset'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'component',
          child: Row(
            children: [
              Icon(Icons.build_circle_outlined, color: AppTheme.statusHigh, size: 20),
              SizedBox(width: 12),
              Text('Enter Replaced Component'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'preview',
          child: Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, color: AppTheme.primaryBlue, size: 20),
              SizedBox(width: 12),
              Text('Preview'),
            ],
          ),
        ),
      ],
    );
  }

  void _showReplacedAssetSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ReplacedAssetSheet(),
    ));
  }

  void _showReplacedComponentSheet() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ReplacedComponentSheet(),
    ));
  }

  void _showPreviewSheet(ChecklistLoaded state) {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PreviewSheet(record: state.record),
    ));
  }

  /// Finalisation sheet: proof photo, technician signature and closing remarks.
  void _showCompletionDialog() {
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CompletionSheet(recordId: widget.recordId),
    ));
  }
}

class _SubsystemChipsDelegate extends SliverPersistentHeaderDelegate {
  _SubsystemChipsDelegate({
    required this.categories,
    required this.activeCategory,
    required this.lineCounts,
    required this.totalLines,
    required this.onSelected,
  });

  final List<String> categories;
  final String? activeCategory;
  final Map<String, int> lineCounts;
  final int totalLines;
  final ValueChanged<String?> onSelected;

  @override
  double get minExtent => _calculateHeight();

  @override
  double get maxExtent => _calculateHeight();

  double _calculateHeight() {
    final totalChips = categories.length + 1;
    if (totalChips <= 3) return 48.0;
    final rows = (totalChips / 3.0).ceil();
    return rows * 42.0 + 8.0;
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text('All Subsystems ($totalLines)'),
            selected: activeCategory == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final cat in categories)
            ChoiceChip(
              label: Text('$cat (${lineCounts[cat] ?? 0})'),
              selected: activeCategory == cat,
              onSelected: (_) => onSelected(cat),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SubsystemChipsDelegate oldDelegate) {
    return oldDelegate.categories != categories ||
        oldDelegate.activeCategory != activeCategory ||
        oldDelegate.totalLines != totalLines;
  }
}

class _CompletionSheet extends ConsumerStatefulWidget {
  const _CompletionSheet({required this.recordId});

  final int recordId;

  @override
  ConsumerState<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends ConsumerState<_CompletionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _remarksController = TextEditingController();
  final _technicianController = TextEditingController();
  final _otherStaffController = TextEditingController();

  EvidenceFile? _proof;
  bool _capturing = false;
  bool _checkedOutBySupervisor = true;

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authControllerProvider);
    if (authState is Authenticated) {
      _technicianController.text = authState.session.displayName;
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _technicianController.dispose();
    _otherStaffController.dispose();
    super.dispose();
  }

  Future<void> _capture(ImageSource source) async {
    setState(() => _capturing = true);
    try {
      final file = await ref
          .read(evidenceServiceProvider)
          .capture(kind: EvidenceKind.proof, source: source);
      if (!mounted) return;
      if (file != null && !file.isWithinSizeLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('That photo is over the 5 MB limit. Try again.'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
        return;
      }
      if (file != null) setState(() => _proof = file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not capture photo: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checklistControllerProvider(widget.recordId));
    final isSubmitting = state is ChecklistLoaded && state.isSubmitting;
    final outstanding =
        state is ChecklistLoaded ? state.remainingRequired : 0;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Finalize Execution',
                style: textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Submit this maintenance execution for supervisor verification.',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              if (outstanding > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.warningAmber.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 18, color: AppTheme.warningAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$outstanding required line(s) still unrecorded. The server will '
                          'reject completion until every required line is submitted.',
                          style: textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildProofField(),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('completion_technician_field'),
                controller: _technicianController,
                decoration: const InputDecoration(
                  labelText: 'Technician Name *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Enter the technician name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('completion_other_staff_field'),
                controller: _otherStaffController,
                decoration: const InputDecoration(
                  labelText: 'Other Staff Involved (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('completion_remarks_field'),
                controller: _remarksController,
                decoration: const InputDecoration(
                  labelText: 'Technician Closing Remarks *',
                  helperText: 'At least 10 characters',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.length < ChecklistController.minCompletionRemarksLength) {
                    return 'Remarks must be at least '
                        '${ChecklistController.minCompletionRemarksLength} characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                key: const Key('completion_checked_out_checkbox'),
                value: _checkedOutBySupervisor,
                onChanged: (val) {
                  if (val != null) setState(() => _checkedOutBySupervisor = val);
                },
                title: Text(
                  'Checked out by supervisor',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    key: const Key('completion_confirm_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.railwayGreen,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: isSubmitting ? null : _submit,
                    child: isSubmitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Confirm Completion'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProofField() {
    final proof = _proof;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proof of Execution',
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Attach a clear photo of the serviced asset or final reading (max 5 MB).',
          style: textTheme.labelSmall?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        if (proof != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderGrey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.railwayGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proof.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        '${(proof.sizeBytes / 1024).toStringAsFixed(1)} KB',
                        style: textTheme.labelSmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => setState(() => _proof = null),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('completion_take_photo'),
                onPressed: _capturing ? null : () => _capture(ImageSource.camera),
                icon: _capturing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Take Photo'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('completion_pick_photo'),
                onPressed: _capturing ? null : () => _capture(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Gallery'),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!canWriteChecklist(sessionOf(ref))) {
      if (mounted) {
        showPermissionDeniedSnackBar(context);
      }
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final otherStaff = _otherStaffController.text.trim();
    final ok = await ref
        .read(checklistControllerProvider(widget.recordId).notifier)
        .completeExecution(
          technicianName: _technicianController.text.trim(),
          remarks: _remarksController.text.trim(),
          proofJpegPath: _proof?.path,
          otherStaff: otherStaff.isEmpty ? null : otherStaff,
        );

    if (ok && mounted) Navigator.of(context).pop();
  }
}

class _ReplacedAssetSheet extends StatefulWidget {
  const _ReplacedAssetSheet();

  @override
  State<_ReplacedAssetSheet> createState() => _ReplacedAssetSheetState();
}

class _ReplacedAssetSheetState extends State<_ReplacedAssetSheet> {
  final _assetNameController = TextEditingController();
  final _oldSerialController = TextEditingController();
  final _newSerialController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _assetNameController.dispose();
    _oldSerialController.dispose();
    _newSerialController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.autorenew, color: AppTheme.errorRed),
                const SizedBox(width: 8),
                Text(
                  'Enter Replaced Asset',
                  style: textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _assetNameController,
              decoration: const InputDecoration(
                labelText: 'Asset Name / Tag *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _oldSerialController,
              decoration: const InputDecoration(
                labelText: 'Old Serial / Asset Code',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newSerialController,
              decoration: const InputDecoration(
                labelText: 'New Serial / Asset Code *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for Replacement',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  if (_assetNameController.text.trim().isEmpty ||
                      _newSerialController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the asset name and the new serial / asset code.'),
                        backgroundColor: AppTheme.errorRed,
                      ),
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Noted locally — include these details in your closing remarks for the supervisor.'),
                      backgroundColor: AppTheme.railwayGreen,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Record Replaced Asset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplacedComponentSheet extends StatefulWidget {
  const _ReplacedComponentSheet();

  @override
  State<_ReplacedComponentSheet> createState() => _ReplacedComponentSheetState();
}

class _ReplacedComponentSheetState extends State<_ReplacedComponentSheet> {
  final _componentNameController = TextEditingController();
  final _partNumberController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _remarksController = TextEditingController();

  @override
  void dispose() {
    _componentNameController.dispose();
    _partNumberController.dispose();
    _quantityController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, color: AppTheme.statusHigh),
                const SizedBox(width: 8),
                Text(
                  'Enter Replaced Component',
                  style: textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _componentNameController,
              decoration: const InputDecoration(
                labelText: 'Component Name *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _partNumberController,
              decoration: const InputDecoration(
                labelText: 'Part / Spec Number',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity Replaced',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _remarksController,
              decoration: const InputDecoration(
                labelText: 'Remarks / Action Details',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.statusHigh,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  if (_componentNameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the component name.'),
                        backgroundColor: AppTheme.errorRed,
                      ),
                    );
                    return;
                  }
                  final qty = int.tryParse(_quantityController.text.trim());
                  if (qty == null || qty <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter a valid quantity (1 or more).'),
                        backgroundColor: AppTheme.errorRed,
                      ),
                    );
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Noted locally — include these details in your closing remarks for the supervisor.'),
                      backgroundColor: AppTheme.railwayGreen,
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Record Replaced Component'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({required this.record});

  final MaintenanceRecord record;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Text(
                'Checklist Summary Preview',
                style: textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryDark.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Completed: ${record.completedLines}/${record.totalLines}',
                  style: textTheme.labelLarge,
                ),
                Text(
                  'Progress: ${(record.progress * 100).toInt()}%',
                  style: textTheme.labelLarge?.copyWith(color: AppTheme.railwayBlue),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: record.activeLines.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final line = record.activeLines[idx];
                return ListTile(
                  dense: true,
                  title: Text(
                    line.displayTitle,
                    style: textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    line.valueType.isMultiPart
                        ? 'Readings: ${line.componentValues.entries.map((e) => "${e.key}: ${e.value}").join(", ")}'
                        : 'Status: ${line.status} ${line.scalarValue.isNotEmpty ? "(${line.scalarValue})" : ""}',
                    style: textTheme.labelSmall,
                  ),
                  trailing: Icon(
                    line.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: line.isCompleted ? AppTheme.railwayGreen : AppTheme.borderGrey,
                    size: 18,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
