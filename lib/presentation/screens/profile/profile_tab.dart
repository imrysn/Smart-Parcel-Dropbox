import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import '../../../config/user_theme.dart';
import '../../../screens/access_log_screen.dart';
import '../../../screens/login_screen.dart';
import '../../../screens/logs_screen.dart';
import '../../../services/auth_service.dart';
import '../../../services/biometric_service.dart';
import '../../../services/database_service.dart';
import '../../../services/input_validator.dart';
import '../../../widgets/startup_intro.dart';
import '../../../widgets/user_ui.dart';

/// Profile Tab
///
/// Clean, modularized Profile view displaying user identity, contact info,
/// security and biometric lock toggles, developer options, and account actions.
class ProfileTab extends StatefulWidget {
  final String userId;
  final DatabaseService databaseService;
  final AuthService authService;
  final BiometricService biometricService;
  final bool devModeEnabled;
  final bool devModeBusy;
  final bool supportsDevMode;
  final ValueChanged<bool>? onDevModeChanged;

  const ProfileTab({
    super.key,
    required this.userId,
    required this.databaseService,
    required this.authService,
    required this.biometricService,
    this.devModeEnabled = false,
    this.devModeBusy = false,
    this.supportsDevMode = false,
    this.onDevModeChanged,
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Future<Map<String, dynamic>?>? _userDataFuture;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _checkBiometrics();
  }

  void _loadProfileData() {
    setState(() {
      _userDataFuture = widget.databaseService.getUserData(widget.userId);
    });
  }

  Future<void> _checkBiometrics() async {
    final enabled = await widget.authService.isBiometricLockEnabled();
    final available = await widget.biometricService.isBiometricAvailable();
    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _biometricAvailable = available;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white : Colors.black;
    final primaryText =
        isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText =
        isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: isDark ? Colors.white : Colors.black,
            ),
          );
        }

        Map<String, dynamic>? userData = snapshot.data;
        final fullName = (userData?['fullName'] as String?)?.trim();
        final email = (userData?['email'] as String?)?.trim() ?? '';
        final profileImage = (userData?['profileImage'] as String?)?.trim();
        final initial = (fullName != null && fullName.isNotEmpty)
            ? fullName[0].toUpperCase()
            : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

        return SingleChildScrollView(
          padding: UserUi.listPadding(context, top: 20, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Minimalist Profile Identity Header (Solid Black 0% Transparency Border)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? UserTheme.nightCard : Colors.white,
                  borderRadius: BorderRadius.circular(UserTheme.radiusL),
                  border: Border.all(
                    color: borderColor,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    _buildAvatar(context, initial, profileImage, isDark),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (fullName != null && fullName.isNotEmpty)
                                ? fullName
                                : 'Smart User',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: primaryText,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Contact information',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: primaryText,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? UserTheme.nightCard : Colors.white,
                  borderRadius: BorderRadius.circular(UserTheme.radiusL),
                  border: Border.all(
                    color: borderColor,
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.phone_android_rounded,
                      title: 'Phone number',
                      value: userData?['phoneNumber'] ?? 'Not set',
                      isEmpty: userData?['phoneNumber'] == null ||
                          (userData?['phoneNumber'] as String).isEmpty,
                      isEditable: true,
                      fieldKey: 'phoneNumber',
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.location_on_outlined,
                      title: 'Home address',
                      value: userData?['address'] ?? 'Not set',
                      isEmpty: userData?['address'] == null ||
                          (userData?['address'] as String).isEmpty,
                      isEditable: true,
                      fieldKey: 'address',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Activity & security',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: primaryText,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? UserTheme.nightCard : Colors.white,
                  borderRadius: BorderRadius.circular(UserTheme.radiusL),
                  border: Border.all(
                    color: borderColor,
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.alternate_email_rounded,
                      title: 'Email identifier',
                      value: email.isNotEmpty ? email : 'Not available',
                      isEmpty: email.isEmpty,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.verified_user_outlined,
                      title: 'Account status',
                      value: 'Identity verified',
                      isEmpty: false,
                      showValueIcon: true,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.qr_code_2_rounded,
                      title: 'Parcel scan logs',
                      value: 'Courier drop-off & pickup history',
                      isEmpty: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.history_rounded,
                      title: 'Owner access history',
                      value: 'Door unlocks & QR owner verifications',
                      isEmpty: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AccessLogScreen()),
                      ),
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.lock_reset_rounded,
                      title: 'Password',
                      value: 'Update account password',
                      isEmpty: false,
                      onTap: _showChangePasswordDialog,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: 20,
                            color: secondaryText,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Biometric app lock',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: primaryText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _biometricAvailable
                                      ? 'Require Face ID or fingerprint on launch'
                                      : 'Available on supported Android & iOS devices',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? UserTheme.nightTextMuted
                                        : UserTheme.dayTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _biometricEnabled && _biometricAvailable,
                            activeTrackColor: isDark ? Colors.white : Colors.black,
                            activeThumbColor: isDark ? Colors.black : Colors.white,
                            onChanged: _biometricAvailable
                                ? _toggleBiometricLock
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.supportsDevMode) ...[
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? UserTheme.nightCard : Colors.white,
                    borderRadius: BorderRadius.circular(UserTheme.radiusL),
                    border: Border.all(
                      color: borderColor,
                      width: 1.0,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          secondary: Icon(
                            Icons.science_outlined,
                            size: 20,
                            color: secondaryText,
                          ),
                          title: Text(
                            'Dev mode',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primaryText,
                            ),
                          ),
                          subtitle: Text(
                            'Replay the intro on launch and simulate weather and time of day in Dropbox.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? UserTheme.nightTextMuted
                                  : UserTheme.dayTextMuted,
                            ),
                          ),
                          value: widget.devModeEnabled,
                          activeTrackColor: isDark ? Colors.white : Colors.black,
                          activeThumbColor: isDark ? Colors.black : Colors.white,
                          onChanged: widget.devModeBusy
                              ? null
                              : widget.onDevModeChanged,
                        ),
                        if (widget.devModeEnabled)
                          ListTile(
                            leading: Icon(
                              Icons.play_circle_outline_rounded,
                              size: 20,
                              color: secondaryText,
                            ),
                            title: Text(
                              'Replay startup intro',
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (routeContext) => StartupIntro(
                                  showEndCard: true,
                                  onFinished: (_) {
                                    if (ModalRoute.of(routeContext)?.isCurrent == true) {
                                      Navigator.of(routeContext).pop();
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(UserTheme.radiusL),
                  border: Border.all(
                    color: borderColor,
                    width: 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _logout,
                    borderRadius: BorderRadius.circular(UserTheme.radiusL),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            color: isDark ? Colors.white : Colors.black,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Log out',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _confirmDeleteAccount,
                  child: Text(
                    'Delete account',
                    style: TextStyle(
                      color: isDark
                          ? UserTheme.nightTextMuted
                          : UserTheme.dayTextMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(
    BuildContext context,
    String initial,
    String? profileImage,
    bool isDark,
  ) {
    final borderColor = isDark ? Colors.white : Colors.black;
    final textColor = isDark ? Colors.white : Colors.black;

    Widget imageWidget;
    final hasImage = profileImage != null && profileImage.trim().isNotEmpty;

    if (hasImage) {
      if (profileImage.startsWith('data:image') || !profileImage.startsWith('http')) {
        try {
          final cleanBase64 = profileImage.contains(',')
              ? profileImage.split(',').last
              : profileImage;
          imageWidget = Image.memory(
            base64Decode(cleanBase64),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackInitial(initial, textColor),
          );
        } catch (_) {
          imageWidget = _buildFallbackInitial(initial, textColor);
        }
      } else {
        imageWidget = CachedNetworkImage(
          imageUrl: profileImage,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          placeholder: (_, __) => Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
            ),
          ),
          errorWidget: (_, __, ___) => _buildFallbackInitial(initial, textColor),
        );
      }
    } else {
      imageWidget = _buildFallbackInitial(initial, textColor);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _pickAndUploadPhoto(profileImage),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? UserTheme.nightCard : Colors.white,
              borderRadius: BorderRadius.circular(UserTheme.radiusL),
              border: Border.all(
                color: borderColor,
                width: 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageWidget,
          ),
        ),
        Positioned(
          bottom: -4,
          right: -4,
          child: GestureDetector(
            onTap: () => _pickAndUploadPhoto(profileImage),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? Colors.black : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: borderColor,
                  width: 1.0,
                ),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 13,
                color: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackInitial(String initial, Color textColor) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(String? currentPhoto) async {
    final primaryText = UserUi.dashboardColors(context).foreground;
    final bool isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    final source = await UserUi.showDashboardSheet<ImageSource?>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Profile photo',
                style: Theme.of(bottomSheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              if (!isDesktop)
                ListTile(
                  leading:
                      Icon(Icons.photo_camera_outlined, color: primaryText),
                  title: Text('Take photo',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: primaryText)),
                  onTap: () =>
                      Navigator.of(bottomSheetContext).pop(ImageSource.camera),
                ),
              ListTile(
                leading: Icon(
                    isDesktop
                        ? Icons.folder_open_rounded
                        : Icons.photo_library_outlined,
                    color: primaryText),
                title: Text(
                    isDesktop ? 'Choose image file' : 'Choose from gallery',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: primaryText)),
                onTap: () =>
                    Navigator.of(bottomSheetContext).pop(ImageSource.gallery),
              ),
              if (currentPhoto != null && currentPhoto.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: UserTheme.statusError),
                  title: const Text('Remove photo',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: UserTheme.statusError)),
                  onTap: () async {
                    Navigator.of(bottomSheetContext).pop();
                    await _removePhoto();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (file == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updating profile photo...'),
          duration: Duration(seconds: 1),
        ),
      );

      final bytes = await file.readAsBytes();
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      await widget.databaseService.updateUserProfile(
        userId: widget.userId,
        profileImage: base64String,
      );

      if (mounted) {
        _loadProfileData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully'),
            backgroundColor: UserTheme.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String message = 'Failed to update photo: $e';
        if (e is PlatformException &&
            (e.code == 'channel-error' ||
                e.message?.contains('FileSelectorApi') == true)) {
          message =
              'Please restart the app to link the Windows file picker plugin.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: UserTheme.statusError,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _removePhoto() async {
    try {
      await widget.databaseService.updateUserProfile(
        userId: widget.userId,
        profileImage: '',
      );
      if (mounted) {
        _loadProfileData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo removed'),
            backgroundColor: UserTheme.statusSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove photo: $e'),
            backgroundColor: UserTheme.statusError,
          ),
        );
      }
    }
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required bool isEmpty,
    bool showValueIcon = false,
    bool isEditable = false,
    String? fieldKey,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor =
        isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final mutedColor =
        isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;

    final VoidCallback? effectiveTap = onTap ??
        (isEditable && fieldKey != null
            ? () => _showEditDialog(context, title, fieldKey, value, isEmpty)
            : null);

    return InkWell(
      onTap: effectiveTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: secondaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isEmpty
                                ? mutedColor
                                : (isDark
                                    ? UserTheme.nightTextPrimary
                                    : UserTheme.dayTextPrimary),
                          ),
                        ),
                      ),
                      if (showValueIcon) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            size: 15, color: UserTheme.statusSuccess),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isEditable)
              Icon(Icons.edit_outlined, size: 18, color: mutedColor)
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: mutedColor),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String title,
    String fieldKey,
    String currentValue,
    bool isEmpty,
  ) {
    final TextEditingController controller = TextEditingController(
      text: isEmpty ? '' : currentValue,
    );

    UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${title.toLowerCase()}'),
        scrollable: true,
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: title,
            hintText: 'Enter $title',
          ),
          keyboardType: fieldKey == 'phoneNumber'
              ? TextInputType.phone
              : TextInputType.streetAddress,
          maxLines: fieldKey == 'address' ? 3 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newValue = controller.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              if (newValue.isEmpty) {
                messenger.showSnackBar(
                  SnackBar(content: Text('$title cannot be empty')),
                );
                return;
              }

              try {
                await widget.databaseService.updateUserProfile(
                  userId: widget.userId,
                  phoneNumber: fieldKey == 'phoneNumber' ? newValue : null,
                  address: fieldKey == 'address' ? newValue : null,
                );

                if (mounted) {
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('$title updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadProfileData();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometricLock(bool enable) async {
    final messenger = ScaffoldMessenger.of(context);
    if (enable) {
      final ok = await widget.biometricService.authenticate(
        reason: 'Verify biometrics to enable app lock',
      );
      if (!ok) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Biometric verification was not completed.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    await widget.authService.setBiometricLockEnabled(enable);
    if (mounted) {
      setState(() => _biometricEnabled = enable);
      messenger.showSnackBar(
        SnackBar(
          content: Text(enable
              ? 'Biometric app lock enabled'
              : 'Biometric app lock disabled'),
          backgroundColor: UserTheme.statusSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showChangePasswordDialog() {
    final formKey = GlobalKey<FormState>();
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    final confirmController = TextEditingController();
    bool submitting = false;
    final messenger = ScaffoldMessenger.of(context);

    UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Current password'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nextController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                    validator: InputValidator.validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirm new password'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != nextController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => submitting = true);
                      final navigator = Navigator.of(dialogContext);
                      try {
                        await widget.databaseService.changePassword(
                          currentPassword: currentController.text,
                          newPassword: nextController.text,
                        );
                        if (dialogContext.mounted) navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully'),
                            backgroundColor: UserTheme.statusSuccess,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: UserTheme.statusError,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              child: Text(submitting ? 'Saving...' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    final confirmController = TextEditingController();
    bool deleting = false;
    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context);

    UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete account?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your profile, parcels, and unlinks your Dropbox access. Type DELETE below to confirm.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(hintText: 'Type DELETE'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  deleting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: deleting || confirmController.text.trim() != 'DELETE'
                  ? null
                  : () async {
                      setDialogState(() => deleting = true);
                      final dialogNav = Navigator.of(dialogContext);
                      try {
                        await widget.databaseService.deleteUser(widget.userId);
                        if (dialogContext.mounted) dialogNav.pop();
                        if (mounted) {
                          rootNavigator.pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        setDialogState(() => deleting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: UserTheme.statusError,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              style: UserUi.dashboardFilledStyle(context, destructive: true),
              child: Text(deleting ? 'Deleting...' : 'Delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout({String? message}) async {
    bool? confirm = false;

    if (message != null) {
      confirm = true;
    } else {
      confirm = await UserUi.showDashboardDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Log out?'),
          scrollable: true,
          content: const Text(
              'You’ll need to sign in again to manage your Dropbox.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Log out'),
            ),
          ],
        ),
      );
    }

    if (confirm == true) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await widget.authService.signOut();
      if (mounted) {
        if (message != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
            ),
          );
        }
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
