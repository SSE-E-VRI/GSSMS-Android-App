import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_create_screen.dart';
import 'package:intl/intl.dart';

class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});

  final int assetId;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!sessionAllows(
          sessionFromAuth(ref.read(authControllerProvider)),
          'assets.view')) {
        return;
      }
      ref.read(assetDetailControllerProvider(widget.assetId).notifier).loadAsset();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'assets.view')) {
      return Scaffold(
        appBar: AppBar(title: Text('Asset #${widget.assetId}')),
        body: const PermissionDeniedView(),
      );
    }

    final state = ref.watch(assetDetailControllerProvider(widget.assetId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(state)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref
                .read(assetDetailControllerProvider(widget.assetId).notifier)
                .loadAsset(),
          ),
        ],
      ),
      body: _buildBody(state),
      bottomNavigationBar: _buildBottomBar(state),
    );
  }

  /// The asset's own category (e.g. "CLS Panels") once loaded — that's what
  /// identifies the asset to someone opening this screen, not its internal
  /// id. Falls back to the id while loading or on error, when there's no
  /// category to show yet.
  String _titleFor(AssetDetailState state) {
    if (state is AssetDetailLoaded) {
      final category = state.asset.assetCategoryName;
      if (category != null && category.trim().isNotEmpty) return category;
    }
    return 'Asset #${widget.assetId}';
  }

  Widget _buildBody(AssetDetailState state) {
    if (state is AssetDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AssetDetailError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.errorRed),
              const SizedBox(height: 12),
              Text(state.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref
                    .read(assetDetailControllerProvider(widget.assetId).notifier)
                    .loadAsset(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (state is AssetDetailLoaded) {
      final asset = state.asset;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(asset),
            const SizedBox(height: 16),
            _buildLocationCard(asset),
            const SizedBox(height: 16),
            _buildTechnicalCard(asset),
            if (asset.remarks != null && asset.remarks!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildRemarksCard(asset),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHeaderCard(Asset asset) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              asset.uniqueId,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.railwayBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              asset.displayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (asset.assetCategoryName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Category: ${asset.assetCategoryName}',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(Asset asset) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location & Installation',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _infoRow('Station', asset.stationName ?? 'N/A'),
            _infoRow('Depot', asset.depotName ?? 'N/A'),
            if (asset.infrastructureName != null)
              _infoRow('Infrastructure', asset.infrastructureName!),
            if (asset.installationDate != null)
              _infoRow('Installed Date', DateFormat('dd MMM yyyy').format(asset.installationDate!)),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalCard(Asset asset) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Technical Specifications',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            _infoRow('Manufacturer', asset.make ?? 'N/A'),
            _infoRow('Model Number', asset.model ?? 'N/A'),
            _infoRow('Serial Number', asset.serialNumber ?? 'N/A'),
            _infoRow('Criticality', asset.criticality.displayName),
            if (asset.capacity != null) _infoRow("Capacity", asset.capacity!),
            if (asset.warrantyExpiryDate != null)
              _infoRow("Warranty Expiry", DateFormat("dd MMM yyyy").format(asset.warrantyExpiryDate!)),
            if (asset.lastMaintenanceDate != null)
              _infoRow("Last Maintenance", DateFormat("dd MMM yyyy").format(asset.lastMaintenanceDate!)),
          ],
        ),
      ),
    );
  }

  Widget _buildRemarksCard(Asset asset) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Remarks',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 20),
            Text(asset.remarks!, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar(AssetDetailState state) {
    if (state is! AssetDetailLoaded) return null;
    final asset = state.asset;

    // rbac/registry.py MODULES builds every permission code as
    // `{module}.{action}` from CRUD = ["view", "create", "edit", "delete"] —
    // there is no "add" action, so `complaints.add` never appears in a real
    // JWT's permissions claim and this gate was unconditionally hiding the
    // button for every user.
    if (!sessionAllows(sessionOf(ref), 'complaints.create')) {
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        key: const Key('action_log_asset_complaint'),
        icon: const Icon(Icons.report_problem_outlined),
        label: const Text('Log Complaint for Asset'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ComplaintCreateScreen(
                initialAssetId: asset.id,
                initialAssetName: '${asset.uniqueId} - ${asset.displayName}',
              ),
            ),
          );
        },
      ),
    );
  }
}
