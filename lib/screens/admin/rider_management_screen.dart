import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/api_config.dart';
import '../../config/user_theme.dart';
import '../../widgets/user_ui.dart';

class RiderManagementScreen extends StatefulWidget {
  final bool isEmbedded;
  const RiderManagementScreen({Key? key, this.isEmbedded = false}) : super(key: key);

  @override
  State<RiderManagementScreen> createState() => _RiderManagementScreenState();
}

class _RiderManagementScreenState extends State<RiderManagementScreen> {
  List<dynamic> _riders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/riders'));
      if (response.statusCode == 200) {
        setState(() {
          _riders = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching riders: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addRider(String riderId, String name) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/riders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'riderId': riderId, 'name': name}),
      );
      if (response.statusCode == 201) {
        _fetchRiders(); // Refresh
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${jsonDecode(response.body)['message']}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error adding rider: $e');
    }
  }

  Future<void> _deleteRider(String id) async {
    try {
      final response = await http.delete(Uri.parse('${ApiConfig.baseUrl}/riders/$id'));
      if (response.statusCode == 200) {
        _fetchRiders(); // Refresh
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rider access revoked successfully.'), behavior: SnackBarBehavior.floating),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting rider: $e');
    }
  }

  Future<void> _showDeleteConfirmation(dynamic rider) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: const Text('Revoke Access?', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        content: Text(
          'Are you sure you want to remove access for ${rider['name']}? They will no longer be able to open the dropbox.',
          style: TextStyle(color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRider(rider['_id']);
            },
            child: const Text('REVOKE', style: TextStyle(color: UserTheme.statusError, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddRiderDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: const Text('Register Rider Access', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the QR/Barcode from the courier manifest or tracking ID. The rider will scan this to open the box.',
              style: TextStyle(fontSize: 12, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              style: TextStyle(color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
              decoration: UserUi.inputDecoration(
                label: 'Courier / Rider Name',
                hint: 'e.g. J&T Express / John Doe',
                icon: Icons.person_rounded,
                context: context,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              style: TextStyle(color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
              decoration: UserUi.inputDecoration(
                label: 'Manifest Barcode / ID',
                hint: 'e.g. PH-JNT-123456',
                icon: Icons.qr_code_rounded,
                context: context,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
          ),
          UserUi.premiumButton(
            label: 'REGISTER',
            onTap: () {
              if (nameController.text.isNotEmpty && idController.text.isNotEmpty) {
                _addRider(idController.text, nameController.text);
                Navigator.pop(context);
              }
            },
            icon: Icons.check_circle_rounded,
          ),
        ],
      ),
    );
  }

  void _showQRCodeDialog(String riderId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(UserTheme.radiusM),
              ),
              child: QrImageView(
                data: riderId,
                version: QrVersions.auto,
                size: 200.0,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              riderId,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1,
                fontFamily: 'monospace',
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PASSKEY ID',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CLOSE', style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isEmbedded 
          ? null 
          : UserTheme.appBarGradient(context: context, title: 'Manage Riders', centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRiderDialog,
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: const Text('REGISTER RIDER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
        backgroundColor: UserTheme.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 8,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange))
          : _riders.isEmpty
              ? UserUi.emptyState(context, icon: Icons.motorcycle_rounded, title: 'No Riders', subtitle: 'Tap the button below to register a new delivery rider account.')
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 120),
                  itemCount: _riders.length,
                  itemBuilder: (context, index) {
                    final rider = _riders[index];
                    return Dismissible(
                      key: ValueKey(rider['_id']),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        await _showDeleteConfirmation(rider);
                        return false; // Never auto-remove; _showDeleteConfirmation handles it
                      },
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: UserTheme.statusError.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(UserTheme.radiusL),
                          border: Border.all(color: UserTheme.statusError.withOpacity(0.4)),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded, color: UserTheme.statusError, size: 20),
                            SizedBox(width: 6),
                            Text('REVOKE', style: TextStyle(color: UserTheme.statusError, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                          ],
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: UserUi.surfaceCard(
                          context,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: UserTheme.primaryOrange.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.motorcycle_rounded, color: UserTheme.primaryOrange, size: 20),
                            ),
                            title: Text(
                              rider['name'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                            subtitle: Text(
                              'ID: ${rider['riderId']}',
                              style: TextStyle(
                                color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.qr_code_2_rounded, color: UserTheme.primaryOrange),
                                  tooltip: 'Show Passkey',
                                  onPressed: () => _showQRCodeDialog(rider['riderId'], rider['name']),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: UserTheme.statusError),
                                  tooltip: 'Revoke Access',
                                  onPressed: () => _showDeleteConfirmation(rider),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
