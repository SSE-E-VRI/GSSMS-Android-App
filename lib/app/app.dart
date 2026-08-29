import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import '../features/auth/presentation/controllers/auth_state.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';

class GssmsApp extends ConsumerStatefulWidget {
  const GssmsApp({super.key});

  @override
  ConsumerState<GssmsApp> createState() => _GssmsAppState();
}

class _GssmsAppState extends ConsumerState<GssmsApp> {
  @override
  void initState() {
    super.initState();
    // Attempt automatic session restoration on app launch
    Future.microtask(() {
      unawaited(ref.read(authControllerProvider.notifier).restoreSession());
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return MaterialApp(
      title: 'GSSMS Mobile',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: _buildHomeForState(authState),
    );
  }

  Widget _buildHomeForState(AuthState state) {
    if (state is Authenticated) {
      return HomeScreen(session: state.session);
    }

    if (state is AuthInitial || (state is AuthLoading && state.message == 'Restoring session...')) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Starting GSSMS Mobile...',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return const LoginScreen();
  }
}
