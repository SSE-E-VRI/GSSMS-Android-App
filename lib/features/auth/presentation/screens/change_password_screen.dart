import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty) {
      setState(() => _error = 'Current password is required.');
      return;
    }
    if (next.isEmpty) {
      setState(() => _error = 'New password is required.');
      return;
    }
    if (next != confirm) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeForcedPasswordChange(
            currentPassword: current,
            newPassword: next,
          );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Failed to change password. Please try again.';
      });
    }
  }

  Future<void> _signOut() async {
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;

    return Scaffold(
      backgroundColor: tokens.surfaceInset,
      appBar: AppBar(
        title: const Text('Change Password'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            key: const Key('change_pw_sign_out_button'),
            onPressed: _submitting ? null : _signOut,
            style: TextButton.styleFrom(
              foregroundColor:
                  Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GssmsSpacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(GssmsSpacing.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Password Change Required',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: GssmsSpacing.s8),
                    Text(
                      'A password change is required for your account before you can proceed.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: GssmsSpacing.s16),
                      Container(
                        key: const Key('change_pw_error_banner'),
                        padding: const EdgeInsets.all(GssmsSpacing.s12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(GssmsRadius.r8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    ],
                    const SizedBox(height: GssmsSpacing.s16),
                    TextField(
                      key: const Key('change_pw_current_field'),
                      controller: _currentController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: GssmsSpacing.s12),
                    TextField(
                      key: const Key('change_pw_new_field'),
                      controller: _newController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: GssmsSpacing.s12),
                    TextField(
                      key: const Key('change_pw_confirm_field'),
                      controller: _confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: GssmsSpacing.s24),
                    FilledButton(
                      key: const Key('change_pw_submit_button'),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update Password'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
