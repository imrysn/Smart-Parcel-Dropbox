import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

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
  final _expectedDateController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();

  bool _isLoading = false;

  @override
  void dispose() {
    _trackingIdController.dispose();
    _shopNameController.dispose();
    _expectedDateController.dispose();
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
        expectedDeliveryDate: _expectedDateController.text.isNotEmpty
            ? _expectedDateController.text
            : null,
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

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (picked != null) {
      setState(() {
        _expectedDateController.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Add Tracking ID'),
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
                color: const Color(0xFFFFF3E0), // Orange 50 - warm tint
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFF4511E), // Deep Orange 600
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Register your tracking ID to receive notifications when your parcel is delivered.',
                          style: TextStyle(
                            color: Colors.grey[800],
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
                  suffixIcon: IconButton(
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
              const SizedBox(height: 16),

              // Expected Delivery Date
              TextFormField(
                controller: _expectedDateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Expected Delivery Date (Optional)',
                  hintText: 'Select date',
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _expectedDateController.clear();
                      });
                    },
                  ),
                ),
                onTap: _selectDate,
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
    );
  }
}
