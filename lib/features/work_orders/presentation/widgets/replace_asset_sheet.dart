import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/station_asset_picker.dart';
import 'package:intl/intl.dart';

/// Server column limit for asset make / model / serial (`max_length=50`).
const int kReplaceAssetFieldMaxLength = 50;

/// Opens the "Replace Asset" bottom sheet. Resolves to `true` once the server
/// acknowledged the replacement (the caller shows the success snackbar).
/// Online-only: the call is never queued, because it is not idempotent.
Future<bool?> showReplaceAssetSheet(
  BuildContext context,
  WidgetRef ref,
  ReplacementJobWork jobWork,
) {
  final repo = ref.read(replacementRepositoryProvider);
  final canReplace = canReplaceWholeAsset(sessionOf(ref));
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReplaceAssetSheet(
      jobWork: jobWork,
      repository: repo,
      canReplace: canReplace,
    ),
  );
}

class ReplaceAssetSheet extends StatefulWidget {
  const ReplaceAssetSheet({
    super.key,
    required this.jobWork,
    required this.repository,
    required this.canReplace,
  });

  final ReplacementJobWork jobWork;
  final IReplacementRepository repository;
  final bool canReplace;

  static String? validateRequired(String? v, String label) {
    if ((v ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  @override
  State<ReplaceAssetSheet> createState() => _ReplaceAssetSheetState();
}

class _ReplaceAssetSheetState extends State<ReplaceAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _reason = TextEditingController();
  final _remarks = TextEditingController();

  int? _assetId;
  String? _assetUniqueId;
  bool _pickedAsset = false;
  DateTime? _warranty;
  late DateTime _replacementDate;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _replacementDate = DateUtils.dateOnly(DateTime.now());
    final jw = widget.jobWork;
    if (jw.assetId != null) {
      _assetId = jw.assetId;
      _assetUniqueId = (jw.assetUniqueId?.trim().isNotEmpty ?? false)
          ? jw.assetUniqueId!.trim()
          : (jw.assetName?.trim().isNotEmpty ?? false)
              ? jw.assetName!.trim()
              : 'Asset #${jw.assetId}';
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickAsset(first: true));
    }
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _serial.dispose();
    _reason.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _pickAsset({bool first = false}) async {
    if (!mounted) return;
    final Asset? picked = await showStationAssetPicker(
      context,
      repository: widget.repository,
      jobWork: widget.jobWork,
      selectedAssetId: _assetId,
    );
    if (!mounted) return;
    if (picked == null) {
      if (first) Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _assetId = picked.id;
      _assetUniqueId = picked.uniqueId;
      _pickedAsset = true;
    });
  }

  Future<void> _pickWarranty() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _warranty ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null && mounted) setState(() => _warranty = d);
  }

  Future<void> _pickReplacementDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _replacementDate.isAfter(today) ? today : _replacementDate,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (d != null && mounted) setState(() => _replacementDate = d);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final assetId = _assetId;
    if (assetId == null) return;
    if (!widget.canReplace) {
      setState(() => _error =
          'Unauthorized: Only Maintenance Staff can replace assets.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await showConfirmationDialog(
      context,
      title: 'Replace this asset?',
      message:
          'Are you sure you want to replace this asset? This action is recorded.',
      confirmLabel: 'Replace',
      destructive: true,
      confirmKey: const Key('replace_asset_confirm_dialog'),
    );
    if (!ok || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.replaceAsset(
        assetId,
        AssetReplacementRequest(
          workOrderId: widget.jobWork.workOrderId,
          newMake: _make.text,
          newModel: _model.text,
          newSerialNumber: _serial.text,
          newWarrantyExpiry: _warranty,
          replacementDate: _replacementDate,
          reason: _reason.text,
          remarks: _remarks.text,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Failed to replace asset: ${replacementErrorText(e)}';
      });
    }
  }

  Widget _dateField({
    required Key fieldKey,
    required String label,
    required DateTime? value,
    String? helper,
    VoidCallback? onTap,
    VoidCallback? onClear,
  }) {
    final tokens = context.gssms;
    return InkWell(
      key: fieldKey,
      onTap: _submitting ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          isDense: true,
          suffixIcon: value != null && onClear != null
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear, size: GssmsSize.iconMd),
                  onPressed: _submitting ? null : onClear,
                )
              : const Icon(Icons.calendar_today_outlined,
                  size: GssmsSize.iconMd),
        ),
        child: Text(
          value == null ? '' : DateFormat('dd MMM yyyy').format(value),
          style: TextStyle(color: tokens.textPrimary),
        ),
      ),
    );
  }

  Widget _text(
    String key,
    TextEditingController c,
    String label, {
    String? hint,
    bool required = false,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      key: Key('replace_asset_$key'),
      controller: c,
      enabled: !_submitting,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      buildCounter: (_,
              {required currentLength, required isFocused, maxLength}) =>
          null,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
      ),
      validator: required
          ? (v) => ReplaceAssetSheet.validateRequired(
              v, label.replaceAll(' *', ''))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);
    final uniqueId = _assetUniqueId;
    const gap = SizedBox(height: GssmsSpacing.s12);

    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: uniqueId == null
          // Waiting on the station asset picker (shown on top of this sheet).
          ? const SizedBox(height: 120)
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Replace Asset: $uniqueId',
                      key: const Key('replace_asset_title'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: GssmsSpacing.s8),
                    Text(
                      'This will archive the current make/model/serial and '
                      'update the asset with new details. The ID $uniqueId '
                      'will remain unchanged.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: tokens.textSecondary),
                    ),
                    gap,
                    Wrap(
                      spacing: GssmsSpacing.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const StatusChip(
                          key: Key('replace_asset_linked_badge'),
                          label: 'Linked to Job Work',
                          tone: GssmsTone.info,
                          icon: Icons.link,
                        ),
                        if (_pickedAsset)
                          TextButton.icon(
                            key: const Key('replace_asset_change'),
                            onPressed: _submitting ? null : _pickAsset,
                            icon: const Icon(Icons.arrow_back,
                                size: GssmsSize.iconSm),
                            label: const Text('Change Asset'),
                          ),
                      ],
                    ),
                    gap,
                    _text('new_make', _make, 'New Make *',
                        hint: 'e.g. Siemens',
                        required: true,
                        maxLength: kReplaceAssetFieldMaxLength),
                    gap,
                    _text('new_model', _model, 'New Model',
                        hint: 'Optional',
                        maxLength: kReplaceAssetFieldMaxLength),
                    gap,
                    _text('new_serial', _serial, 'New Serial No',
                        hint: 'Optional',
                        maxLength: kReplaceAssetFieldMaxLength),
                    gap,
                    _dateField(
                      fieldKey: const Key('replace_asset_warranty'),
                      label: 'New Warranty Exp.',
                      value: _warranty,
                      onTap: _pickWarranty,
                      onClear: () => setState(() => _warranty = null),
                    ),
                    gap,
                    _dateField(
                      fieldKey: const Key('replace_asset_replacement_date'),
                      label: 'Date of Replacement *',
                      value: _replacementDate,
                      helper: 'Actual date when replacement occurred',
                      onTap: _pickReplacementDate,
                    ),
                    gap,
                    _text('reason', _reason, 'Reason for Replacement *',
                        hint: 'e.g. Burnt out, Upgraded',
                        required: true,
                        minLines: 2,
                        maxLines: 4),
                    gap,
                    _text('remarks', _remarks, 'Remarks',
                        minLines: 1, maxLines: 3),
                    if (_error != null) ...[
                      const SizedBox(height: GssmsSpacing.s8),
                      Text(
                        _error!,
                        key: const Key('replace_asset_error'),
                        style: TextStyle(color: tokens.danger.foreground),
                      ),
                    ],
                    const SizedBox(height: GssmsSpacing.s16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            key: const Key('replace_asset_cancel'),
                            onPressed: _submitting
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: GssmsSpacing.s8),
                        Expanded(
                          child: FilledButton(
                            key: const Key('replace_asset_submit'),
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.danger.solid,
                              foregroundColor: tokens.danger.onSolid,
                              minimumSize: const Size.fromHeight(
                                  GssmsSize.touchTarget),
                            ),
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: tokens.danger.onSolid,
                                    ),
                                  )
                                : const Text('Confirm Replacement'),
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
}
