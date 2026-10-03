import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_api_service.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/station_asset_picker.dart';

/// Whether the replaced component belongs to a registered asset.
enum ComponentAssetMode { registered, unregistered }

/// Opens the "Replace Component" bottom sheet. Resolves to `true` when the
/// server acknowledged the replacement (the caller shows the success
/// snackbar), otherwise `null` / `false`.
Future<bool?> showReplaceComponentSheet(
  BuildContext context,
  WidgetRef ref,
  ReplacementJobWork jobWork,
) {
  final repo = ref.read(replacementRepositoryProvider);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReplaceComponentSheet(jobWork: jobWork, repository: repo),
  );
}

/// Replace-component flow for the open checklist's Job Work. Online-only and
/// not idempotent: failures are shown inline and the sheet stays open.
class ReplaceComponentSheet extends StatefulWidget {
  const ReplaceComponentSheet({
    super.key,
    required this.jobWork,
    required this.repository,
  });

  final ReplacementJobWork jobWork;
  final IReplacementRepository repository;

  @override
  State<ReplaceComponentSheet> createState() => _ReplaceComponentSheetState();
}

class _ReplaceComponentSheetState extends State<ReplaceComponentSheet> {
  static const _requiredFieldsMessage =
      'Please fill in required fields (Component Name, Make, Serial No, Reason).';

  final _reference = TextEditingController();
  final _name = TextEditingController();
  final _oldMake = TextEditingController();
  final _oldModel = TextEditingController();
  final _oldSerial = TextEditingController();
  final _newMake = TextEditingController();
  final _newModel = TextEditingController();
  final _newSerial = TextEditingController();
  final _reason = TextEditingController();
  final _remarks = TextEditingController();

  late ComponentAssetMode _mode;
  Asset? _asset;
  String? _assetError;
  bool _loadingAssets = false;
  String? _assetsLoadError;

  List<AssetComponent> _components = const [];
  AssetComponent? _component;
  bool _loadingComponents = false;
  String? _componentsLoadError;
  int _componentsRequest = 0;

  DateTime? _warranty;
  bool _submitting = false;
  String? _error;
  Set<String> _missing = const {};

  bool get _hasStation => widget.jobWork.stationId != null;
  bool get _registered => _mode == ComponentAssetMode.registered;

  @override
  void initState() {
    super.initState();
    _mode = _hasStation
        ? ComponentAssetMode.registered
        : ComponentAssetMode.unregistered;
    if (_hasStation) _preselectJobWorkAsset();
  }

  @override
  void dispose() {
    for (final c in [
      _reference,
      _name,
      _oldMake,
      _oldModel,
      _oldSerial,
      _newMake,
      _newModel,
      _newSerial,
      _reason,
      _remarks,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Web parity: default the registered asset to the Job Work's own asset when
  /// it is part of the (station-scoped) list.
  Future<void> _preselectJobWorkAsset() async {
    final jw = widget.jobWork;
    setState(() => _loadingAssets = true);
    try {
      final page = await widget.repository.fetchStationAssets(
        stationId: jw.stationId!,
        infrastructureId: jw.infrastructureId,
      );
      if (!mounted) return;
      Asset? match;
      if (jw.assetId != null) {
        for (final a in page.assets) {
          if (a.id == jw.assetId) match = a;
        }
      }
      setState(() => _loadingAssets = false);
      // The user may already have picked an asset while this was loading.
      if (match != null && _asset == null) _selectAsset(match);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAssets = false;
        _assetsLoadError =
            'Failed to load registered assets for this maintenance location.';
      });
    }
  }

  void _clearComponentFields() {
    _component = null;
    _name.clear();
    _oldMake.clear();
    _oldModel.clear();
    _oldSerial.clear();
  }

  void _selectAsset(Asset asset) {
    final request = ++_componentsRequest;
    setState(() {
      _asset = asset;
      _assetError = null;
      _components = const [];
      _componentsLoadError = null;
      _loadingComponents = true;
      _clearComponentFields();
    });
    _loadComponents(asset.id, request);
  }

  Future<void> _loadComponents(int assetId, int request) async {
    try {
      final list = await widget.repository.fetchReplaceableComponents(assetId);
      if (!mounted || request != _componentsRequest) return;
      setState(() {
        _components = list;
        _loadingComponents = false;
      });
    } catch (_) {
      if (!mounted || request != _componentsRequest) return;
      setState(() {
        _loadingComponents = false;
        _componentsLoadError =
            'Failed to load registered components for this asset.';
      });
    }
  }

  void _selectComponent(String? sourceId) {
    AssetComponent? picked;
    for (final c in _components) {
      if (c.sourceId == sourceId) picked = c;
    }
    setState(() {
      _component = picked;
      _name.text = picked?.name ?? '';
      _oldMake.text = picked?.make ?? '';
      _oldModel.text = picked?.model ?? '';
      _oldSerial.text = picked?.serialNumber ?? '';
    });
  }

  Future<void> _pickAsset() async {
    final picked = await showStationAssetPicker(
      context,
      repository: widget.repository,
      jobWork: widget.jobWork,
      title: 'Select Registered Asset',
      selectedAssetId: _asset?.id,
    );
    if (picked == null || !mounted) return;
    if (picked.id != _asset?.id) _selectAsset(picked);
  }

  Future<void> _pickWarranty() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _warranty ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _warranty = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final reference = _reference.text.trim();
    final name = _name.text.trim();
    final newMake = _newMake.text.trim();
    final newSerial = _newSerial.text.trim();
    final reason = _reason.text.trim();

    String? banner;
    String? assetError;
    var missing = <String>{};
    if (_registered && _component == null) {
      banner = 'Please select a registered component.';
      if (_asset == null) assetError = 'Please select a registered asset.';
    } else if (!_registered && reference.isEmpty) {
      banner = 'Please enter the non-registered asset name or identifier.';
    } else {
      if (name.isEmpty) missing.add('name');
      if (newMake.isEmpty) missing.add('new_make');
      if (newSerial.isEmpty) missing.add('new_serial');
      if (reason.isEmpty) missing.add('reason');
      if (missing.isNotEmpty) banner = _requiredFieldsMessage;
    }
    if (banner != null) {
      setState(() {
        _error = banner;
        _assetError = assetError;
        _missing = missing;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _assetError = null;
      _missing = const {};
    });
    try {
      if (_registered) {
        final component = _component!;
        await widget.repository.replaceInstalledComponent(
          component.sourceId,
          InstalledComponentReplacementRequest(
            workOrderId: widget.jobWork.workOrderId,
            reason: reason,
            componentCode: component.componentCode,
            name: name,
            make: newMake,
            model: _newModel.text.trim(),
            serialNumber: newSerial,
          ),
        );
      } else {
        await widget.repository.logJobWorkReplacement(
          widget.jobWork.workOrderId,
          JobWorkComponentReplacementRequest(
            assetReference: reference,
            componentName: name,
            oldMake: _oldMake.text.trim(),
            oldModel: _oldModel.text.trim(),
            oldSerialNumber: _oldSerial.text.trim(),
            newMake: newMake,
            newModel: _newModel.text.trim(),
            newSerialNumber: newSerial,
            newWarrantyExpiry: _warranty,
            reason: reason,
            remarks: _remarks.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Failed to save component replacement: '
            '${replacementErrorText(e)}';
      });
    }
  }

  String _assetLabel(Asset a) =>
      '${a.uniqueId} — ${a.assetCategoryName ?? a.displayName}';

  String get _intro {
    final asset = _asset;
    if (_registered && asset != null) {
      return 'Record a component replaced within asset ${asset.uniqueId}. '
          'Its asset master component history will be updated.';
    }
    return 'Select a registered asset and one of its existing components, '
        'or use the non-registered asset option.';
  }

  Widget _notice(GssmsTone tone, IconData icon, String text, {Key? key}) {
    final palette = context.gssms.tone(tone);
    return Container(
      key: key,
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

  Widget _text(
    String keySuffix,
    TextEditingController controller,
    String label, {
    String? hint,
    int minLines = 1,
    int maxLines = 1,
    int? maxLength,
    bool enabled = true,
    String? missingKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
      child: TextFormField(
        key: Key('replace_component_$keySuffix'),
        controller: controller,
        enabled: enabled && !_submitting,
        minLines: minLines,
        maxLines: maxLines,
        inputFormatters:
            maxLength == null ? null : [LengthLimitingTextInputFormatter(maxLength)],
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          errorText: missingKey != null && _missing.contains(missingKey)
              ? 'Required'
              : null,
        ),
      ),
    );
  }

  Widget _assetField() {
    final tokens = context.gssms;
    final asset = _asset;
    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
      child: InkWell(
        key: const Key('replace_component_asset_field'),
        onTap: _submitting ? null : _pickAsset,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Registered Asset *',
            isDense: true,
            errorText: _assetError,
            suffixIcon: _loadingAssets
                ? const Padding(
                    padding: EdgeInsets.all(GssmsSpacing.s12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            asset != null
                ? _assetLabel(asset)
                : (_loadingAssets
                    ? 'Loading registered assets…'
                    : '-- Select registered asset --'),
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: asset != null ? null : tokens.textSecondary,
                ),
          ),
        ),
      ),
    );
  }

  Widget _componentField() {
    final tokens = context.gssms;
    if (_componentsLoadError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
        child: Text(
          _componentsLoadError!,
          key: const Key('replace_component_components_error'),
          style: TextStyle(color: tokens.danger.foreground),
        ),
      );
    }
    if (_loadingComponents) {
      return Padding(
        padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
        child: DropdownButtonFormField<String>(
          key: const Key('replace_component_component_loading'),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Existing Registered Component *',
            isDense: true,
          ),
          hint: const Text('Loading components…'),
          items: const [],
          onChanged: null,
        ),
      );
    }
    if (_components.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
        child: _notice(
          GssmsTone.warning,
          Icons.warning_amber_rounded,
          'No replaceable registered components are available. Select '
          '“Non-registered asset” to record a manual component '
          'replacement.',
          key: const Key('replace_component_no_components'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
      child: DropdownButtonFormField<String>(
        key: const Key('replace_component_component_dropdown'),
        isExpanded: true,
        initialValue: _component?.sourceId,
        decoration: const InputDecoration(
          labelText: 'Existing Registered Component *',
          isDense: true,
        ),
        hint: const Text('-- Select component --'),
        items: [
          for (final c in _components)
            DropdownMenuItem(
              value: c.sourceId,
              child: Text(
                '${c.componentCode ?? 'Component'} — ${c.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _submitting ? null : _selectComponent,
      ),
    );
  }

  Widget _warrantyField() {
    final tokens = context.gssms;
    final date = _warranty;
    return Padding(
      padding: const EdgeInsets.only(bottom: GssmsSpacing.s12),
      child: InkWell(
        key: const Key('replace_component_warranty'),
        onTap: _submitting ? null : _pickWarranty,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'New Warranty Exp.',
            isDense: true,
            suffixIcon: date == null
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(
                    key: const Key('replace_component_warranty_clear'),
                    icon: const Icon(Icons.clear),
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _warranty = null),
                  ),
          ),
          child: Text(
            date == null
                ? 'Optional'
                : MaterialLocalizations.of(context).formatCompactDate(date),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: date == null ? tokens.textSecondary : null,
                ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: GssmsSpacing.s16,
        right: GssmsSpacing.s16,
        top: GssmsSpacing.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + GssmsSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Replace Component',
              key: const Key('replace_component_title'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: GssmsSpacing.s8),
            Text(
              _intro,
              key: const Key('replace_component_intro'),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: GssmsSpacing.s16),
            Text(
              'Asset registration',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: GssmsSpacing.s4),
            SegmentedButton<ComponentAssetMode>(
              key: const Key('replace_component_mode'),
              segments: [
                ButtonSegment(
                  value: ComponentAssetMode.registered,
                  label: const Text('Registered asset'),
                  enabled: _hasStation,
                ),
                const ButtonSegment(
                  value: ComponentAssetMode.unregistered,
                  label: Text('Non-registered asset'),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: _submitting
                  ? null
                  : (s) => setState(() {
                        _mode = s.first;
                        _error = null;
                        _assetError = null;
                        _missing = const {};
                      }),
            ),
            const SizedBox(height: GssmsSpacing.s12),
            if (_registered) ...[
              if (_assetsLoadError != null) ...[
                Text(
                  _assetsLoadError!,
                  key: const Key('replace_component_assets_error'),
                  style: TextStyle(color: tokens.danger.foreground),
                ),
                const SizedBox(height: GssmsSpacing.s8),
              ],
              _assetField(),
              if (_asset != null) _componentField(),
            ] else ...[
              if (!_hasStation) ...[
                _notice(
                  GssmsTone.warning,
                  Icons.warning_amber_rounded,
                  "This Job Work has no station, so registered assets can't "
                  'be listed. Use Non-registered asset.',
                  key: const Key('replace_component_no_station'),
                ),
                const SizedBox(height: GssmsSpacing.s12),
              ],
              _text(
                'asset_reference',
                _reference,
                'Non-registered Asset Name / ID *',
                hint: 'e.g. Old relay panel near cabin entrance',
              ),
            ],
            _text(
              'name',
              _name,
              'Component Name *',
              hint: 'e.g. Indication Lamp',
              enabled: !_registered,
              missingKey: 'name',
            ),
            _text('old_make', _oldMake, 'Old Make (Optional)'),
            _text('old_model', _oldModel, 'Old Model (Optional)'),
            _text('old_serial', _oldSerial, 'Old Serial No (Optional)'),
            _text('new_make', _newMake, 'New Make *',
                maxLength: 100, missingKey: 'new_make'),
            _text('new_model', _newModel, 'New Model'),
            _text('new_serial', _newSerial, 'New Serial No *',
                maxLength: 100, missingKey: 'new_serial'),
            _warrantyField(),
            _text(
              'reason',
              _reason,
              'Reason for Replacement *',
              hint: 'e.g. Broken, Worn out',
              minLines: 2,
              maxLines: 4,
              missingKey: 'reason',
            ),
            _text('remarks', _remarks, 'Remarks', maxLines: 3),
            if (_error != null) ...[
              Text(
                _error!,
                key: const Key('replace_component_error'),
                style: TextStyle(color: tokens.danger.foreground),
              ),
              const SizedBox(height: GssmsSpacing.s8),
            ],
            const SizedBox(height: GssmsSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const Key('replace_component_cancel'),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: GssmsSpacing.s8),
                Expanded(
                  child: FilledButton(
                    key: const Key('replace_component_submit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.danger.solid,
                      foregroundColor: tokens.danger.onSolid,
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
    );
  }
}
