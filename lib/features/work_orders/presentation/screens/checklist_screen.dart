import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/utils/numbered_list.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/repeatable_text_list.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_action_bar.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_group_header.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_header.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/checklist_line_card.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/group_evidence_strip.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/replace_asset_sheet.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/replace_component_sheet.dart';

class ChecklistScreen extends ConsumerStatefulWidget {
  const ChecklistScreen({super.key, required this.recordId});

  final int recordId;

  @override
  ConsumerState<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends ConsumerState<ChecklistScreen> {
  /// Scroll targets for line cards, by line id.
  final Map<int, GlobalKey> _lineScrollKeys = {};

  /// Currently highlighted (jumped-to) line id, cleared after a few seconds.
  int? _highlightedLineId;
  int _highlightSeq = 0;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _highlightLine(int lineId) {
    _highlightTimer?.cancel();
    final seq = ++_highlightSeq;
    setState(() {
      _highlightedLineId = lineId;
    });
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _highlightSeq != seq) return;
      setState(() {
        _highlightedLineId = null;
      });
    });
  }

  void _jumpToIncompleteLine(ChecklistLoaded state) {
    final targetLine = state.firstIncompleteRequiredLine;
    if (targetLine == null) return;

    final remaining = state.remainingRequired;
    showGssmsSnackBar(
      context,
      'Complete the highlighted item first ($remaining left).',
      tone: GssmsTone.warning,
    );

    final isHidden = state.activeSubCategory != null &&
        !state.displayedGroups
            .any((g) => g.lines.any((l) => l.id == targetLine.id));

    if (isHidden) {
      ref
          .read(checklistControllerProvider(widget.recordId).notifier)
          .setActiveSubCategory(null);
    }

    _highlightLine(targetLine.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keyContext = _lineScrollKeys[targetLine.id]?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.1,
        );
      }
    });
  }

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
      if (!context.mounted) return;
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
              onIncompleteTap: () => _jumpToIncompleteLine(state),
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
      final groups = state.displayedGroups;
      final allGroups = record.assetGroups;
      final categories = state.subCategories;
      final session = sessionOf(ref);
      final canCheckOut = canWriteChecklist(session);
      final canUncheck = canUncheckoutGroup(session);

      return CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.stationName ?? 'Station'} · ${record.templateName ?? 'Schedule'} · ${(record.progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${record.completedLines} of ${record.totalLines}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
            ),
            actions: [
              _buildOverflowMenu(state),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(6),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: record.progress,
                  backgroundColor: Colors.white30,
                  color: record.progress == 1.0
                      ? context.gssms.success.solid
                      : context.gssms.accent.solid,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: ChecklistHeader(record: record)),
          if (categories.isNotEmpty)
            SliverPersistentHeader(
              pinned: true,
              delegate: _SubsystemChipsDelegate(
                categories: categories,
                activeCategory: state.activeSubCategory,
                totalLines: allGroups.length,
                lineCounts: {
                  for (final cat in categories)
                    cat: allGroups
                        .where((g) => g.categoryLabel == cat)
                        .length,
                },
                onSelected: (cat) => ref
                    .read(checklistControllerProvider(widget.recordId).notifier)
                    .setActiveSubCategory(cat),
              ),
            ),
          if (groups.isEmpty)
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
                    final group = groups[index];
                    final activeLines =
                        group.lines.where((l) => !l.excluded).toList();
                    // Records from before group check-out existed carry no
                    // `checked_out`: show their lines flat, as they always were.
                    final legacy =
                        group.lines.every((l) => l.checkedOut == null);
                    return Padding(
                      padding: EdgeInsets.only(bottom: legacy ? 12 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (legacy)
                            for (final line in activeLines)
                              Padding(
                                padding: EdgeInsets.only(
                                    top: line == activeLines.first ? 0 : 12),
                                child: _lineCard(line, record, showAttachments: true),
                              )
                          else ...[
                          ChecklistGroupHeader(
                            group: group,
                            canCheckOut: canCheckOut,
                            canUncheck: canUncheck,
                            saving: state.savingGroupKeys.contains(group.key),
                            isPastTechCompleted: record.isPastTechCompleted,
                            onToggle: (included) =>
                                _toggleGroup(group, included),
                          ),
                          if (group.checkedOut) ...[
                            const SizedBox(height: GssmsSpacing.s8),
                            GroupEvidenceStrip(
                              recordId: widget.recordId,
                              holder: group.photoHolder,
                              isPastTechCompleted: record.isPastTechCompleted,
                            ),
                            for (final line in activeLines)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _lineCard(line, record,
                                    showAttachments: false),
                              ),
                          ],
                          ],
                        ],
                      ),
                    );
                  },
                  childCount: groups.length,
                ),
              ),
            ),
        ],
      );
    }

    return const SingleChildScrollView(child: SkeletonList(itemCount: 4));
  }

  Widget _lineCard(MaintenanceRecordLine line, MaintenanceRecord record,
      {required bool showAttachments}) {
    final scrollKey = _lineScrollKeys.putIfAbsent(line.id, () => GlobalKey());
    return KeyedSubtree(
      key: scrollKey,
      child: ChecklistLineCard(
        key: ValueKey(line.id),
        line: line,
        isHighlighted: _highlightedLineId == line.id,
        recordId: widget.recordId,
        showAttachments: showAttachments,
        isPastTechCompleted: record.isPastTechCompleted,
        onSave: (edit) {
          unawaited(ref
              .read(checklistControllerProvider(widget.recordId).notifier)
              .submitLineObservation(
                lineId: line.id,
                value: edit.value,
                status: edit.status,
                statusOptionId: edit.statusOptionId,
                actionOptionId: edit.actionOptionId,
                remarks: edit.remarks,
              ));
        },
      ),
    );
  }

  /// Checks a group out or un-checks it. Un-check is confirmed first, and the
  /// server may ask for a reason (retry with it).
  Future<void> _toggleGroup(ChecklistAssetGroup group, bool included) async {
    final controller =
        ref.read(checklistControllerProvider(widget.recordId).notifier);
    if (!included) {
      final confirmed = await showConfirmationDialog(
        context,
        title: 'Un-check this asset group?',
        message: 'Its checklist lines are removed from this record.',
        confirmLabel: 'Un-check',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }

    var ok = await controller.setGroupIncluded(group, included);
    if (!ok && !included && controller.groupReasonRequired && mounted) {
      final reason = await _askReason();
      if (reason == null || !mounted) return;
      ok = await controller.setGroupIncluded(group, included, reason: reason);
    }
    if (!mounted || !ok) return;
    final latest =
        ref.read(checklistControllerProvider(widget.recordId));
    if (latest is ChecklistLoaded && latest.successMessage != null) {
      showGssmsSnackBar(context, latest.successMessage!,
          tone: GssmsTone.success);
    }
  }

  Future<String?> _askReason() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => const _ReasonDialog(),
    );
  }

  Widget _buildOverflowMenu(ChecklistLoaded state) {
    final session = sessionOf(ref);
    final allowReplace = ReplacementJobWork.fromRecord(state.record) != null &&
        !state.record.isReplacementLocked;
    return PopupMenuButton<String>(
      key: const Key('checklist_overflow_menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'asset':
            _openReplaceAsset(state);
            break;
          case 'component':
            _openReplaceComponent(state);
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
                Flexible(child: Text(label)),
              ],
            ),
          );
        }

        return [
          if (allowReplace && canReplaceWholeAsset(session))
            item('asset', Icons.autorenew, tokens.danger.foreground,
                'Enter Replaced Asset'),
          if (allowReplace && canReplaceAssets(session))
            item('component', Icons.build_circle_outlined,
                tokens.accent.foreground, 'Enter Replaced Component'),
          item('preview', Icons.remove_red_eye_outlined, tokens.link, 'Preview'),
        ];
      },
    );
  }

  Future<void> _openReplaceAsset(ChecklistLoaded state) async {
    final jobWork = ReplacementJobWork.fromRecord(state.record);
    if (jobWork == null) return;
    final ok = await showReplaceAssetSheet(context, ref, jobWork);
    if (ok == true && mounted) {
      showGssmsSnackBar(context, 'Asset replaced successfully!',
          tone: GssmsTone.success);
    }
  }

  Future<void> _openReplaceComponent(ChecklistLoaded state) async {
    final jobWork = ReplacementJobWork.fromRecord(state.record);
    if (jobWork == null) return;
    final ok = await showReplaceComponentSheet(context, ref, jobWork);
    if (ok == true && mounted) {
      showGssmsSnackBar(context, 'Component replacement recorded!',
          tone: GssmsTone.success);
    }
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
  const _CompletionSheet({required this.recordId});

  final int recordId;

  @override
  ConsumerState<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends ConsumerState<_CompletionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _remarksKey = GlobalKey<RepeatableTextListState>();
  late final List<String> _initialRemarks;
  String? _remarksError;
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
    final current = ref.read(checklistControllerProvider(widget.recordId));
    _initialRemarks = [
      if (current is ChecklistLoaded) ...splitNumberedList(current.record.remarks),
    ];
  }

  @override
  void dispose() {
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
              RepeatableTextList(
                key: _remarksKey,
                keyPrefix: 'completion_remarks',
                label: 'Technician Remarks *',
                hint: 'Add a remark',
                initial: _initialRemarks,
                errorText: _remarksError,
                onChanged: (_) {
                  if (_remarksError != null) {
                    setState(() => _remarksError = null);
                  }
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
    if (!canWriteChecklist(sessionFromAuth(ref.read(authControllerProvider)))) {
      if (mounted) {
        showPermissionDeniedSnackBar(context);
      }
      return;
    }
    final formOk = _formKey.currentState?.validate() ?? false;
    // Commit typed-but-not-added text before validating the remarks.
    final entries = _remarksKey.currentState?.commitPending() ?? const [];
    final remarks = joinNumberedList(entries);
    if (entries.isEmpty ||
        remarks.trim().length < ChecklistController.minCompletionRemarksLength) {
      setState(() =>
          _remarksError = 'Add at least one remark (10+ characters).');
      return;
    }
    if (!formOk) return;

    final otherStaff = _otherStaffController.text.trim();
    final ok = await ref
        .read(checklistControllerProvider(widget.recordId).notifier)
        .completeExecution(
          technicianName: _technicianController.text.trim(),
          remarks: remarks,
          proofJpegPath: _proof?.path,
          otherStaff: otherStaff.isEmpty ? null : otherStaff,
        );

    if (ok && mounted) Navigator.of(context).pop();
  }
}

/// Asks for the reason the server requires to un-check a group after
/// technician completion.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.trim().isEmpty;
    return AlertDialog(
      title: const Text('Reason required'),
      content: TextField(
        key: const Key('group_uncheck_reason_field'),
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Reason *',
          helperText: 'The Job Work is returned to the technician for rework.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('group_uncheck_reason_confirm'),
          onPressed:
              empty ? null : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Un-check'),
        ),
      ],
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
