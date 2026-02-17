import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/forms/custom_text_field.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/utils/extensions.dart';
import '../providers/tracking_provider.dart';

/// Refactored Add Tracking Screen using new components
/// 
/// Demonstrates:
/// - Riverpod for state management
/// - Reusable form components
/// - Validation utilities
/// - Context extensions for snackbars
class AddTrackingScreenRefactored extends ConsumerStatefulWidget {
  const AddTrackingScreenRefactored({super.key});

  @override
  ConsumerState<AddTrackingScreenRefactored> createState() =>
      _AddTrackingScreenRefactoredState();
}

class _AddTrackingScreenRefactoredState
    extends ConsumerState<AddTrackingScreenRefactored> {
  final _formKey = GlobalKey<FormState>();
  final _trackingIdController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _expectedDateController = TextEditingController();

  @override
  void dispose() {
    _trackingIdController.dispose();
    _shopNameController.dispose();
    _expectedDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      context.showErrorSnackBar('User not logged in');
      return;
    }

    await ref.read(trackingRegistrationProvider.notifier).registerTracking(
          userId: userId,
          trackingId: _trackingIdController.text.trim(),
          shopName: _shopNameController.text.trim(),
          expectedDeliveryDate: _expectedDateController.text.isNotEmpty
              ? _expectedDateController.text
              : null,
        );

    // Listen to registration state
    ref.listen<AsyncValue<void>>(
      trackingRegistrationProvider,
      (previous, next) {
        next.when(
          data: (_) {
            context.showSuccessSnackBar('Tracking ID added successfully!');
            Navigator.of(context).pop();
          },
          loading: () {},
          error: (error, stack) {
            context.showErrorSnackBar(error.toString());
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final registrationState = ref.watch(trackingRegistrationProvider);
    final isLoading = registrationState.isLoading;

    return Scaffold(
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
                color: const Color(0xFFFFF3E0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFF4511E),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Register your tracking ID to receive notifications when your parcel is delivered.',
                          style: TextStyle(color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Tracking ID field
              CustomTextField(
                controller: _trackingIdController,
                labelText: 'Tracking ID',
                hintText: 'Enter tracking number from shop',
                prefixIcon: Icons.qr_code_2,
                validator: InputValidators.validateTrackingId,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // Shop Name field
              CustomTextField(
                controller: _shopNameController,
                labelText: 'Shop/Platform Name',
                hintText: 'e.g., Shopee, Lazada',
                prefixIcon: Icons.store_outlined,
                validator: (value) =>
                    InputValidators.validateRequired(value, 'Shop name'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),

              // Expected Delivery Date field
              CustomTextField(
                controller: _expectedDateController,
                labelText: 'Expected Delivery Date (Optional)',
                hintText: 'Select date',
                prefixIcon: Icons.calendar_today_outlined,
                readOnly: true,
                onTap: _selectDate,
                suffixIcon: _expectedDateController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _expectedDateController.clear();
                          });
                        },
                      )
                    : null,
              ),
              const SizedBox(height: 32),

              // Submit button
              PrimaryButton(
                label: 'Add Tracking ID',
                onPressed: isLoading ? null : _handleSubmit,
                isLoading: isLoading,
                icon: Icons.add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
