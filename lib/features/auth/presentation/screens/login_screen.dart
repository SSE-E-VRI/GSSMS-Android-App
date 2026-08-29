import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/auth_controller.dart';
import '../controllers/auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    if (_formKey.currentState?.validate() ?? false) {
      ref.read(authControllerProvider.notifier).login(
            _usernameController.text,
            _passwordController.text,
          );
    }
  }

  void _onOtpSubmitPressed() {
    if (_otpFormKey.currentState?.validate() ?? false) {
      ref.read(authControllerProvider.notifier).submitOtp(_otpController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isGeneralLoading = authState is AuthLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Branding
                  _buildHeader(),
                  const SizedBox(height: 32),

                  // State-specific UI: OtpRequired stays visible during OTP submit
                  if (authState is OtpRequired)
                    _buildOtpChallengeView(authState)
                  else
                    _buildStandardLoginForm(authState, isGeneralLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.primaryDark,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.electric_bolt_rounded,
            size: 40,
            color: AppTheme.accentOrange,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'GSSMS Mobile',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'General Service Smart Management System',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStandardLoginForm(AuthState authState, bool isLoading) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (authState is AuthError) ...[
            _buildErrorBanner(authState.message),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('login_username_field'),
            controller: _usernameController,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            validator: (val) =>
                val == null || val.trim().isEmpty ? 'Enter your username' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('login_password_field'),
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _onLoginPressed(),
            validator: (val) =>
                val == null || val.isEmpty ? 'Enter your password' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            key: const Key('login_submit_button'),
            onPressed: isLoading ? null : _onLoginPressed,
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpChallengeView(OtpRequired state) {
    final isSubmitting = state.isSubmitting;

    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.security, color: Colors.amber.shade900),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Two-Factor Authentication required. Enter the 6-digit code from your authenticator app.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (state.errorMessage != null) ...[
            _buildErrorBanner(state.errorMessage!),
            const SizedBox(height: 16),
          ],
          TextFormField(
            key: const Key('login_otp_field'),
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              labelText: '2FA Code',
              counterText: '',
              prefixIcon: Icon(Icons.pin),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Enter the 6-digit code';
              }
              if (val.trim().length != 6) {
                return 'Code must be 6 digits';
              }
              return null;
            },
            onFieldSubmitted: (_) => _onOtpSubmitPressed(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            key: const Key('login_otp_submit_button'),
            onPressed: isSubmitting ? null : _onOtpSubmitPressed,
            child: isSubmitting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Verify & Continue'),
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('login_otp_cancel_button'),
            onPressed: isSubmitting
                ? null
                : () {
                    _otpController.clear();
                    ref.read(authControllerProvider.notifier).cancelOtp();
                  },
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.errorRed.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.errorRed.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppTheme.errorRed,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
