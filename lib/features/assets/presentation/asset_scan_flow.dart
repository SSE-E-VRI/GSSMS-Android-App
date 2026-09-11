import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_list_screen.dart';
import 'package:gssms_mobile/features/assets/presentation/widgets/qr_scanner_dialog.dart';

/// Scan (or type) an asset code from anywhere and open that asset.
///
/// Resolution is the SSOT §29 workflow — `GET /assets/?search=<code>` then an
/// exact `unique_id`/serial match (see `scanOrFindAssetByCode`); a partial
/// match is never auto-selected. On no exact match the user lands on the
/// Asset Registry pre-filtered by the code, so a worn label is still useful.
Future<void> scanAndOpenAsset(BuildContext context, WidgetRef ref) async {
  final scanned = await showDialog<String>(
    context: context,
    builder: (_) => const QrScannerDialog(),
  );
  final code = scanned?.trim();
  if (code == null || code.isEmpty || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LookingUpDialog(code: code),
  ));

  Asset? match;
  Object? failure;
  try {
    match = await ref.read(assetRepositoryProvider).scanOrFindAssetByCode(code);
  } catch (e) {
    failure = e;
  } finally {
    // Close the progress dialog (the route on top of the caller).
    navigator.pop();
  }

  if (match != null) {
    unawaited(navigator.push(
      MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: match!.id)),
    ));
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failure != null
            ? 'Could not look up "$code". ${userFacingError(failure)}'
            : 'No asset matches "$code" exactly.',
      ),
      action: SnackBarAction(
        label: 'Search',
        onPressed: () => navigator.push(
          MaterialPageRoute(
            builder: (_) => AssetListScreen(initialSearch: code),
          ),
        ),
      ),
    ),
  );
}

class _LookingUpDialog extends StatelessWidget {
  const _LookingUpDialog({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: GssmsSpacing.s16),
            Expanded(
              child: Text(
                'Looking up $code…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
