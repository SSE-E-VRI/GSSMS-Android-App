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
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_master.dart';
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

  // Template / Checklist (maintenance_master) — optional, mirrors web's
  // "Template / Checklist" picker plus its schedule_type column filter and
  // Asset/Station template split (MaintenanceMasterList.jsx).
  List<MaintenanceMaster> _templates = const [];
  bool _loadingTemplates = false;
  MaintenanceScheduleType? _templateScheduleFilter;
  MaintenanceTemplateKind _templateKindFilter = MaintenanceTemplateKind.assetTemplate;
  int? _selectedMaintenanceMasterId;

  List<MaintenanceMaster> get _filteredTemplates {
    return _templates.where((t) {
      if (t.templateKind != _templateKindFilter) return false;
      if (_templateScheduleFilter != null &&
          t.scheduleType != _templateScheduleFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Header band + submit button: a solid/on-solid pair so the text stays
  /// readable in both themes.
  Color get _band => Theme.of(context).colorScheme.primary;
  Color get _onBand => Theme.of(context).colorScheme.onPrimary;
  Color get _webLightBg => context.gssms.surfaceInset;
  Color get _border => context.gssms.border;

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
    if (!canCreateWorkOrder(session)) {
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
    unawaited(_loadTemplates());
  }

  Future<void> _loadTemplates() async {
    setState(() => _loadingTemplates = true);
    try {
      final templates =
          await ref.read(workOrderRepositoryProvider).fetchMaintenanceMasters();
      if (mounted) setState(() => _templates = templates);
    } catch (_) {
      // Optional field — a failed template fetch must not block Job Work
      // creation. The dropdown simply stays empty/unfiltered.
      if (mounted) setState(() => _templates = const []);
    } finally {
      if (mounted) setState(() => _loadingTemplates = false);
    }
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
    if (!canCreateWorkOrder(sessionOf(ref))) {
      if (mounted) {
        showPermissionDeniedSnackBar(context);
      }
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_canSelectDepot && _selectedDepotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please select a Depot'),
          backgroundColor: context.gssms.danger.solid));
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
            // Creation uses `scheduled_date` — `due_date` is a read-only
            // server-derived field (SSOT §15), not a creation field.
            scheduledDate: _dueDate == null
                ? null
                : DateFormat('yyyy-MM-dd').format(_dueDate!),
            maintenanceMasterId: _selectedMaintenanceMasterId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Job Work created successfully!'),
            backgroundColor: context.gssms.success.solid));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Failed to create Job Work: ${workOrderReadableError(e)}'),
            backgroundColor: context.gssms.danger.solid));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // RBAC-05: `maintenance.create` alone is not enough — the backend's
    // WorkOrderPermission.CREATE_ROLES restricts the generic create action to
    // DEPOT_INCHARGE/DEPOT_USER with no admin-tier bypass, so canCreateWorkOrder
    // folds in that role check to avoid a guaranteed 403 on submit for
    // SUPER_ADMIN/ZR_ADMIN/DIV_ADMIN/DIV_HQ_USER.
    if (!canCreateWorkOrder(sessionOf(ref))) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('New Job Work'),
        ),
        body: const PermissionDeniedView(),
      );
    }

    return Scaffold(
      // No title here — the colored header below already carries it (as an
      // accessible `Semantics(header: true)` region), so the AppBar isn't
      // duplicating it back-to-back. Only the back button lives up top.
      appBar: AppBar(),
      backgroundColor: _webLightBg,
      body: !_bootstrapped
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
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
                      // This is the screen's only title (the AppBar carries
                      // no text of its own — see build() above), so it's
                      // marked as an accessible header region rather than
                      // decorative content screen readers would otherwise
                      // skip.
                      Semantics(
                        header: true,
                        label: 'New Job Work',
                        // The Row's own Icon/Text would otherwise each add
                        // their own semantics on top of this label.
                        excludeSemantics: true,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _band,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12)),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.add_task_outlined,
                                  color: _onBand, size: 20),
                              const SizedBox(width: 8),
                              Text('New Job Work',
                                  style: TextStyle(
                                      color: _onBand,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Depot',
                                tooltip:
                                    'The depot this Job Work is scoped to. Locked to your own depot unless you have multi-depot access.'),
                            const SizedBox(height: 6),
                            _depotField(),
                            const SizedBox(height: 14),
                            _label('Title / Subject',
                                required: true,
                                tooltip: 'A short summary of the work to be done.'),
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
                                      _label('Type',
                                          tooltip:
                                              'The nature of the work — preventive, corrective, breakdown, etc.'),
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
                                      _label('Priority',
                                          tooltip: 'How urgently this Job Work should be actioned.'),
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
                            _templateCard(),
                            const SizedBox(height: 14),
                            _label('Due Date (Optional)',
                                tooltip: 'The date this work is scheduled to be completed by.'),
                            const SizedBox(height: 6),
                            InkWell(
                              key: const Key('wo_due_date_field'),
                              onTap: _pickDueDate,
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: _input().copyWith(
                                  suffixIcon: _dueDate == null
                                      ? Icon(
                                          Icons.calendar_today_outlined,
                                          size: 18,
                                          color: context.gssms.textSecondary)
                                      : IconButton(
                                          key: const Key(
                                              'wo_due_date_clear'),
                                          tooltip: 'Clear due date',
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
                                          ? context.gssms.textSecondary
                                          : context.gssms.textPrimary),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _label('Description',
                                tooltip:
                                    'Scope of work, symptoms, or access notes for the assigned technician.'),
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
                            Divider(height: 1, color: _border),
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

  Widget _label(String t, {bool required = false, required String tooltip}) {
    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              text: t,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.gssms.textPrimary),
              children: [
                if (required)
                  TextSpan(
                      text: ' *',
                      style: TextStyle(
                          color: context.gssms.danger.foreground,
                          fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Was purely decorative — visually promised "tap for help" but had no
        // handler. Tooltip makes it a real tap/long-press affordance, and its
        // `message` doubles as the icon's accessible label instead of a
        // silent, unlabeled glyph.
        Tooltip(
          message: tooltip,
          triggerMode: TooltipTriggerMode.tap,
          child: Icon(Icons.info_outline,
              size: 14, color: context.gssms.textSecondary),
        ),
      ],
    );
  }

  InputDecoration _input([String? hint]) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: context.gssms.textSecondary, fontSize: 14),
        filled: true,
        fillColor: Theme.of(context).inputDecorationTheme.fillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _border)),
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
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on,
                  color: context.gssms.link, size: 16),
              const SizedBox(width: 6),
              Text('Location & Asset (Optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.gssms.link,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          _label('Infrastructure Type',
              tooltip:
                  'Narrows the Location Name list below to Stations, LC Gates, Service Buildings, or Staff Quarters.'),
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
          _label('Location Name', tooltip: 'The specific site this Job Work applies to.'),
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
          _label('Asset Category', tooltip: 'Filters the Specific Asset list below by category.'),
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
          _label('Specific Asset (Optional)',
              tooltip:
                  'Link this Job Work to one exact asset, or leave blank for a general/location-level task.'),
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

  Widget _templateCard() {
    final filtered = _filteredTemplates;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist, color: context.gssms.link, size: 16),
              const SizedBox(width: 6),
              Text('Template / Checklist (Optional)',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: context.gssms.link,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          _label('Category',
              tooltip:
                  'Asset Template applies to one specific asset; Station / Batch Template applies broadly across a station.'),
          const SizedBox(height: 6),
          // Web splits templates into Asset Templates / Station Templates
          // tables (MaintenanceMasterList.jsx `template_kind`); here that's a
          // segmented toggle instead of two lists. "Station / Batch" is the
          // scoped-across-a-station template kind ("batch job work").
          SegmentedButton<MaintenanceTemplateKind>(
            key: const Key('wo_template_kind_segment'),
            segments: const [
              ButtonSegment(
                value: MaintenanceTemplateKind.assetTemplate,
                label: Text('Asset', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: MaintenanceTemplateKind.stationTemplate,
                label: Text('Station / Batch', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {_templateKindFilter},
            onSelectionChanged: (s) {
              setState(() {
                _templateKindFilter = s.first;
                if (_selectedMaintenanceMasterId != null &&
                    !_filteredTemplates
                        .any((t) => t.id == _selectedMaintenanceMasterId)) {
                  _selectedMaintenanceMasterId = null;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          _label('Schedule Type', tooltip: 'How often this checklist template is meant to run.'),
          const SizedBox(height: 6),
          DropdownButtonFormField<MaintenanceScheduleType?>(
            key: const Key('wo_template_schedule_dropdown'),
            isExpanded: true,
            value: _templateScheduleFilter,
            decoration: _input('-- All Schedule Types --'),
            items: [
              const DropdownMenuItem<MaintenanceScheduleType?>(
                  value: null, child: Text('-- All Schedule Types --')),
              ...MaintenanceScheduleType.values
                  .where((s) => s != MaintenanceScheduleType.unknown)
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.displayName,
                          style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (s) {
              setState(() {
                _templateScheduleFilter = s;
                if (_selectedMaintenanceMasterId != null &&
                    !_filteredTemplates
                        .any((t) => t.id == _selectedMaintenanceMasterId)) {
                  _selectedMaintenanceMasterId = null;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          _label('Template',
              tooltip:
                  'Attach a checklist template so the technician has a structured checklist during execution.'),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            key: const Key('wo_template_dropdown'),
            isExpanded: true,
            value: filtered.any((t) => t.id == _selectedMaintenanceMasterId)
                ? _selectedMaintenanceMasterId
                : null,
            decoration: _input('-- No Template --').copyWith(
              suffixIcon: _loadingTemplates
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            items: [
              const DropdownMenuItem<int>(
                  value: null, child: Text('-- No Template --')),
              ...filtered.map((t) => DropdownMenuItem(
                  value: t.id,
                  child: Text('${t.name} (${t.scheduleType.displayName})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (id) =>
                setState(() => _selectedMaintenanceMasterId = id),
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
            foregroundColor: context.gssms.textSecondary,
            side: BorderSide(color: context.gssms.border),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 48),
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
            backgroundColor: _band,
            foregroundColor: _onBand,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 2,
            minimumSize: const Size(0, GssmsSize.touchTarget),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: _onBand, strokeWidth: 2))
              : const Icon(Icons.add_task_outlined,
                  size: 16),
          label: Text(_isSubmitting ? 'Creating...' : 'Create Job Work',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }
}
