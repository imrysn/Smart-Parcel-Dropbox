import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

/// Add Pickup Screen - Register item for rider collection
class AddPickupScreen extends StatefulWidget {
  const AddPickupScreen({super.key});

  @override
  State<AddPickupScreen> createState() => _AddPickupScreenState();
}

class _AddPickupScreenState extends State<AddPickupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _trackingIdController = TextEditingController();
  final _descriptionController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();

  bool _isLoading = false;

  String _selectedCourier = 'Spx';

  @override
  void dispose() {
    _trackingIdController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _registerPickup() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = await _authService.currentUserId;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Create a combined label: Courier - Description
      final String fullDescription = '$_selectedCourier - ${_descriptionController.text.trim()}';

      // 1. Register the pickup in the database
      await _databaseService.registerTrackingId(
        userId: userId,
        trackingId: _trackingIdController.text.trim(),
        shopName: fullDescription,
        mode: 'pickup',
      );

      // Update status to ready_for_pickup
      await _databaseService.updateTrackingStatus(
        trackingId: _trackingIdController.text.trim(),
        status: 'ready_for_pickup',
      );

      // 2. Ask user if they want to deposit now
      if (mounted) {
        final bool? depositNow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Registration Successful'),
            content: const Text('Your pickup is registered. Would you like to open the drop box now to deposit the item?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open Box Now'),
              ),
            ],
          ),
        );

        if (depositNow == true) {
          // Open the box
          await _databaseService.controlDropBoxDoor(
            userId: userId,
            open: true,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Drop box opened. Please deposit your item.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }

        if (mounted) {
          Navigator.of(context).pop(); // Back to Home
        }
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Register Pickup Item'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Provide the Tracking ID that the rider will use to verify and collect your item.',
                          style: TextStyle(color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _trackingIdController,
                decoration: InputDecoration(
                  labelText: 'Tracking ID',
                  hintText: 'Enter the ID for rider verification',
                  prefixIcon: const Icon(Icons.tag),
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
              DropdownButtonFormField<String>(
                value: _selectedCourier,
                decoration: const InputDecoration(
                  labelText: 'Courier / Delivery Type',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                items: ['Spx', 'J&T', 'lalamove'].map((String courier) {
                  return DropdownMenuItem<String>(
                    value: courier,
                    child: Text(courier),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedCourier = newValue;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Item Description',
                  hintText: 'e.g., Return Parcel, Document',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter item description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _registerPickup,
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Register Pickup',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
