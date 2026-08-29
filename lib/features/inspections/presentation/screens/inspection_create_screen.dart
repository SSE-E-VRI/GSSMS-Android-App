import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';

class InspectionCreateScreen extends ConsumerStatefulWidget {
  const InspectionCreateScreen({super.key, this.initialAssetId, this.initialAssetName});

  final int? initialAssetId;
  final String? initialAssetName;

  @override
  ConsumerState<InspectionCreateScreen> createState() => _InspectionCreateScreenState();
}

class _InspectionCreateScreenState extends ConsumerState<InspectionCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  InspectionPriority _selectedPriority = InspectionPriority.medium;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(inspectionRepositoryProvider).createInspection(
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim(),
            priority: _selectedPriority.code,
            assetId: widget.initialAssetId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspection logged successfully!'), backgroundColor: AppTheme.railwayGreen),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to log inspection: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Field Inspection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.initialAssetName != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.railwayBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.railwayBlue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.build_circle_outlined, color: AppTheme.railwayBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Target Asset: ${widget.initialAssetName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.railwayBlue),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                key: const Key('inspection_title_field'),
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Inspection Title *', hintText: 'e.g. Monthly EB Bunk Inspection', border: OutlineInputBorder()),
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InspectionPriority>(
                key: const Key('inspection_priority_dropdown'),
                value: _selectedPriority,
                decoration: const InputDecoration(labelText: 'Priority *', border: OutlineInputBorder()),
                items: InspectionPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(p.displayName))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPriority = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('inspection_description_field'),
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Detailed Findings *', hintText: 'Observations, measurements, and corrective actions required', border: OutlineInputBorder(), alignLabelWithHint: true),
                maxLines: 4,
                validator: (val) => val == null || val.trim().isEmpty ? 'Please enter detailed findings' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('submit_inspection_button'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.railwayBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Submit Inspection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
