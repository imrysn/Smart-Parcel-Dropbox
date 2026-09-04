import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/tracking_service.dart';
import '../services/service_locator.dart';

/// Add Pickup & Outbound Staging Screen for Small Business Fulfillment
class AddPickupScreen extends StatefulWidget {
  const AddPickupScreen({super.key});

  @override
  State<AddPickupScreen> createState() => _AddPickupScreenState();
}

class _AddPickupScreenState extends State<AddPickupScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKeyOutbound = GlobalKey<FormState>();
  final _formKeyPersonal = GlobalKey<FormState>();

  // Single Outbound Customer Staging Controllers
  final _outboundTrackingController = TextEditingController();
  final _shopNameController = TextEditingController(text: 'My Business Store');
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _riderPhoneController = TextEditingController();
  final _riderNameController = TextEditingController();
  String _selectedCourierOutbound = 'J&T Express';

  // Batch Outbound Staging Controllers
  final _batchTrackingTextController = TextEditingController();
  final _batchShopNameController = TextEditingController(text: 'My Business Store');
  String _selectedCourierBatch = 'J&T Express';
  bool _openDoorForBatch = true;

  // Personal Pickup Controllers
  final _personalTrackingIdController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCourierPersonal = 'Spx';

  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final TrackingService _trackingService = getIt<TrackingService>();

  bool _isLoading = false;

  bool get _isMobile {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _outboundTrackingController.dispose();
    _shopNameController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _riderPhoneController.dispose();
    _riderNameController.dispose();
    _batchTrackingTextController.dispose();
    _batchShopNameController.dispose();
    _personalTrackingIdController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Smart Waybill Barcode & QR Parser Engine
  void _smartParseAndAutofill(String rawCode) {
    String cleanCode = rawCode.trim();
    String? detectedCourier;
    String? detectedCustomer;
    String? detectedPhone;

    // 1. Check if JSON payload (from generated vendor QR)
    if (cleanCode.startsWith('{') && cleanCode.endsWith('}')) {
      try {
        final Map<String, dynamic> data = jsonDecode(cleanCode);
        cleanCode = data['trackingId']?.toString() ?? data['id']?.toString() ?? cleanCode;
        detectedCustomer = data['customerName']?.toString() ?? data['name']?.toString();
        detectedPhone = data['customerPhone']?.toString() ?? data['phone']?.toString();
        detectedCourier = data['courier']?.toString() ?? data['courierName']?.toString();
      } catch (_) {}
    } 
    // 2. Check if pipe or comma separated payload (TRACKING|CUSTOMER|PHONE|COURIER)
    else if (cleanCode.contains('|')) {
      final parts = cleanCode.split('|');
      if (parts.isNotEmpty) cleanCode = parts[0].trim();
      if (parts.length > 1) detectedCustomer = parts[1].trim();
      if (parts.length > 2) detectedPhone = parts[2].trim();
      if (parts.length > 3) detectedCourier = parts[3].trim();
    }

    // 3. Smart Courier Partner Auto-Detection by Waybill Prefix
    final upper = cleanCode.toUpperCase();
    if (detectedCourier == null || detectedCourier.isEmpty) {
      if (upper.startsWith('JNT') || upper.startsWith('60') || upper.startsWith('JT')) {
        detectedCourier = 'J&T Express';
      } else if (upper.startsWith('SPX') || upper.startsWith('MY')) {
        detectedCourier = 'Spx';
      } else if (upper.startsWith('NLMY') || upper.startsWith('NV') || upper.startsWith('NINJA')) {
        detectedCourier = 'NinjaVan';
      } else if (upper.startsWith('PL') || upper.startsWith('EN') || upper.startsWith('ER') || upper.startsWith('EM') || upper.startsWith('POS')) {
        detectedCourier = 'PosLaju';
      } else if (upper.startsWith('DHL') || upper.startsWith('JD') || upper.startsWith('77')) {
        detectedCourier = 'DHL Express';
      } else if (upper.startsWith('LLM') || upper.startsWith('LALA')) {
        detectedCourier = 'Lalamove';
      }
    }

    setState(() {
      _outboundTrackingController.text = cleanCode;
      if (detectedCustomer != null && detectedCustomer.isNotEmpty) {
        _customerNameController.text = detectedCustomer;
      }
      if (detectedPhone != null && detectedPhone.isNotEmpty) {
        _customerPhoneController.text = detectedPhone;
      }
      if (detectedCourier != null && detectedCourier.isNotEmpty) {
        final validCouriers = ['J&T Express', 'NinjaVan', 'PosLaju', 'DHL Express', 'Spx', 'Lalamove'];
        if (validCouriers.contains(detectedCourier)) {
          _selectedCourierOutbound = detectedCourier;
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ Smart Autofill Applied: Courier set to ${detectedCourier ?? "Auto-detected"}!'),
          backgroundColor: UserTheme.primaryOrange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Opens camera scanner sheet to scan waybill barcode/QR
  Future<void> _scanBarcode({required Function(String code) onScanned, bool continuous = false}) async {
    if (!_isMobile) {
      // Desktop / Fallback Dialog
      final textController = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Simulate Barcode Scan'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Enter/Scan Waybill Barcode',
              hintText: 'e.g. JNT998822001',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(textController.text.trim()),
              child: const Text('ADD BARCODE'),
            ),
          ],
        ),
      );
      if (code != null && code.isNotEmpty) {
        onScanned(code);
      }
      return;
    }

    // Mobile Camera Scanner Sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) {
        bool scannedThisSession = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Stack(
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      if (scannedThisSession && !continuous) return;
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final val = barcode.rawValue;
                        if (val != null && val.isNotEmpty) {
                          scannedThisSession = true;
                          HapticFeedback.mediumImpact();
                          onScanned(val);
                          if (!continuous) {
                            Navigator.of(context).pop();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Scanned: $val'),
                                duration: const Duration(milliseconds: 800),
                                backgroundColor: UserTheme.statusSuccess,
                              ),
                            );
                          }
                          break;
                        }
                      }
                    },
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        continuous
                            ? 'Point camera at package waybill barcodes.\nScanning continuously...'
                            : 'Align package waybill barcode inside frame to scan.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _stageOutboundCustomerOrder() async {
    if (!_formKeyOutbound.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final trackingId = _outboundTrackingController.text.trim();
      final customerName = _customerNameController.text.trim();
      final customerPhone = _customerPhoneController.text.trim();
      final courierName = _selectedCourierOutbound;
      final riderPhone = _riderPhoneController.text.trim();
      final riderName = _riderNameController.text.trim();

      final res = await _trackingService.stageOutboundPackage(
        trackingId: trackingId,
        shopName: _shopNameController.text.trim(),
        customerName: customerName,
        customerPhone: customerPhone,
        courierName: courierName,
        riderName: riderName.isNotEmpty ? riderName : null,
        riderPhone: riderPhone.isNotEmpty ? riderPhone : null,
      );

      final courierOtp = res['courierOtp']?.toString() ?? '';

      final pickupPassText = 
          "📦 SMART PARCEL DROPBOX - COURIER PICKUP PASS\n\n"
          "Tracking ID / Waybill: $trackingId\n"
          "Courier: $courierName\n"
          "Customer: $customerName\n"
          "${courierOtp.isNotEmpty ? 'Ref OTP: $courierOtp\n' : ''}"
          "\nPickup Instructions:\n"
          "1. Arrive at the Smart Parcel Drop Box.\n"
          "2. Press the physical 'PICKUP' button.\n"
          "3. Scan this Tracking ID / Waybill or present the QR code to the scanner.\n"
          "4. The pickup door will unlock automatically!";

      Future<void> launchSms(String phone, String body) async {
        final encoded = Uri.encodeComponent(body);
        if (!kIsWeb && Platform.isWindows) {
          try {
            await Process.run('cmd', ['/c', 'start', 'sms:$phone?body=$encoded']);
          } catch (_) {}
        }
        await Clipboard.setData(ClipboardData(text: body));
      }

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: UserTheme.statusSuccess, size: 24),
                SizedBox(width: 8),
                Text('Order Staged!'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Package staged in Dropbox for $courierName pickup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // High-contrast Scannable QR Code for physical scanner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        QrImageView(
                          data: trackingId,
                          version: QrVersions.auto,
                          size: 150,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          trackingId,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Hold this QR code or parcel waybill barcode to the Drop Box scanner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                    ),
                  ),

                  if (courierOtp.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Ref OTP: $courierOtp',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: UserTheme.primaryOrange,
                        ),
                      ),
                    ),
                  ],

                  if (riderPhone.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Rider: $riderPhone',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (riderPhone.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.sms_rounded, size: 16),
                  label: const Text('SEND SMS TO RIDER'),
                  onPressed: () async {
                    await launchSms(riderPhone, pickupPassText);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('SMS opened for $riderPhone! (Copied to clipboard)'),
                          backgroundColor: UserTheme.statusSuccess,
                        ),
                      );
                    }
                  },
                ),
              TextButton.icon(
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('SHARE PASS'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pickupPassText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Courier Pickup Pass copied to clipboard! Share via WhatsApp / Messenger.'),
                        backgroundColor: UserTheme.statusSuccess,
                      ),
                    );
                  }
                },
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('DONE'),
              ),
            ],
          ),
        );

        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: UserTheme.statusError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _stageBatchOutboundCustomerOrders() async {
    final rawText = _batchTrackingTextController.text.trim();
    if (rawText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan, paste, or enter at least one tracking ID'), backgroundColor: UserTheme.statusWarning),
      );
      return;
    }

    final trackingIds = rawText
        .split(RegExp(r'[\n,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (trackingIds.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final List<Map<String, String>> packages = trackingIds.map((id) {
        return {
          'trackingId': id,
          'customerName': 'Valued Customer',
          'courierName': _selectedCourierBatch,
        };
      }).toList();

      final created = await _trackingService.batchStageOutboundPackages(
        packages: packages,
        shopName: _batchShopNameController.text.trim(),
        openDoor: _openDoorForBatch,
      );

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.inventory_2_outlined, color: UserTheme.statusSuccess),
                SizedBox(width: 8),
                Text('Batch Deposit Staged!'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Successfully registered ${created.length} packages for pickup via $_selectedCourierBatch.'),
                const SizedBox(height: 12),
                if (_openDoorForBatch)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: UserTheme.statusSuccess.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: UserTheme.statusSuccess.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.lock_open, color: UserTheme.statusSuccess),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dropbox door signal sent! Open box and deposit all parcels now.',
                            style: TextStyle(color: UserTheme.statusSuccess, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('DONE'),
              ),
            ],
          ),
        );

        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: UserTheme.statusError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerPersonalPickup() async {
    if (!_formKeyPersonal.currentState!.validate()) return;

    final userId = await _authService.currentUserId;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final String fullDescription = '$_selectedCourierPersonal - ${_descriptionController.text.trim()}';

      await _databaseService.registerTrackingId(
        userId: userId,
        trackingId: _personalTrackingIdController.text.trim(),
        shopName: fullDescription,
        mode: 'pickup',
      );

      await _databaseService.updateTrackingStatus(
        trackingId: _personalTrackingIdController.text.trim(),
        status: 'ready_for_pickup',
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: UserTheme.statusError),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Fulfillment & Outbound Hub',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: UserTheme.primaryOrange,
            labelColor: UserTheme.primaryOrange,
            unselectedLabelColor: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
            tabs: const [
              Tab(icon: Icon(Icons.post_add_rounded), text: 'Single Order'),
              Tab(icon: Icon(Icons.inventory_rounded), text: 'Batch Deposit'),
              Tab(icon: Icon(Icons.person_outline), text: 'Personal'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Single Outbound Customer Order Staging
            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKeyOutbound,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UserUi.surfaceCard(
                      context,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: UserTheme.primaryOrange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Stage an individual customer package. Generates a digital Courier Pickup QR Pass & automated SMS dispatch.',
                              style: TextStyle(
                                color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _outboundTrackingController,
                      decoration: InputDecoration(
                        labelText: 'Order / Waybill Tracking ID',
                        prefixIcon: const Icon(Icons.local_shipping_outlined, color: UserTheme.primaryOrange),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange),
                              tooltip: 'Scan Waybill QR with Phone Camera',
                              onPressed: () => _scanBarcode(
                                onScanned: (code) => _smartParseAndAutofill(code),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.content_paste),
                              tooltip: 'Paste Clipboard',
                              onPressed: () async {
                                final data = await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _smartParseAndAutofill(data!.text!);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter tracking ID' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                        hintText: 'e.g. Sarah Smith',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter customer name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customerPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Customer Phone / WhatsApp (Optional)',
                        hintText: 'e.g. 60123456789',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCourierOutbound,
                      decoration: const InputDecoration(
                        labelText: 'Courier Partner',
                        prefixIcon: Icon(Icons.alt_route_rounded),
                      ),
                      items: ['J&T Express', 'NinjaVan', 'PosLaju', 'DHL Express', 'Spx', 'Flash Express', 'Lalamove'].map((c) {
                        return DropdownMenuItem(value: c, child: Text(c));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCourierOutbound = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ['J&T Express', 'Spx', 'Flash Express', 'NinjaVan', 'Lalamove'].map((courier) {
                        final isSelected = _selectedCourierOutbound == courier;
                        return ChoiceChip(
                          label: Text(courier, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedColor: UserTheme.primaryOrange,
                          labelStyle: TextStyle(color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedCourierOutbound = courier);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _riderPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Courier / Rider Phone (For SMS Dispatch)',
                        hintText: 'e.g. 09123456789 (Optional)',
                        prefixIcon: Icon(Icons.sms_outlined, color: UserTheme.primaryOrange),
                      ),
                    ),
                    const SizedBox(height: 28),
                    UserUi.premiumButton(
                      label: 'STAGE ORDER & GET PICKUP PASS',
                      onTap: _isLoading ? () {} : _stageOutboundCustomerOrder,
                      icon: Icons.qr_code_rounded,
                    ),
                  ],
                ),
              ),
            ),

            // Tab 2: Batch Outbound Staging & 1-Tap Unlock
            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UserUi.surfaceCard(
                    context,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.flash_on, color: UserTheme.primaryOrange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Scan multiple waybill barcodes with camera or paste list. Unlock dropbox in 1 tap!',
                            style: TextStyle(
                              color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  UserUi.premiumButton(
                    label: 'SCAN WAYBILLS WITH CAMERA',
                    onTap: () => _scanBarcode(
                      continuous: true,
                      onScanned: (code) {
                        final upper = code.toUpperCase();
                        String? autoCourier;
                        if (upper.startsWith('JNT') || upper.startsWith('60')) autoCourier = 'J&T Express';
                        else if (upper.startsWith('SPX') || upper.startsWith('MY')) autoCourier = 'Spx';
                        else if (upper.startsWith('NLMY') || upper.startsWith('NV')) autoCourier = 'NinjaVan';
                        else if (upper.startsWith('PL') || upper.startsWith('EN')) autoCourier = 'PosLaju';

                        setState(() {
                          final current = _batchTrackingTextController.text;
                          if (!current.contains(code)) {
                            _batchTrackingTextController.text = current.isEmpty ? code : '$current\n$code';
                          }
                          if (autoCourier != null) {
                            _selectedCourierBatch = autoCourier;
                          }
                        });
                      },
                    ),
                    icon: Icons.qr_code_scanner_rounded,
                  ),
                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _batchTrackingTextController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Scanned / Pasted Tracking IDs',
                      hintText: 'JNT9901001\nJNT9901002\nJNT9901003',
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 80.0),
                        child: Icon(Icons.list_alt_rounded),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            setState(() => _batchTrackingTextController.text = data!.text!);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCourierBatch,
                    decoration: const InputDecoration(
                      labelText: 'Courier Partner for Batch',
                      prefixIcon: Icon(Icons.alt_route_rounded),
                    ),
                    items: ['J&T Express', 'NinjaVan', 'PosLaju', 'DHL Express', 'Spx', 'Lalamove'].map((c) {
                      return DropdownMenuItem(value: c, child: Text(c));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCourierBatch = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(
                      'Unlock Dropbox Door Immediately',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Automatically opens box so you can deposit all items right now',
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        fontSize: 12,
                      ),
                    ),
                    value: _openDoorForBatch,
                    activeThumbColor: UserTheme.primaryOrange,
                    onChanged: (val) => setState(() => _openDoorForBatch = val),
                  ),
                  const SizedBox(height: 24),
                  UserUi.premiumButton(
                    label: 'REGISTER BATCH & DEPOSIT ALL NOW',
                    onTap: _isLoading ? () {} : _stageBatchOutboundCustomerOrders,
                    icon: Icons.lock_open_rounded,
                  ),
                ],
              ),
            ),

            // Tab 3: Personal Pickup
            SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKeyPersonal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    UserUi.surfaceCard(
                      context,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: UserTheme.primaryOrange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Register personal items or returns to be collected from your dropbox.',
                              style: TextStyle(
                                color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _personalTrackingIdController,
                      decoration: InputDecoration(
                        labelText: 'Tracking ID',
                        prefixIcon: const Icon(Icons.tag, color: UserTheme.primaryOrange),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange),
                          onPressed: () => _scanBarcode(
                            onScanned: (code) => setState(() => _personalTrackingIdController.text = code),
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter tracking ID' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCourierPersonal,
                      decoration: const InputDecoration(
                        labelText: 'Courier / Service',
                        prefixIcon: Icon(Icons.local_shipping_outlined),
                      ),
                      items: ['Spx', 'J&T', 'lalamove'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setState(() => _selectedCourierPersonal = val!),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter description' : null,
                    ),
                    const SizedBox(height: 28),
                    UserUi.premiumButton(
                      label: 'REGISTER PERSONAL PICKUP',
                      onTap: _isLoading ? () {} : _registerPersonalPickup,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
