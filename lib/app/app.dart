import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/sync/sync_manager.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/controllers/auth_state.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';

class GssmsApp extends ConsumerStatefulWidget {
  const GssmsApp({super.key});

  @override
  ConsumerState<GssmsApp> createState() => _GssmsAppState();
}

class _GssmsAppState extends ConsumerState<GssmsApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Attempt automatic session restoration on app launch
    Future.microtask(() {
      unawaited(ref.read(authControllerProvider.notifier).restoreSession());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment connectivity has most
    // likely changed (walked back into coverage, Wi-Fi reconnected).
    if (state == AppLifecycleState.resumed &&
        ref.read(authControllerProvider) is Authenticated) {
      unawaited(ref.read(syncManagerProvider.notifier).resumePendingSync());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Replay work queued before a restart as soon as a session is available
    // (restored or freshly signed in) instead of waiting for a new mutation.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is Authenticated && previous is! Authenticated) {
        unawaited(ref.read(syncManagerProvider.notifier).resumePendingSync());
      }
    });

    final authState = ref.watch(authControllerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'GSSMS Mobile',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: _buildHomeForState(authState),
    );
  }

  Widget _buildHomeForState(AuthState state) {
    if (state is Authenticated) {
      return HomeScreen(session: state.session, autoLoadData: true);
    }

    if (state is AuthInitial ||
        (state is AuthLoading && state.message == 'Restoring session...')) {
      return const _StartupView();
    }

    return const LoginScreen();
  }
}

class _StartupView extends StatelessWidget {
  const _StartupView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: GssmsSpacing.s16),
            Text(
              'Starting GSSMS Mobile...',
              style: TextStyle(color: context.gssms.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
