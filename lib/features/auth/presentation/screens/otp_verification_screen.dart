import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/auth_exceptions.dart';
import '../controllers/auth_controller.dart';
import 'otp_flow_mode.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.mode,
    required this.email,
  });

  final OtpFlowMode mode;
  final String email;

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isResending = false;
  bool _isLockedOut = false;
  String? _errorMessage;
  int? _attemptsRemaining;

  Timer? _timer;
  int _secondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
        });
      }
    });
  }

  Future<void> _onResendOtp() async {
    if (_secondsRemaining > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final purpose =
        widget.mode == OtpFlowMode.login ? 'LOGIN' : 'password_reset';

    try {
      await ref.read(authRepositoryProvider).requestOtp(
            email: widget.email,
            purpose: purpose,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Verification code resent to your email.'),
          backgroundColor: context.gssms.success.solid,
        ),
      );

      // Reset lockout and start 60s timer
      setState(() {
        _isLockedOut = false;
        _attemptsRemaining = null;
      });
      _startResendTimer();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to resend verification code.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _onSubmit() async {
    if (_isLockedOut || _isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final otp = _otpController.text.trim();

    if (widget.mode == OtpFlowMode.login) {
      try {
        await ref.read(authControllerProvider.notifier).loginWithOtp(
              widget.email,
              otp,
            );

        if (!mounted) return;
        // Pop all views back to root so GssmsApp shows HomeScreen
        Navigator.of(context).popUntil((route) => route.isFirst);
      } on InvalidOtpException catch (e) {
        if (mounted) {
          setState(() {
            _attemptsRemaining = e.attemptsRemaining;
            _errorMessage = e.message;
            if (e.attemptsRemaining != null && e.attemptsRemaining! <= 0) {
              _isLockedOut = true;
            }
          });
        }
      } on OtpLockoutException catch (e) {
        if (mounted) {
          setState(() {
            _isLockedOut = true;
            _attemptsRemaining = 0;
            _errorMessage = e.message;
          });
        }
      } on AuthException catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.message;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _errorMessage = 'An unexpected error occurred during OTP login.';
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      // Forgot password flow
      final newPassword = _newPasswordController.text;
      try {
        await ref.read(authRepositoryProvider).resetPasswordWithOtp(
              email: widget.email,
              otp: otp,
              newPassword: newPassword,
            );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Password reset successfully. Please sign in with your new password.'),
            backgroundColor: context.gssms.success.solid,
          ),
        );

        Navigator.of(context).popUntil((route) => route.isFirst);
      } on InvalidOtpException catch (e) {
        if (mounted) {
          setState(() {
            _attemptsRemaining = e.attemptsRemaining;
            _errorMessage = e.message;
            if (e.attemptsRemaining != null && e.attemptsRemaining! <= 0) {
              _isLockedOut = true;
            }
          });
        }
      } on OtpLockoutException catch (e) {
        if (mounted) {
          setState(() {
            _isLockedOut = true;
            _attemptsRemaining = 0;
            _errorMessage = e.message;
          });
        }
      } on AuthException catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.message;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to reset password. Please try again.';
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = widget.mode == OtpFlowMode.login;
    final title = isLogin ? 'Verify Sign-In Code' : 'Reset Password';
    final submitButtonText = isLogin ? 'Sign In' : 'Reset Password';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header icon
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: context.gssms.info.background,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mark_email_read_rounded,
                          size: 32,
                          color: context.gssms.link,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: context.gssms.textPrimary,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Subtitle with email
                    Text(
                      'Enter the 6-digit code sent to\n${widget.email}',
                      style: TextStyle(
                        fontSize: 14,
                        color: context.gssms.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Expiry Notice
                    Center(
                      child: Container(
                        key: const Key('otp_expiry_notice'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.gssms.border.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 16, color: context.gssms.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Expires in 10 minutes',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.gssms.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error banner
                    if (_errorMessage != null) ...[
                      _buildErrorBanner(_errorMessage!),
                      const SizedBox(height: 16),
                    ],

                    // Attempts remaining indicator
                    if (_attemptsRemaining != null &&
                        _attemptsRemaining! > 0 &&
                        !_isLockedOut) ...[
                      Container(
                        key: const Key('otp_attempts_remaining_text'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.gssms.warning.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: context.gssms.warning.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 18, color: context.gssms.warning.foreground),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_attemptsRemaining attempt${_attemptsRemaining != 1 ? 's' : ''} remaining before lockout.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.gssms.warning.foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // OTP Input Field
                    TextFormField(
                      key: const Key('otp_code_field'),
                      controller: _otpController,
                      enabled: !_isLockedOut && !_isLoading,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                      decoration: const InputDecoration(
                        labelText: '6-digit OTP code',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Enter the 6-digit verification code';
                        }
                        if (val.trim().length != 6) {
                          return 'Code must be exactly 6 digits';
                        }
                        return null;
                      },
                    ),

                    // Additional fields for Forgot Password
                    if (widget.mode == OtpFlowMode.forgotPassword) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('otp_new_password_field'),
                        controller: _newPasswordController,
                        obscureText: _obscureNewPassword,
                        enabled: !_isLockedOut && !_isLoading,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscureNewPassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscureNewPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureNewPassword = !_obscureNewPassword;
                              });
                            },
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Enter a new password';
                          }
                          if (val.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('otp_confirm_password_field'),
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        enabled: !_isLockedOut && !_isLoading,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscureConfirmPassword
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Confirm your new password';
                          }
                          if (val != _newPasswordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Submit button
                    ElevatedButton(
                      key: const Key('otp_verify_submit_button'),
                      onPressed: (_isLockedOut || _isLoading) ? null : _onSubmit,
                      child: _isLoading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : Text(submitButtonText),
                    ),
                    const SizedBox(height: 20),

                    // Resend countdown & button
                    Center(
                      child: _secondsRemaining > 0
                          ? Text(
                              'Resend code in ${_secondsRemaining}s',
                              key: const Key('otp_resend_countdown_text'),
                              style: TextStyle(
                                fontSize: 14,
                                color: context.gssms.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : TextButton.icon(
                              key: const Key('otp_resend_button'),
                              onPressed: _isResending ? null : _onResendOtp,
                              icon: _isResending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Resend Code'),
                            ),
                    ),
                    const SizedBox(height: 8),

                    // Back button
                    TextButton(
                      key: const Key('otp_verify_back_button'),
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Back'),
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

  Widget _buildErrorBanner(String message) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('otp_error_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.gssms.danger.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.gssms.danger.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: context.gssms.danger.foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: context.gssms.danger.foreground,
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
