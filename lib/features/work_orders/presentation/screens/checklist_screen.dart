import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
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
  /// Replaced asset/component details captured from the overflow menu. There
  /// is no API field for them, so they are carried into the closing remarks
  /// (an existing `complete` field) instead of being discarded.
  final List<String> _replacementNotes = [];

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
        // Never claim completion that has only reached this device (SSOT §41).
        showGssmsSnackBar(
          context,
          next.queued
              ? 'Completion saved on this device. It will be submitted for '
                  'verification when a connection is available.'
              : 'Submitted for verification.',
          tone: next.queued ? GssmsTone.warning : GssmsTone.success,
          duration: Duration(seconds: next.queued ? 6 : 4),
        );
        Navigator.of(context).pop();
      } else if (next is ChecklistLoaded && next.errorMessage != null) {
        showGssmsSnackBar(context, next.errorMessage!, tone: GssmsTone.danger);
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
      return const SingleChildScrollView(child: SkeletonList(itemCount: 4));
    }

    if (state is ChecklistError) {
      return EmptyStateView.error(
        title: 'Could not load the checklist',
        message: state.message,
        onRetry: () => ref
            .read(checklistControllerProvider(widget.recordId).notifier)
            .loadRecord(),
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
                      ? context.gssms.success.solid
                      : context.gssms.accent.solid,
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
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView.noResults(
                title: 'No checklist items in this subsystem',
                icon: Icons.checklist,
                onClearFilters: () => ref
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .setActiveSubCategory(null),
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

    return const SingleChildScrollView(child: SkeletonList(itemCount: 4));
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
      itemBuilder: (context) {
        final tokens = context.gssms;
        PopupMenuItem<String> item(
            String value, IconData icon, Color color, String label) {
          return PopupMenuItem(
            value: value,
            child: Row(
              children: [
                Icon(icon, color: color, size: GssmsSize.iconMd),
                const SizedBox(width: GssmsSpacing.s12),
                Text(label),
              ],
            ),
          );
        }

        return [
          item('asset', Icons.autorenew, tokens.danger.foreground,
              'Enter Replaced Asset'),
          item('component', Icons.build_circle_outlined,
              tokens.accent.foreground, 'Enter Replaced Component'),
          item('preview', Icons.remove_red_eye_outlined, tokens.link, 'Preview'),
        ];
      },
    );
  }

  Future<void> _showReplacedAssetSheet() async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ReplacedAssetSheet(),
    );
    _addReplacementNote(note);
  }

  Future<void> _showReplacedComponentSheet() async {
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ReplacedComponentSheet(),
    );
    _addReplacementNote(note);
  }

  void _addReplacementNote(String? note) {
    if (note == null || note.trim().isEmpty || !mounted) return;
    setState(() => _replacementNotes.add(note.trim()));
    showGssmsSnackBar(
      context,
      'Added to your closing remarks. Review them when you sign and submit.',
      tone: GssmsTone.success,
    );
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
      builder: (ctx) => _CompletionSheet(
        recordId: widget.recordId,
        replacementNotes: List.unmodifiable(_replacementNotes),
      ),
    ));
  }
}

/// Subsystem filter as a dropdown rather than a wrapping row of ChoiceChips
/// — same reasoning as the list screens' status/type/category dropdowns: a
/// chip Wrap grows to N rows for N subsystems (a multi-panel station easily
/// has 5+), eating a variable, unpredictable amount of the pinned header's
/// height above the checklist itself. A dropdown is always exactly one row.
/// Stays a *pinned* sliver header (unlike the list screens' filters, which
/// scroll away with their content) — a technician re-checks/changes this
/// filter continuously while working through a long checklist, so keeping
/// it reachable without scrolling back up is the right call here.
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

  static const double _height = 64.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      alignment: Alignment.center,
      child: DropdownButtonFormField<String?>(
        key: const Key('checklist_subsystem_filter_dropdown'),
        isExpanded: true,
        value: activeCategory,
        decoration: const InputDecoration(
          labelText: 'Subsystem',
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<String?>(
              value: null, child: Text('All Subsystems ($totalLines)')),
          for (final cat in categories)
            DropdownMenuItem(
                value: cat,
                child: Text('$cat (${lineCounts[cat] ?? 0})',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
        ],
        onChanged: onSelected,
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
  const _CompletionSheet({
    required this.recordId,
    this.replacementNotes = const [],
  });

  final int recordId;

  /// Replaced asset/component notes, pre-filled into the closing remarks.
  final List<String> replacementNotes;

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
    if (widget.replacementNotes.isNotEmpty) {
      _remarksController.text = widget.replacementNotes.join('\n');
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
        showGssmsSnackBar(
          context,
          'That photo is over the 5 MB limit. Try again.',
          tone: GssmsTone.danger,
        );
        return;
      }
      if (file != null) setState(() => _proof = file);
    } catch (e) {
      if (!mounted) return;
      showGssmsSnackBar(
        context,
        'Could not capture photo. ${userFacingError(e)}',
        tone: GssmsTone.danger,
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checklistControllerProvider(widget.recordId));
    final isSubmitting = state is ChecklistLoaded && state.isSubmitting;
    final outstanding = state is ChecklistLoaded ? state.remainingRequired : 0;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.gssms;

    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sign & Submit', style: textTheme.titleLarge),
              const SizedBox(height: GssmsSpacing.s4),
              Text(
                'Submits this maintenance execution to the depot incharge for '
                'verification. Checklist readings cannot be changed afterwards.',
                style: textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              if (outstanding > 0) ...[
                const SizedBox(height: GssmsSpacing.s12),
                _SheetNotice(
                  tone: GssmsTone.warning,
                  icon: Icons.warning_amber_rounded,
                  text: '$outstanding required '
                      '${outstanding == 1 ? 'line is' : 'lines are'} still '
                      'unrecorded. The server will reject completion until '
                      'every required line is submitted.',
                ),
              ],
              const SizedBox(height: GssmsSpacing.s16),
              _buildProofField(),
              const SizedBox(height: GssmsSpacing.s16),
              TextFormField(
                key: const Key('completion_technician_field'),
                controller: _technicianController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Technician Name *',
                  isDense: true,
                ),
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Enter the technician name'
                    : null,
              ),
              const SizedBox(height: GssmsSpacing.s12),
              TextFormField(
                key: const Key('completion_other_staff_field'),
                controller: _otherStaffController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Other Staff Involved (optional)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: GssmsSpacing.s12),
              TextFormField(
                key: const Key('completion_remarks_field'),
                controller: _remarksController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Technician Closing Remarks *',
                  helperText: 'At least 10 characters',
                ),
                minLines: 3,
                maxLines: 6,
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.length < ChecklistController.minCompletionRemarksLength) {
                    return 'Remarks must be at least '
                        '${ChecklistController.minCompletionRemarksLength} characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: GssmsSpacing.s8),
              CheckboxListTile(
                key: const Key('completion_checked_out_checkbox'),
                value: _checkedOutBySupervisor,
                onChanged: (val) {
                  if (val != null) setState(() => _checkedOutBySupervisor = val);
                },
                title: Text(
                  'Checked out by supervisor',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: GssmsSpacing.s16),
              SizedBox(
                height: GssmsSize.primaryAction,
                child: FilledButton.icon(
                  key: const Key('completion_confirm_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.success.solid,
                    foregroundColor: tokens.success.onSolid,
                  ),
                  onPressed: isSubmitting ? null : _submit,
                  icon: isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: Text(isSubmitting ? 'Submitting…' : 'Confirm & Submit'),
                ),
              ),
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
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
    final tokens = context.gssms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Proof of Execution', style: textTheme.titleMedium),
        const SizedBox(height: GssmsSpacing.s4),
        Text(
          'Attach a clear photo of the serviced asset or final reading (max 5 MB).',
          style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: GssmsSpacing.s8),
        if (proof != null)
          Container(
            padding: const EdgeInsets.all(GssmsSpacing.s8),
            decoration: BoxDecoration(
              color: tokens.success.background,
              border: Border.all(color: tokens.success.border),
              borderRadius: BorderRadius.circular(GssmsRadius.r8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: tokens.success.foreground),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proof.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${(proof.sizeBytes / 1024).toStringAsFixed(1)} KB',
                        style: textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove photo',
                  onPressed: () => setState(() => _proof = null),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('completion_take_photo'),
                  onPressed: _capturing ? null : () => _capture(ImageSource.camera),
                  icon: _capturing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Take Photo'),
                ),
              ),
              const SizedBox(width: GssmsSpacing.s8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('completion_pick_photo'),
                  onPressed: _capturing ? null : () => _capture(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                ),
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

/// Shared chrome for the checklist's bottom sheets: icon + title + close,
/// keyboard-safe padding, scrollable body.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s8,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: GssmsSpacing.s8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SheetNotice extends StatelessWidget {
  const _SheetNotice({required this.tone, required this.icon, required this.text});

  final GssmsTone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.tone(tone);
    return Container(
      padding: const EdgeInsets.all(GssmsSpacing.s12),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(GssmsRadius.r8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.foreground),
          const SizedBox(width: GssmsSpacing.s8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collects replaced-asset details and pops with a remarks line. There is no
/// replaced-asset API field, so the text travels in the closing remarks
/// rather than being thrown away.
class _ReplacedAssetSheet extends StatefulWidget {
  const _ReplacedAssetSheet();

  @override
  State<_ReplacedAssetSheet> createState() => _ReplacedAssetSheetState();
}

class _ReplacedAssetSheetState extends State<_ReplacedAssetSheet> {
  final _formKey = GlobalKey<FormState>();
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

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final oldSerial = _oldSerialController.text.trim();
    final reason = _reasonController.text.trim();
    final note = [
      'Replaced asset: ${_assetNameController.text.trim()}',
      if (oldSerial.isNotEmpty) 'old $oldSerial',
      'new ${_newSerialController.text.trim()}',
      if (reason.isNotEmpty) 'reason: $reason',
    ].join(', ');
    Navigator.of(context).pop('$note.');
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    return Form(
      key: _formKey,
      child: _SheetScaffold(
        icon: Icons.autorenew,
        iconColor: context.gssms.danger.foreground,
        title: 'Enter Replaced Asset',
        children: [
          const _SheetNotice(
            tone: GssmsTone.info,
            icon: Icons.info_outline,
            text: 'These details are added to your closing remarks so the '
                'supervisor sees them when verifying.',
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _assetNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Asset Name / Tag *', isDense: true),
            validator: required,
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _oldSerialController,
            textInputAction: TextInputAction.next,
            decoration:
                const InputDecoration(labelText: 'Old Serial / Asset Code', isDense: true),
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _newSerialController,
            textInputAction: TextInputAction.next,
            decoration:
                const InputDecoration(labelText: 'New Serial / Asset Code *', isDense: true),
            validator: required,
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _reasonController,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                const InputDecoration(labelText: 'Reason for Replacement', isDense: true),
            maxLines: 2,
          ),
          const SizedBox(height: GssmsSpacing.s16),
          SizedBox(
            height: GssmsSize.touchTarget,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Add to Closing Remarks'),
            ),
          ),
        ],
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
  final _formKey = GlobalKey<FormState>();
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

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final part = _partNumberController.text.trim();
    final details = _remarksController.text.trim();
    final note = [
      'Replaced component: ${_componentNameController.text.trim()}',
      if (part.isNotEmpty) 'part $part',
      'qty ${int.parse(_quantityController.text.trim())}',
      if (details.isNotEmpty) details,
    ].join(', ');
    Navigator.of(context).pop('$note.');
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: _SheetScaffold(
        icon: Icons.build_circle_outlined,
        iconColor: context.gssms.accent.foreground,
        title: 'Enter Replaced Component',
        children: [
          const _SheetNotice(
            tone: GssmsTone.info,
            icon: Icons.info_outline,
            text: 'These details are added to your closing remarks so the '
                'supervisor sees them when verifying.',
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _componentNameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Component Name *', isDense: true),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _partNumberController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Part / Spec Number', isDense: true),
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Quantity Replaced *', isDense: true),
            validator: (v) {
              final qty = int.tryParse(v?.trim() ?? '');
              return (qty == null || qty <= 0) ? 'Enter 1 or more' : null;
            },
          ),
          const SizedBox(height: GssmsSpacing.s12),
          TextFormField(
            controller: _remarksController,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                const InputDecoration(labelText: 'Remarks / Action Details', isDense: true),
            maxLines: 2,
          ),
          const SizedBox(height: GssmsSpacing.s16),
          SizedBox(
            height: GssmsSize.touchTarget,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Add to Closing Remarks'),
            ),
          ),
        ],
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
    final tokens = context.gssms;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.remove_red_eye_outlined, color: tokens.link),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: Text('Checklist Summary Preview', style: textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Container(
              padding: const EdgeInsets.all(GssmsSpacing.s12),
              decoration: BoxDecoration(
                color: tokens.surfaceInset,
                borderRadius: BorderRadius.circular(GssmsRadius.r8),
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
                    style: textTheme.labelLarge?.copyWith(color: tokens.link),
                  ),
                ],
              ),
            ),
            const SizedBox(height: GssmsSpacing.s12),
            Expanded(
              child: ListView.separated(
                itemCount: record.activeLines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, idx) {
                  final line = record.activeLines[idx];
                  return ListTile(
                    dense: true,
                    title: Text(line.displayTitle, style: textTheme.titleSmall),
                    subtitle: Text(
                      line.valueType.isMultiPart
                          ? 'Readings: ${line.componentValues.entries.map((e) => "${e.key}: ${e.value}").join(", ")}'
                          : 'Status: ${line.status} ${line.scalarValue.isNotEmpty ? "(${line.scalarValue})" : ""}',
                      style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                    ),
                    trailing: Icon(
                      line.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: line.isCompleted
                          ? tokens.success.foreground
                          : tokens.textTertiary,
                      size: GssmsSize.iconMd,
                      semanticLabel: line.isCompleted ? 'Recorded' : 'Not recorded',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
