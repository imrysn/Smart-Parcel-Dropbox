import 'package:flutter/material.dart';
import '../../../config/user_theme.dart';
import '../../../screens/access_log_screen.dart';
import '../../../screens/login_screen.dart';
import '../../../screens/logs_screen.dart';
import '../../../services/auth_service.dart';
import '../../../services/biometric_service.dart';
import '../../../services/database_service.dart';
import '../../../services/input_validator.dart';
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
    final primaryText =
        isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText =
        isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: UserTheme.primaryOrange),
          );
        }

        Map<String, dynamic>? userData = snapshot.data;
        final fullName = (userData?['fullName'] as String?)?.trim();
        final email = (userData?['email'] as String?)?.trim() ?? '';
        final initial = (fullName != null && fullName.isNotEmpty)
            ? fullName[0].toUpperCase()
            : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

        return SingleChildScrollView(
          padding: UserUi.listPadding(context, top: 20, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Minimalist Profile Identity Header
              UserUi.surfaceCard(
                context,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: UserTheme.primaryOrange.withValues(alpha: 0.35),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: UserTheme.primaryOrange,
                        ),
                      ),
                    ),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: secondaryText,
                  ),
                ),
              ),
              UserUi.surfaceCard(
                context,
                padding: EdgeInsets.zero,
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: secondaryText,
                  ),
                ),
              ),
              UserUi.surfaceCard(
                context,
                padding: EdgeInsets.zero,
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
                            color: isDark
                                ? UserTheme.nightTextSecondary
                                : UserTheme.dayTextSecondary,
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
                            activeTrackColor: UserTheme.primaryOrange,
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
                UserUi.surfaceCard(
                  context,
                  padding: EdgeInsets.zero,
                  child: Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile.adaptive(
                      secondary: Icon(
                        Icons.science_outlined,
                        size: 20,
                        color: secondaryText,
                      ),
                      title: const Text('Dev mode'),
                      subtitle: const Text(
                        'Enable weather and time-of-day simulation in Dropbox.',
                      ),
                      value: widget.devModeEnabled,
                      activeTrackColor: UserTheme.primaryOrange,
                      onChanged: widget.devModeBusy
                          ? null
                          : widget.onDevModeChanged,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded,
                      color: UserTheme.statusError, size: 18),
                  label: const Text(
                    'Log out',
                    style: TextStyle(
                      color: UserTheme.statusError,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor:
                        UserTheme.statusError.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusM),
                      side: BorderSide(
                          color: UserTheme.statusError.withValues(alpha: 0.2)),
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

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit $title'),
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
          ElevatedButton(
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
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
              onPressed: submitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete Account?'),
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
            ElevatedButton(
              onPressed: deleting || confirmController.text.trim() != 'DELETE'
                  ? null
                  : () async {
                      setDialogState(() => deleting = true);
                      final dialogNav = Navigator.of(dialogContext);
                      try {
                        await widget.databaseService
                            .deleteUser(widget.userId);
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
              style: ElevatedButton.styleFrom(
                backgroundColor: UserTheme.statusError,
                foregroundColor: Colors.white,
              ),
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
      confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
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
