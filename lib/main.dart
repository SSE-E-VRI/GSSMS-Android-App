import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      retry: _noRetry,
      child: const GssmsApp(),
    ),
  );
}

/// Riverpod 3 auto-retries failed providers (up to 10x, exponential backoff)
/// by default. This app already has its own deliberate, visible retry/offline
/// story for mutations (SyncManager's outbox) and surfaces read failures
/// immediately (e.g. the Deficiencies tile's "View deficiencies" fallback) —
/// a silent multi-attempt retry would leave screens stuck on a loading state
/// for up to ~35s instead of honestly showing the failure. Disable it to keep
/// Riverpod 2's single-attempt behavior.
Duration? _noRetry(int retryCount, Object error) => null;
