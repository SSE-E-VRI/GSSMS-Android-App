import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/data/org_scope_options_service.dart';
import 'package:gssms_mobile/core/domain/lookup_option.dart';
import 'package:gssms_mobile/core/domain/org_option.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/models/org_scope.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';

const _infraTypes = [
  InfraFilterType.station,
  InfraFilterType.lcGate,
  InfraFilterType.serviceBuilding,
  InfraFilterType.staffQuarter,
];

/// Log New Complaint — mirrors web `Log New Complaint`
/// (gssms.share.zrok.io/complaints/new) field-for-field: Depot, Department
/// Reporting, Title/Subject, a Location & Asset Details group (Infrastructure
/// Type, Location Name, Asset Category, Specific Asset), then Description,
/// with Cancel / Submit Complaint footer.
class ComplaintCreateScreen extends ConsumerStatefulWidget {
  const ComplaintCreateScreen(
      {super.key, this.initialAssetId, this.initialAssetName});

  final int? initialAssetId;
  final String? initialAssetName;

  @override
  ConsumerState<ComplaintCreateScreen> createState() =>
      _ComplaintCreateScreenState();
}

class _ComplaintCreateScreenState extends ConsumerState<ComplaintCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  bool _isSubmitting = false;
  bool _bootstrapped = false;

  List<LookupOption> _departments = const [];
  bool _loadingDepartments = false;
  String? _selectedDepartment;
  String? _departmentError;

  bool _canSelectDepot = false;
  List<OrgOption> _depots = const [];
  bool _loadingDepots = false;
  int? _selectedDepotId;

  InfraFilterType _infraType = InfraFilterType.station;
  List<InfrastructureOption> _locations = const [];
  bool _loadingLocations = false;
  int? _selectedLocationId;

  List<Asset> _assets = const [];
  bool _loadingAssets = false;
  List<String> _categories = const [];
  String? _selectedCategory;
  int? _selectedAssetId;

  static const _webRed = AppTheme.errorRed;
  static const _webLightBg = AppTheme.backgroundLight;
  static const _border = AppTheme.borderGrey;

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

  /// The station this complaint's location resolves to, whatever
  /// Infrastructure Type is selected — a Station row's own id, or the
  /// selected LC Gate/Service Building/Staff Quarter's parent station.
  int? get _resolvedStationId {
    if (_selectedLocationId == null) return null;
    if (_infraType == InfraFilterType.station) return _selectedLocationId;
    final match = _locations.where((l) => l.id == _selectedLocationId);
    return match.isEmpty ? null : match.first.stationId;
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    final session = sessionFromAuth(ref.read(authControllerProvider));
    if (!sessionAllows(session, 'complaints.create')) {
      if (mounted) setState(() => _bootstrapped = true);
      return;
    }
    final scope = session?.scope ?? const OrgScope();

    setState(() {
      _canSelectDepot = session != null &&
          scope.level != OrgScopeLevel.depot &&
          scope.level != OrgScopeLevel.self;
      _selectedDepotId = session?.depotId;
      // For depot-scoped users the dropdown is disabled — seed it with their
      // own depot so the field still shows the resolved depot name rather
      // than a blank "-- Select Depot --" hint (same as inspection form).
      if (!_canSelectDepot && _selectedDepotId != null) {
        _depots = [
          OrgOption(
              id: _selectedDepotId!,
              name: session?.depotName ?? 'Depot #$_selectedDepotId')
        ];
      }
      _bootstrapped = true;
    });

    unawaited(_loadDepartments());
    if (_canSelectDepot) {
      unawaited(
          _loadDepots(zoneId: scope.zone?.id, divisionId: scope.division?.id));
    }
    unawaited(_loadLocations());
  }

  Future<void> _loadDepartments() async {
    setState(() => _loadingDepartments = true);
    try {
      final options = await ref
          .read(lookupOptionsServiceProvider)
          .fetchOptions('complaint_department');
      if (mounted) setState(() => _departments = options);
    } catch (_) {
      if (mounted) {
        setState(() => _departmentError = 'Failed to load departments');
      }
    } finally {
      if (mounted) setState(() => _loadingDepartments = false);
    }
  }

  Future<void> _loadDepots({int? zoneId, int? divisionId}) async {
    setState(() => _loadingDepots = true);
    try {
      final depots = await ref
          .read(orgScopeOptionsServiceProvider)
          .fetchDepots(zoneId: zoneId, divisionId: divisionId);
      if (mounted) setState(() => _depots = depots);
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
      final options = await ref
          .read(infrastructureOptionsServiceProvider)
          .fetchOptions(_infraType, depotId: _selectedDepotId);
      if (mounted) setState(() => _locations = options);
    } catch (_) {
      if (mounted) setState(() => _locations = const []);
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  Future<void> _loadAssetsForLocation() async {
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
      final categories = <String>{
        for (final a in page.assets)
          if ((a.assetCategoryName ?? '').trim().isNotEmpty)
            a.assetCategoryName!.trim(),
      }.toList()
        ..sort();
      setState(() {
        _assets = page.assets;
        _categories = categories;
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

  Future<void> _submitComplaint() async {
    if (!sessionAllows(sessionOf(ref), 'complaints.create')) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDepartment == null) {
      setState(() => _departmentError = 'Please select a department');
      return;
    }
    if (_canSelectDepot && _selectedDepotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a Depot'),
            backgroundColor: AppTheme.errorRed),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(complaintRepositoryProvider).createComplaint(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            department: _selectedDepartment!,
            depotId: _selectedDepotId,
            stationId: _infraType == InfraFilterType.station
                ? _selectedLocationId
                : null,
            infrastructureId: _infraType == InfraFilterType.station
                ? null
                : _selectedLocationId,
            assetId: _selectedAssetId ?? widget.initialAssetId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complaint logged successfully!'),
            backgroundColor: AppTheme.railwayGreen,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log complaint: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'complaints.create')) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Log New Complaint'),
          backgroundColor: AppTheme.primaryDark,
        ),
        body: const PermissionDeniedView(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log New Complaint'),
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
                      // Red header — mirrors web's "Log New Complaint" bar.
                      Container(
                        decoration: const BoxDecoration(
                          color: _webRed,
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: const Row(
                          children: [
                            Icon(Icons.campaign_outlined,
                                color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Log New Complaint',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.initialAssetName != null) ...[
                              _targetAssetBanner(),
                              const SizedBox(height: 14),
                            ],
                            _depotField(),
                            const SizedBox(height: 14),
                            _departmentField(),
                            const SizedBox(height: 14),
                            _titleField(),
                            const SizedBox(height: 16),
                            _locationAndAssetSection(),
                            const SizedBox(height: 14),
                            _descriptionField(),
                            const SizedBox(height: 16),
                            const Divider(height: 1, color: _border),
                            const SizedBox(height: 16),
                            _actionRow(),
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

  Widget _labelWithInfo(String label, {bool required = false}) {
    // Flexible text so long labels (e.g. "Specific Asset (Optional)") wrap
    // instead of overflowing their half-width column at 360dp.
    return Row(
      children: [
        Flexible(
          child: RichText(
            text: TextSpan(
              text: label,
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

  InputDecoration _webInput({
    String? hint,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
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
      errorText: errorText,
      suffixIcon: suffixIcon,
    );
  }

  Widget _targetAssetBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.railwayBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.railwayBlue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_circle_outlined,
              color: AppTheme.railwayBlue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Target Asset: ${widget.initialAssetName}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.railwayBlue,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _depotField() {
    final safeValue =
        _depots.any((d) => d.id == _selectedDepotId) ? _selectedDepotId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Depot'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_depot_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select Depot --',
            suffixIcon: _loadingDepots
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          items: _depots
              .map((d) => DropdownMenuItem(
                  value: d.id,
                  child: Text(d.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14))))
              .toList(),
          // Disabled once the user's own scope already fixes one depot — same as
          // web's `disabled={!canSelectDepot}`; the server forces this depot
          // regardless of what's sent for such a user, so an editable control
          // here would just be misleading.
          onChanged: !_canSelectDepot || _loadingDepots
              ? null
              : (id) {
                  setState(() => _selectedDepotId = id);
                  unawaited(_loadLocations());
                },
        ),
      ],
    );
  }

  Widget _departmentField() {
    final safeValue = _departments.any((d) => d.key == _selectedDepartment)
        ? _selectedDepartment
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Department Reporting', required: true),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('complaint_department_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select Department --',
            errorText: _departmentError,
            suffixIcon: _loadingDepartments
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          items: _departments
              .map((d) => DropdownMenuItem(
                  value: d.key,
                  child: Text(d.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14))))
              .toList(),
          onChanged: _loadingDepartments
              ? null
              : (key) => setState(() {
                    _selectedDepartment = key;
                    _departmentError = null;
                  }),
        ),
      ],
    );
  }

  Widget _titleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Title / Subject', required: true),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_title_field'),
          controller: _titleController,
          decoration: _webInput(hint: 'e.g. Fan not working in Waiting Hall'),
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter a complaint title';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _descriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Description', required: true),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('complaint_description_field'),
          controller: _descriptionController,
          decoration:
              _webInput(hint: 'Describe the issue in detail...'),
          maxLines: 5,
          minLines: 4,
          validator: (val) {
            if (val == null || val.trim().isEmpty) {
              return 'Please enter detailed description';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _locationAndAssetSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.errorLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.errorBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: _webRed, size: 16),
              SizedBox(width: 6),
              Text(
                'Location & Asset Details',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _webRed,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Row 1: Infrastructure Type + Location Name (mirrors web 2-col).
          // Wrap-friendly: on narrow phones the two fields stack instead of
          // overflowing — the previous fixed Row could push the Location
          // dropdown off-screen at 360dp.
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Column(
                  children: [
                    _infraTypeField(),
                    const SizedBox(height: 12),
                    _locationField(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _infraTypeField()),
                  const SizedBox(width: 12),
                  Expanded(child: _locationField()),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Row 2: Asset Category + Specific Asset.
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 420;
              if (narrow) {
                return Column(
                  children: [
                    _categoryField(),
                    const SizedBox(height: 12),
                    _assetField(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _categoryField()),
                  const SizedBox(width: 12),
                  Expanded(child: _assetField()),
                ],
              );
            },
          ),
          if (_resolvedStationId != null && !_loadingAssets && _assets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No registered assets found for this location. You can still log a generic complaint.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infraTypeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Infrastructure Type'),
        const SizedBox(height: 6),
        DropdownButtonFormField<InfraFilterType>(
          key: const Key('complaint_infra_type_dropdown'),
          isExpanded: true,
          value: _infraType,
          decoration: _webInput().copyWith(
            fillColor: AppTheme.surfaceCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          items: _infraTypes
              .map((t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (type) {
            if (type == null) return;
            setState(() => _infraType = type);
            unawaited(_loadLocations());
          },
        ),
      ],
    );
  }

  Widget _locationField() {
    final safeValue = _locations.any((l) => l.id == _selectedLocationId)
        ? _selectedLocationId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Location Name'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_location_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Select ${_infraType.label} --',
            suffixIcon: _loadingLocations
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ).copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                  unawaited(_loadAssetsForLocation());
                },
        ),
      ],
    );
  }

  Widget _categoryField() {
    final safeValue =
        _categories.contains(_selectedCategory) ? _selectedCategory : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Asset Category'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('complaint_asset_category_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(hint: '-- All Categories --').copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          // "-- All Categories --" is a real, selectable item (value: null), not
          // just the unselected hint — otherwise there is no menu item that can
          // take a selection back to "all" once a real category is picked.
          items: [
            const DropdownMenuItem<String>(
                value: null, child: Text('-- All Categories --', style: TextStyle(fontSize: 13))),
            ..._categories.map((c) => DropdownMenuItem(
                value: c,
                child: Text(c,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)))),
          ],
          onChanged: (_selectedLocationId == null || _assets.isEmpty)
              ? null
              : (cat) => setState(() {
                    _selectedCategory = cat;
                    if (_selectedAssetId != null &&
                        !_filteredAssets
                            .any((a) => a.id == _selectedAssetId)) {
                      _selectedAssetId = null;
                    }
                  }),
        ),
      ],
    );
  }

  Widget _assetField() {
    final options = _filteredAssets;
    final safeValue =
        options.any((a) => a.id == _selectedAssetId) ? _selectedAssetId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelWithInfo('Specific Asset (Optional)'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          key: const Key('complaint_asset_dropdown'),
          isExpanded: true,
          value: safeValue,
          decoration: _webInput(
            hint: '-- Generic / Location Issue --',
            suffixIcon: _loadingAssets
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ).copyWith(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          // Same reasoning as the category dropdown: a real null-valued item so
          // a generic (non-asset-specific) complaint can be reselected after
          // picking a specific asset.
          items: [
            const DropdownMenuItem<int>(
                value: null,
                child: Text('-- Generic / Location Issue --',
                    style: TextStyle(fontSize: 13))),
            ...options.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    _selectedCategory == null
                        ? '${a.uniqueId} (${a.assetCategoryName ?? ''})'
                        : a.uniqueId,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                )),
          ],
          onChanged: _selectedLocationId == null
              ? null
              : (id) => setState(() => _selectedAssetId = id),
        ),
      ],
    );
  }

  Widget _actionRow() {
    // NOTE: do NOT use full-width / expanded buttons here — AppTheme's
    // elevatedButtonTheme sets minimumSize: Size.fromHeight(48) (infinite
    // width), which inside a Row produces BoxConstraints(w=Infinity) and a
    // blank screen (same crash fixed on InspectionCreateScreen). Explicit
    // finite minimumSize + shrinkWrap keeps both buttons content-sized.
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          key: const Key('cancel_complaint_button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textMuted,
            side: const BorderSide(color: AppTheme.borderGrey),
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
          label:
              const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          key: const Key('submit_complaint_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _webRed,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            elevation: 2,
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: _isSubmitting ? null : _submitComplaint,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_outlined,
                  size: 16, color: Colors.white),
          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Complaint',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }
}
