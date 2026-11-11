import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
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
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();

  final List<String> _shops = ['Lazada', 'Shopee', 'Tiktok'];
  String _selectedShop = 'Lazada';
  static const String _addOption = 'Add';
  int _dropdownRebuildKey = 0;

  bool _isLoading = false;

  @override
  void dispose() {
    _trackingIdController.dispose();
    super.dispose();
  }

  IconData _getShopIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('shopee')) return Icons.shopping_bag_rounded;
    if (lower.contains('lazada')) return Icons.storefront_rounded;
    if (lower.contains('tiktok')) return Icons.music_note_rounded;
    return Icons.local_shipping_rounded;
  }

  Color _getShopColor(String name, bool isDark) {
    final lower = name.toLowerCase();
    if (lower.contains('shopee')) return const Color(0xFFEE4D2D);
    if (lower.contains('lazada')) return isDark ? const Color(0xFF388AF6) : const Color(0xFF0F146D);
    if (lower.contains('tiktok')) return const Color(0xFFFE2C55);
    return UserTheme.primaryOrange;
  }

  Future<void> _showAddShopDialog(BuildContext context) async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final newShop = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: UserTheme.primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_business_rounded,
                color: UserTheme.primaryOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Add Merchant / Shop',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the courier or merchant name:',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: textController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(
                  color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Amazon, DHL, FedEx',
                  hintStyle: TextStyle(
                    color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a shop name';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCEL',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: UserTheme.primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(textController.text.trim());
              }
            },
            child: const Text(
              'ADD',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    setState(() {
      _dropdownRebuildKey++;
      if (newShop != null && newShop.isNotEmpty) {
        final existingIndex = _shops.indexWhere(
          (s) => s.toLowerCase() == newShop.toLowerCase(),
        );
        if (existingIndex != -1) {
          _selectedShop = _shops[existingIndex];
        } else {
          _shops.add(newShop);
          _selectedShop = newShop;
        }
      }
    });
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
        shopName: _selectedShop,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waybill tracking ID registered!'),
            backgroundColor: UserTheme.statusSuccess,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: UserTheme.statusError,
            behavior: SnackBarBehavior.floating,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: 'Add Tracking ID',
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: UserUi.listPadding(context, top: 16, bottom: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info Card
                UserUi.surfaceCard(
                  context,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: UserTheme.primaryOrange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: UserTheme.primaryOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Automatic Barcode Access',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'The dropbox scanner will recognize this waybill and unlock the top door automatically.',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Courier or Merchant Dropdown Selection
                UserUi.sectionTitle(
                  context,
                  'Courier or Merchant',
                  subtitle: 'Select platform or add a new courier',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('shop_dropdown_${_selectedShop}_$_dropdownRebuildKey'),
                  initialValue: _shops.contains(_selectedShop) ? _selectedShop : _shops.first,
                  dropdownColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: UserTheme.primaryOrange),
                  borderRadius: BorderRadius.circular(UserTheme.radiusL),
                  decoration: InputDecoration(
                    labelText: 'Courier or Merchant',
                    prefixIcon: const Icon(Icons.storefront_rounded),
                    filled: true,
                    fillColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
                    ),
                  ),
                  selectedItemBuilder: (context) {
                    final allItems = [..._shops, _addOption];
                    return allItems.map((item) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                          ),
                        ),
                      );
                    }).toList();
                  },
                  items: [
                    ..._shops.map((shop) => DropdownMenuItem<String>(
                      value: shop,
                      child: Row(
                        children: [
                          Icon(
                            _getShopIcon(shop),
                            size: 18,
                            color: _getShopColor(shop, isDark),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            shop,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    )),
                    const DropdownMenuItem<String>(
                      value: _addOption,
                      child: Row(
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            size: 18,
                            color: UserTheme.primaryOrange,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Add',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: UserTheme.primaryOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val == _addOption) {
                      _showAddShopDialog(context);
                    } else if (val != null) {
                      setState(() => _selectedShop = val);
                    }
                  },
                  validator: (val) {
                    if (val == null || val.isEmpty || val == _addOption) {
                      return 'Please select a courier or merchant';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Tracking ID field
                UserUi.sectionTitle(
                  context,
                  'Tracking Number',
                  subtitle: 'Waybill code printed on the shipping label',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _trackingIdController,
                  decoration: InputDecoration(
                    labelText: 'Tracking Number',
                    hintText: 'e.g. SPXMY0123456789',
                    prefixIcon: const Icon(Icons.qr_code_2_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: 'Paste from clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data != null && data.text != null) {
                          setState(() {
                            _trackingIdController.text = data.text!.trim();
                          });
                        }
                      },
                    ),
                    filled: true,
                    fillColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      borderSide: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter tracking number';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Submit Button
                UserUi.premiumButton(
                  label: _isLoading ? 'REGISTERING...' : 'REGISTER TRACKING ID',
                  icon: Icons.check_circle_outline_rounded,
                  isLoading: _isLoading,
                  onTap: _isLoading ? () {} : _addTracking,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
