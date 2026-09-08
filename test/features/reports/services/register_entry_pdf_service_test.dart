import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';
import 'package:gssms_mobile/features/reports/services/register_entry_pdf_service.dart';

void main() {
  test('builds a non-empty PDF for a register entry with grouped items', () async {
    const entry = MaintenanceRegisterEntry(
      id: 1,
      masterName: 'MTUR-202608-0016',
      depotName: 'Vriddhachalam Depot',
      technician: 'gmani',
      supervisor: 'vri',
      items: [
        RegisterLineItem(
          assetName: 'EB Bunk',
          inspection: 'Check and clean the EB meter bunk',
          value: '4.2',
          status: 'DIRTY',
          statusLabel: 'Dirty',
          action: 'Cleaned',
          remarks: 'Dust build-up removed',
        ),
        RegisterLineItem(
          assetName: 'Earth Pit',
          inspection: 'Check whether 2 earth pits are available',
          statusLabel: 'Available',
          action: 'No action required',
        ),
      ],
    );

    final doc = await RegisterEntryPdfService.build(entry);
    final bytes = await doc.save();

    expect(bytes, isNotEmpty);
    // PDF file signature — confirms this is a real document, not an empty
    // or malformed byte stream that would silently fail to open on device.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('builds a PDF for an entry with no line items without throwing', () async {
    const entry = MaintenanceRegisterEntry(id: 2, masterName: 'Empty Register');

    final doc = await RegisterEntryPdfService.build(entry);
    final bytes = await doc.save();

    expect(bytes, isNotEmpty);
  });
}
