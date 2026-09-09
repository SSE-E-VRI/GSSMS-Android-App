import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_theme.dart';

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({
    super.key,
    this.startInManualMode = false,
  });

  /// In test environments or when explicitly requested, open directly in manual entry mode.
  final bool startInManualMode;

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final TextEditingController _codeController = TextEditingController();
  late final MobileScannerController _scannerController;

  bool _isManualMode = false;
  bool _hasDetected = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    _isManualMode = widget.startInManualMode;
    _scannerController = MobileScannerController(
      formats: const [
        BarcodeFormat.qrCode,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
      ],
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _hasDetected = true;
        Navigator.of(context).pop(code);
        break;
      }
    }
  }

  void _onSubmitManualCode() {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      Navigator.of(context).pop(code);
    }
  }

  Future<void> _toggleTorch() async {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    try {
      await _scannerController.toggleTorch();
    } catch (_) {
      // Camera may be unavailable or permission denied; the scanner
      // errorBuilder already surfaces an actionable message for that.
      if (mounted) {
        setState(() {
          _torchEnabled = !_torchEnabled;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                color: AppTheme.primaryDark,
                child: Row(
                  children: [
                    Icon(
                      _isManualMode
                          ? Icons.keyboard_alt_outlined
                          : Icons.qr_code_scanner_rounded,
                      color: AppTheme.accentOrange,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isManualMode ? 'Enter Asset Code' : 'Scan Asset Label',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                      ),
                    ),
                    if (!_isManualMode)
                      IconButton(
                        icon: Icon(
                          _torchEnabled ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                        ),
                        tooltip: 'Toggle Flashlight',
                        onPressed: _toggleTorch,
                      ),
                    IconButton(
                      key: const Key('cancel_scanner_button'),
                      icon: const Icon(Icons.close, color: Colors.white70),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Content Body (Scanner or Manual Input)
              Flexible(
                child: _isManualMode
                    ? _buildManualInputView()
                    : _buildScannerView(),
              ),

              // Bottom Toggle Action
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: AppTheme.backgroundLight,
                  border: Border(
                    top: BorderSide(color: AppTheme.borderGrey),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: !_isManualMode
                          ? TextButton.icon(
                              key: const Key('toggle_manual_entry_button'),
                              onPressed: () {
                                setState(() {
                                  _isManualMode = true;
                                });
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text(
                                'Enter Code Manually',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                              : TextButton.icon(
                                  key: const Key('toggle_camera_button'),
                                  onPressed: () {
                                    setState(() {
                                      _isManualMode = false;
                                    });
                                  },
                              icon: const Icon(Icons.camera_alt_outlined, size: 18),
                              label: const Text(
                                'Scan with Camera',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerView() {
    return SizedBox(
      height: 380,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              final isPermission =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              final msg = isPermission
                  ? 'Camera permission denied. Please grant camera access in Settings, or enter the code manually below.'
                  : 'Unable to start camera scanner: ${error.errorDetails?.message ?? error.errorCode.name}. Please enter the code manually.';
              return _buildCameraErrorView(msg);
            },
          ),
          // Viewfinder reticle
          _buildReticleOverlay(),
          // Hint overlay at bottom
          Positioned(
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Align QR code or Code128 barcode in box',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReticleOverlay() {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.accentOrange, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // Corner accents
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.successGreen, width: 4),
                  left: BorderSide(color: AppTheme.successGreen, width: 4),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.successGreen, width: 4),
                  right: BorderSide(color: AppTheme.successGreen, width: 4),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.successGreen, width: 4),
                  left: BorderSide(color: AppTheme.successGreen, width: 4),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.successGreen, width: 4),
                  right: BorderSide(color: AppTheme.successGreen, width: 4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraErrorView(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 48,
            color: AppTheme.warningAmber,
          ),
          const SizedBox(height: 16),
          Text(
            'Camera Unavailable',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            key: const Key('camera_error_enter_manual_button'),
            onPressed: () {
              setState(() {
                _isManualMode = true;
              });
            },
            icon: const Icon(Icons.keyboard),
            label: const Text('Enter Code Manually'),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'For damaged, faded, or unreadable labels, enter the asset identifier directly.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('manual_code_input'),
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Asset / Serial Code',
              hintText: 'e.g. VRI-SS01-HTSTR-2POLE-001',
              prefixIcon: Icon(Icons.tag),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _onSubmitManualCode(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            key: const Key('confirm_code_lookup_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.railwayBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _onSubmitManualCode,
            child: const Text('Lookup Asset'),
          ),
        ],
      ),
    );
  }
}
