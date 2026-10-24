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
import '../features/work_orders/presentation/screens/offline_work_screen.dart';

class GssmsApp extends ConsumerStatefulWidget {
  const GssmsApp({super.key});

  @override
  ConsumerState<GssmsApp> createState() => _GssmsAppState();
}

class _GssmsAppState extends ConsumerState<GssmsApp>
    with WidgetsBindingObserver {
  ProviderSubscription<AuthState>? _authSub;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Subscribe once (not in build) — replay queued work when a session
    // becomes available instead of waiting for a new mutation.
    _authSub =
        ref.listenManual<AuthState>(authControllerProvider, (previous, next) {
      if (next is! Authenticated && previous is Authenticated) {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
      if (next is Authenticated &&
          !next.session.isOffline &&
          (previous is! Authenticated || previous.session.isOffline)) {
        unawaited(ref.read(syncManagerProvider.notifier).resumePendingSync());
      }
    });
    // Attempt automatic session restoration on app launch
    Future.microtask(() {
      unawaited(ref.read(authControllerProvider.notifier).restoreSession());
    });
  }

  @override
  void dispose() {
    _authSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the moment connectivity has most
    // likely changed (walked back into coverage, Wi-Fi reconnected).
    final auth = ref.read(authControllerProvider);
    if (state == AppLifecycleState.resumed && auth is Authenticated) {
      if (auth.session.isOffline) {
        unawaited(ref
            .read(authControllerProvider.notifier)
            .reconnectOfflineSession());
      } else {
        unawaited(ref.read(syncManagerProvider.notifier).resumePendingSync());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(authControllerProvider.select(_phaseOf));
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'GSSMS Mobile',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      home: _buildHomeForPhase(phase),
    );
  }

  static _AuthPhase _phaseOf(AuthState state) {
    if (state is Authenticated) {
      return state.session.isOffline
          ? _AuthPhase.offline
          : _AuthPhase.authenticated;
    }
    if (state is AuthInitial ||
        (state is AuthLoading && state.message == 'Restoring session...')) {
      return _AuthPhase.startup;
    }
    return _AuthPhase.login;
  }

  Widget _buildHomeForPhase(_AuthPhase phase) {
    switch (phase) {
      case _AuthPhase.offline:
        return const OfflineWorkScreen();
      case _AuthPhase.authenticated:
        final state = ref.read(authControllerProvider);
        if (state is Authenticated) {
          return HomeScreen(session: state.session, autoLoadData: true);
        }
        return const LoginScreen();
      case _AuthPhase.startup:
        return const _StartupView();
      case _AuthPhase.login:
        return const LoginScreen();
    }
  }
}

enum _AuthPhase { authenticated, offline, startup, login }

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
