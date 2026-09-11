import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/services/profile_photo_cache.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/profile_avatar.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, this.imagePicker});

  final ImagePicker? imagePicker;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _designationController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _uploadingPhoto = false;
  UserProfile? _profile;
  String _username = '';
  String _role = '';
  String? _banner;
  bool _bannerError = false;

  Color get _fieldFill => context.gssms.surfaceInset;
  Color get _border => context.gssms.border;

  IAuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(_onPasswordChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newPasswordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _phoneController.dispose();
    _designationController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _banner = null;
    });
    try {
      final profile = await _repo.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _username = profile.username;
        _role = profile.role;
        _emailController.text = profile.email;
        _phoneController.text = profile.phoneNumber;
        _designationController.text = profile.designation;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _banner = e.message;
        _bannerError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _banner = 'Failed to load profile.';
        _bannerError = true;
      });
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  'Profile Photo',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.gssms.textPrimary,
                      ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('photo_option_camera'),
                leading: Icon(Icons.camera_alt, color: context.gssms.link),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadPhoto(ImageSource.camera);
                },
              ),
              ListTile(
                key: const Key('photo_option_gallery'),
                leading: Icon(Icons.photo_library, color: context.gssms.link),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadPhoto(ImageSource.gallery);
                },
              ),
              if (_profile?.profilePicture != null && _profile!.profilePicture!.isNotEmpty)
                ListTile(
                  key: const Key('photo_option_remove'),
                  leading: Icon(Icons.delete_outline, color: context.gssms.danger.foreground),
                  title: Text(
                    'Remove Photo',
                    style: TextStyle(color: context.gssms.danger.foreground),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _removePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    final picker = widget.imagePicker ?? ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _uploadingPhoto = true;
      _banner = null;
    });

    try {
      final updated = await _repo.updateUserPhoto(picked.path);
      final userId = updated.id != 0 ? updated.id : (_profile?.id ?? 0);
      if (userId != 0) {
        // Tag the local copy with the URL the server just assigned, so the
        // very next lookup for that URL is a hit instead of a re-download.
        await ref.read(profilePhotoCacheProvider).cacheLocalFile(
              userId,
              picked.path,
              photoUrl: updated.profilePicture,
            );
      }
      ref
          .read(authControllerProvider.notifier)
          .updateSessionProfilePicture(updated.profilePicture);

      if (!mounted) return;
      setState(() {
        _profile = updated;
        _uploadingPhoto = false;
        _banner = 'Profile photo updated successfully!';
        _bannerError = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _banner = e.message;
        _bannerError = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _banner = 'Could not upload photo: ${userFacingError(e)}';
        _bannerError = true;
      });
    }
  }

  Future<void> _removePhoto() async {
    setState(() {
      _uploadingPhoto = true;
      _banner = null;
    });

    try {
      final updated = await _repo.updateUserPhoto(null);
      final userId = updated.id != 0 ? updated.id : (_profile?.id ?? 0);
      if (userId != 0) {
        await ref.read(profilePhotoCacheProvider).clearCachedPhoto(userId);
      }
      ref
          .read(authControllerProvider.notifier)
          .updateSessionProfilePicture(null);

      if (!mounted) return;
      setState(() {
        _profile = updated;
        _uploadingPhoto = false;
        _banner = 'Profile photo removed.';
        _bannerError = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _banner = e.message;
        _bannerError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _banner = 'Failed to remove photo.';
        _bannerError = true;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _savingProfile = true;
      _banner = null;
    });
    try {
      final updated = await _repo.updateProfile(
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        designation: _designationController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _savingProfile = false;
        _banner = 'Profile updated successfully!';
        _bannerError = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
        _banner = e.message;
        _bannerError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
        _banner = 'Failed to update profile.';
        _bannerError = true;
      });
    }
  }

  Future<void> _updatePassword() async {
    final next = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (next.isEmpty) {
      setState(() {
        _banner = 'Enter a new password.';
        _bannerError = true;
      });
      return;
    }
    if (next != confirm) {
      setState(() {
        _banner = 'New passwords do not match.';
        _bannerError = true;
      });
      return;
    }

    setState(() {
      _savingPassword = true;
      _banner = null;
    });
    try {
      await _repo.changePassword(next);
      if (!mounted) return;
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() {
        _savingPassword = false;
        _banner = 'Password changed successfully.';
        _bannerError = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
        _banner = e.message;
        _bannerError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
        _banner = 'Failed to change password.';
        _bannerError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gssms.surfaceInset,
      appBar: AppBar(title: const Text('User Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text(
                        'User Profile',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_banner != null) ...[
                            _bannerBox(_banner!, error: _bannerError),
                            const SizedBox(height: 16),
                          ],
                          Center(
                            child: ProfileAvatar(
                              key: const Key('user_profile_avatar'),
                              userId: _profile?.id,
                              photoUrl: _profile?.profilePicture,
                              displayName: _username,
                              radius: 48,
                              isUploading: _uploadingPhoto,
                              onCameraTap: _showPhotoOptions,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_username.isNotEmpty) ...[
                            Center(
                              child: Text(
                                _username,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.gssms.textPrimary,
                                ),
                              ),
                            ),
                            if (_role.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.gssms.neutral.solid,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _role,
                                    style: TextStyle(
                                      color: context.gssms.neutral.onSolid,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],
                          Text(
                            'Personal Information',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.gssms.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _labeledField(
                            label: 'Email',
                            child: TextField(
                              key: const Key('profile_email_field'),
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _labeledField(
                            label: 'Phone',
                            child: TextField(
                              key: const Key('profile_phone_field'),
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: _inputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _labeledField(
                            label: 'Designation',
                            child: TextField(
                              key: const Key('profile_designation_field'),
                              controller: _designationController,
                              decoration: _inputDecoration(
                                hint: 'Enter your designation',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const Key('profile_save_changes_button'),
                              onPressed: _savingProfile ? null : _saveProfile,
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              child: _savingProfile
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(context).colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Text('Save Changes'),
                            ),
                          ),
                          const Divider(height: 32),
                          Text(
                            'Change Password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.gssms.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _labeledField(
                            label: 'New Password',
                            child: TextField(
                              key: const Key('profile_new_password_field'),
                              controller: _newPasswordController,
                              obscureText: true,
                              decoration: _inputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _labeledField(
                            label: 'Confirm Password',
                            child: TextField(
                              key: const Key('profile_confirm_password_field'),
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: _inputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const Key('profile_update_password_button'),
                              onPressed: _savingPassword ||
                                      _newPasswordController.text.isEmpty
                                  ? null
                                  : _updatePassword,
                              style: FilledButton.styleFrom(
                                backgroundColor: context.gssms.warning.solid,
                                foregroundColor: context.gssms.textPrimary,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text('Update Password'),
                            ),
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

  Widget _bannerBox(String text, {required bool error}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: error ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? Colors.red.shade800 : Colors.green.shade800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _labeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.gssms.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _border),
      ),
    );
  }
}
