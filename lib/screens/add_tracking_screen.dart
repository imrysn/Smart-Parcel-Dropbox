import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'ocr_scanner_screen.dart';

/// Add Tracking Screen - Register new tracking ID
class AddTrackingScreen extends StatefulWidget {
  const AddTrackingScreen({super.key});

  @override
  State<AddTrackingScreen> createState() => _AddTrackingScreenState();
}

class _AddTrackingScreenState extends State<AddTrackingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _trackingIdController = TextEditingController();
  final _shopNameController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _trackingIdController.dispose();
    _shopNameController.dispose();
    super.dispose();
  }

  Future<void> _addTracking() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = await _authService.currentUserId;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      await _databaseService.registerTrackingId(
        userId: userId,
        trackingId: _trackingIdController.text.trim(),
        shopName: _shopNameController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tracking ID added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: UserTheme.appBarGradient(
        context: context,
        title: 'Add tracking ID',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info card
              Card(
                color: UserTheme.backgroundSurface,
                surfaceTintColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: UserTheme.primaryOrangeDark,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Register your tracking ID to receive notifications when your parcel is delivered.',
                          style: TextStyle(
                            color: UserTheme.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Tracking ID
              TextFormField(
                controller: _trackingIdController,
                decoration: InputDecoration(
                  labelText: 'Tracking ID',
                  hintText: 'Enter tracking number from shop',
                  prefixIcon: const Icon(Icons.qr_code_2),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.center_focus_strong, color: UserTheme.primaryOrange),
                        tooltip: 'AI OCR Scan',
                        onPressed: () async {
                          final result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(builder: (context) => const OcrScannerScreen()),
                          );
                          if (result != null && mounted) {
                            setState(() {
                              _trackingIdController.text = result;
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data != null && data.text != null) {
                            setState(() {
                              _trackingIdController.text = data.text!;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter tracking ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Shop Name
              TextFormField(
                controller: _shopNameController,
                decoration: const InputDecoration(
                  labelText: 'Shop/Platform Name',
                  hintText: 'e.g., Shopee, Lazada',
                  prefixIcon: Icon(Icons.store_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter shop name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Add button
              ElevatedButton(
                onPressed: _isLoading ? null : _addTracking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Add Tracking ID',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
