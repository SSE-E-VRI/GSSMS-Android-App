import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:intl/intl.dart';

/// Minimal New Job Work — mirrors web's `+ New Job Work` dialog just enough
/// for field creation: Depot, Title, Type, Priority, Location (Infra Type +
/// Location Name), Asset (Category + Specific, optional), Due Date,
/// Description. Full template/schedule/failure-code flows stay web-only.
class WorkOrderCreateScreen extends ConsumerStatefulWidget {
  const WorkOrderCreateScreen({super.key});

  @override
  ConsumerState<WorkOrderCreateScreen> createState() =>
      _WorkOrderCreateScreenState();
}

class _WorkOrderCreateScreenState
    extends ConsumerState<WorkOrderCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  bool _bootstrapped = false;

  bool _canSelectDepot = false;
  List<OrgOption> _depots = const [];
  bool _loadingDepots = false;
  int? _selectedDepotId;

  WorkOrderType _type = WorkOrderType.preventive;
  WorkOrderPriority _priority = WorkOrderPriority.medium;
  DateTime? _dueDate;

  InfraFilterType _infraType = InfraFilterType.station;
  List<InfrastructureOption> _locations = const [];
  bool _loadingLocations = false;
  int? _selectedLocationId;

  List<Asset> _assets = const [];
  bool _loadingAssets = false;
  List<String> _categories = const [];
  String? _selectedCategory;
  int? _selectedAssetId;

  static const _webBlue = AppTheme.railwayBlue;
  static const _webLightBg = Color(0xFFF6F8FF);
  static const _border = Color(0xFFE3E8F5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  int? get _resolvedStationId {
    if (_selectedLocationId == null) return null;
    if (_infraType == InfraFilterType.station) return _selectedLocationId;
    final m = _locations.where((l) => l.id == _selectedLocationId);
    return m.isEmpty ? null : m.first.stationId;
  }

  int? get _resolvedInfraId {
    if (_selectedLocationId == null) return null;
    if (_infraType == InfraFilterType.station) return null;
    return _selectedLocationId;
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final session = sessionFromAuth(ref.read(authControllerProvider));
    if (!sessionAllows(session, 'maintenance.create')) {
      if (mounted) setState(() => _bootstrapped = true);
      return;
    }
    final scope = session?.scope ?? const OrgScope();
    setState(() {
      _canSelectDepot = session != null &&
          scope.level != OrgScopeLevel.depot &&
          scope.level != OrgScopeLevel.self;
      _selectedDepotId = session?.depotId;
      if (!_canSelectDepot && _selectedDepotId != null) {
        _depots = [
          OrgOption(
              id: _selectedDepotId!,
              name: session?.depotName ?? 'Depot #$_selectedDepotId')
        ];
      }
      _bootstrapped = true;
    });
    if (_canSelectDepot) {
      unawaited(_loadDepots(
          zoneId: scope.zone?.id, divisionId: scope.division?.id));
    }
    unawaited(_loadLocations());
  }

  Future<void> _loadDepots({int? zoneId, int? divisionId}) async {
    setState(() => _loadingDepots = true);
    try {
      final d = await ref
          .read(orgScopeOptionsServiceProvider)
          .fetchDepots(zoneId: zoneId, divisionId: divisionId);
      if (mounted) setState(() => _depots = d);
    } catch (_) {
      if (mounted) setState(() => _depots = const []);
    } finally {
      if (mounted) setState(() => _loadingDepots = false);
    }
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loadingLocations = true;
      _selectedLocationId = null;
      _locations = const [];
      _assets = const [];
      _categories = const [];
      _selectedCategory = null;
      _selectedAssetId = null;
    });
    try {
      final opts = await ref
          .read(infrastructureOptionsServiceProvider)
          .fetchOptions(_infraType, depotId: _selectedDepotId);
      if (mounted) setState(() => _locations = opts);
    } catch (_) {
      if (mounted) setState(() => _locations = const []);
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  Future<void> _loadAssets() async {
    final stationId = _resolvedStationId;
    setState(() {
      _assets = const [];
      _categories = const [];
      _selectedCategory = null;
      _selectedAssetId = null;
    });
    if (stationId == null) return;
    setState(() => _loadingAssets = true);
    try {
      final page = await ref
          .read(assetApiServiceProvider)
          .getAssets(stationId: stationId);
      if (!mounted) return;
      final cats = <String>{
        for (final a in page.assets)
          if ((a.assetCategoryName ?? '').trim().isNotEmpty)
            a.assetCategoryName!.trim(),
      }.toList()
        ..sort();
      setState(() {
        _assets = page.assets;
        _categories = cats;
      });
    } catch (_) {
      if (mounted) setState(() => _assets = const []);
    } finally {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  List<Asset> get _filteredAssets {
    if (_selectedCategory == null) return _assets;
    return _assets
        .where((a) => a.assetCategoryName == _selectedCategory)
        .toList();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select due date (optional)',
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!sessionAllows(sessionOf(ref), 'maintenance.create')) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_canSelectDepot && _selectedDepotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a Depot'),
          backgroundColor: AppTheme.errorRed));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref.read(workOrderRepositoryProvider).createWorkOrder(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            type: _type.code,
            priority: _priority.code,
            depotId: _selectedDepotId,
            stationId: _resolvedStationId,
            infrastructureId: _resolvedInfraId,
            assetId: _selectedAssetId,
            dueDate: _dueDate == null
                ? null
                : DateFormat('yyyy-MM-dd').format(_dueDate!),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Job Work created successfully!'),
            backgroundColor: AppTheme.railwayGreen));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Failed to create Job Work: ${workOrderReadableError(e)}'),
            backgroundColor: AppTheme.errorRed));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'maintenance.create')) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('New Job Work'),
          backgroundColor: AppTheme.primaryDark,
        ),
        body: const PermissionDeniedView(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Job Work'),
        backgroundColor: AppTheme.primaryDark,
      ),
      backgroundColor: _webLightBg,
      body: !_bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: _webBlue,
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: const Row(
                          children: [
                            Icon(Icons.add_task_outlined,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('New Job Work',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Depot'),
                            const SizedBox(height: 6),
                            _depotField(),
                            const SizedBox(height: 14),
                            _label('Title / Subject', required: true),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: const Key('wo_title_field'),
                              controller: _titleController,
                              decoration: _input(
                                  'e.g. Station monthly maintenance'),
                              validator: (v) =>
                                  v == null || v.trim().isEmpty
                                      ? 'Please enter a title'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('Type'),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<WorkOrderType>(
                                        key: const Key('wo_type_dropdown'),
                                        isExpanded: true,
                                        value: _type,
                                        decoration: _input(),
                                        items: const [
                                          WorkOrderType.preventive,
                                          WorkOrderType.corrective,
                                          WorkOrderType.breakdown,
                                          WorkOrderType.calibration,
                                          WorkOrderType.installation,
                                          WorkOrderType.other,
                                        ]
                                            .map((t) => DropdownMenuItem(
                                                value: t,
                                                child: Text(t.displayName,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 13))))
                                            .toList(),
                                        onChanged: (t) {
                                          if (t != null) {
                                            setState(() => _type = t);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _label('Priority'),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<
                                          WorkOrderPriority>(
                                        key: const Key(
                                            'wo_priority_dropdown'),
                                        isExpanded: true,
                                        value: _priority,
                                        decoration: _input(),
                                        items: WorkOrderPriority.values
                                            .map((p) => DropdownMenuItem(
                                                value: p,
                                                child: Text(p.displayName,
                                                    style: const TextStyle(
                                                        fontSize: 13))))
                                            .toList(),
                                        onChanged: (p) {
                                          if (p != null) {
                                            setState(
                                                () => _priority = p);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _locationCard(),
                            const SizedBox(height: 14),
                            _label('Due Date (Optional)'),
                            const SizedBox(height: 6),
                            InkWell(
                              key: const Key('wo_due_date_field'),
                              onTap: _pickDueDate,
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: _input().copyWith(
                                  suffixIcon: _dueDate == null
                                      ? const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 18,
                                          color: AppTheme.textSecondary)
                                      : IconButton(
                                          key: const Key(
                                              'wo_due_date_clear'),
                                          icon: const Icon(Icons.clear,
                                              size: 18),
                                          onPressed: () => setState(
                                              () => _dueDate = null),
                                        ),
                                ),
                                child: Text(
                                  _dueDate == null
                                      ? '-- Select date --'
                                      : DateFormat('dd-MM-yyyy')
                                          .format(_dueDate!),
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: _dueDate == null
                                          ? AppTheme.textSecondary
                                          : AppTheme.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _label('Description'),
                            const SizedBox(height: 6),
                            TextFormField(
                              key: const Key('wo_description_field'),
                              controller: _descriptionController,
                              decoration: _input(
                                  'Work scope, symptoms, access notes...'),
                              maxLines: 4,
                              minLines: 3,
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1, color: _border),
                            const SizedBox(height: 16),
                            _actions(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _label(String t, {bool required = false}) {
    return Row(
      children: [
        Flexible(
          child: RichText(
            text: TextSpan(
              text: t,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
              children: [
                if (required)
                  const TextSpan(
                      text: ' *',
                      style: TextStyle(
                          color: AppTheme.errorRed,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.info_outline,
            size: 14, color: AppTheme.textSecondary),
      ],
    );
  }

  InputDecoration _input([String? hint]) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _border)),
      );

  Widget _depotField() {
    final safe =
        _depots.any((d) => d.id == _selectedDepotId) ? _selectedDepotId : null;
    return DropdownButtonFormField<int>(
      key: const Key('wo_depot_dropdown'),
      isExpanded: true,
      value: safe,
      decoration: _input('-- Select Depot --').copyWith(
        suffixIcon: _loadingDepots
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)))
            : null,
      ),
      items: _depots
          .map((d) => DropdownMenuItem(
              value: d.id,
              child: Text(d.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14))))
          .toList(),
      onChanged: !_canSelectDepot || _loadingDepots
          ? null
          : (id) {
              setState(() => _selectedDepotId = id);
              unawaited(_loadLocations());
            },
    );
  }

  Widget _locationCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on,
                  color: AppTheme.railwayBlue, size: 16),
              SizedBox(width: 6),
              Text('Location & Asset (Optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.railwayBlue,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          _label('Infrastructure Type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<InfraFilterType>(
            key: const Key('wo_infra_type_dropdown'),
            isExpanded: true,
            value: _infraType,
            decoration: _input(),
            items: const [
              InfraFilterType.station,
              InfraFilterType.lcGate,
              InfraFilterType.serviceBuilding,
              InfraFilterType.staffQuarter,
            ]
                .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: (t) {
              if (t == null) return;
              setState(() => _infraType = t);
              unawaited(_loadLocations());
            },
          ),
          const SizedBox(height: 12),
          _label('Location Name'),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            key: const Key('wo_location_dropdown'),
            isExpanded: true,
            value: _locations.any((l) => l.id == _selectedLocationId)
                ? _selectedLocationId
                : null,
            decoration: _input('-- Select ${_infraType.label} --').copyWith(
              suffixIcon: _loadingLocations
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            items: _locations
                .map((l) => DropdownMenuItem(
                    value: l.id,
                    child: Text(l.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: _loadingLocations
                ? null
                : (id) {
                    setState(() => _selectedLocationId = id);
                    unawaited(_loadAssets());
                  },
          ),
          const SizedBox(height: 12),
          _label('Asset Category'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: const Key('wo_asset_category_dropdown'),
            isExpanded: true,
            value: _categories.contains(_selectedCategory)
                ? _selectedCategory
                : null,
            decoration: _input('-- All Categories --'),
            items: [
              const DropdownMenuItem<String>(
                  value: null, child: Text('-- All Categories --')),
              ..._categories.map((c) => DropdownMenuItem(
                  value: c, child: Text(c))),
            ],
            onChanged: (_selectedLocationId == null || _assets.isEmpty)
                ? null
                : (c) => setState(() {
                      _selectedCategory = c;
                      if (_selectedAssetId != null &&
                          !_filteredAssets
                              .any((a) => a.id == _selectedAssetId)) {
                        _selectedAssetId = null;
                      }
                    }),
          ),
          const SizedBox(height: 12),
          _label('Specific Asset (Optional)'),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            key: const Key('wo_asset_dropdown'),
            isExpanded: true,
            value: _filteredAssets.any((a) => a.id == _selectedAssetId)
                ? _selectedAssetId
                : null,
            decoration:
                _input('-- Generic / Location Work --').copyWith(
              suffixIcon: _loadingAssets
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            items: [
              const DropdownMenuItem<int>(
                  value: null,
                  child: Text('-- Generic / Location Work --')),
              ..._filteredAssets.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(a.uniqueId,
                      overflow: TextOverflow.ellipsis))),
            ],
            onChanged: _selectedLocationId == null
                ? null
                : (id) => setState(() => _selectedAssetId = id),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          key: const Key('cancel_wo_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF64748B),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Cancel',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          key: const Key('submit_wo_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.railwayBlue,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 2,
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add_task_outlined,
                  size: 16, color: Colors.white),
          label: Text(_isSubmitting ? 'Creating...' : 'Create Job Work',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }
}
