import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../widgets/smart_scanner_view.dart';
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
          content: Text('Smart Autofill Applied: Courier set to ${detectedCourier ?? "Auto-detected"}.'),
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

    // Mobile Camera Scanner Sheet powered by unified SmartScannerView
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              height: MediaQuery.sizeOf(sheetCtx).height * 0.76,
              decoration: BoxDecoration(
                color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(UserTheme.radiusXL),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: UserTheme.primaryOrange,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            continuous
                                ? 'Continuous Waybill Scanner'
                                : 'Scan Waybill Barcode',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? UserTheme.nightTextPrimary
                                  : UserTheme.dayTextPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(UserTheme.radiusL),
                        child: SmartScannerView(
                          isSquare: false,
                          continuous: continuous,
                          verticalCenterFraction: 0.44,
                          instructionText: continuous
                              ? 'Point camera at each package waybill.\nContinuous scan cooldown is active.'
                              : 'Align package waybill barcode inside the frame.',
                          onCodeScanned: (val) {
                            onScanned(val);
                            if (!continuous) {
                              if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                            } else if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).clearSnackBars();
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Scanned: $val'),
                                  duration: const Duration(milliseconds: 900),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: UserTheme.statusSuccess,
                                ),
                              );
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

      await _trackingService.stageOutboundPackage(
        trackingId: trackingId,
        shopName: _shopNameController.text.trim(),
        customerName: customerName,
        customerPhone: customerPhone,
        courierName: courierName,
        riderName: riderName.isNotEmpty ? riderName : null,
        riderPhone: riderPhone.isNotEmpty ? riderPhone : null,
      );

      final pickupPassText =
          "SMART PARCEL DROPBOX - COURIER PICKUP PASS\n\n"
          "Tracking ID: $trackingId\n"
          "Courier: $courierName\n"
          "Customer: $customerName\n\n"
          "At the dropbox, select Pickup and scan the waybill barcode.";

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        await showDialog(
          context: context,
          builder: (dialogContext) {
            String? feedbackMsg;
            bool isPassCopied = false;

            return StatefulBuilder(
              builder: (context, setModalState) {
                void triggerFeedback(String msg, {bool passCopied = false}) {
                  setModalState(() {
                    feedbackMsg = msg;
                    if (passCopied) isPassCopied = true;
                  });
                  Future.delayed(const Duration(milliseconds: 2500), () {
                    if (dialogContext.mounted) {
                      setModalState(() {
                        if (feedbackMsg == msg) feedbackMsg = null;
                        isPassCopied = false;
                      });
                    }
                  });
                }

                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  backgroundColor: isDark ? UserTheme.nightCard : Colors.white,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Header Row with Status & Close button
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$courierName Pickup QR',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Send this QR to rider to access the dropbox',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isDark ? UserTheme.nightSurface : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // HERO CENTERPIECE: Elevated High-Contrast QR Code Pass
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Main BIG QR Code
                                  QrImageView(
                                    data: trackingId,
                                    version: QrVersions.auto,
                                    size: 220,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.all(6),
                                  ),
                                  const SizedBox(height: 8),

                                  // Clean, non-bold Tracking ID
                                  SelectableText(
                                    trackingId,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.normal,
                                      fontSize: 16,
                                      color: Color(0xFF334155),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          if (riderPhone.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Rider: $riderPhone', textAlign: TextAlign.center),
                          ],

                          // In-Modal Immediate Feedback Toast (In front of dialog)
                          if (feedbackMsg != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: UserTheme.statusSuccess,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 15),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      feedbackMsg!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),

                          // Action Controls: Balanced & Modern
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isPassCopied ? Colors.green.shade700 : UserTheme.primaryOrange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: Icon(
                                    isPassCopied ? Icons.check_rounded : Icons.share_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    isPassCopied ? 'Pass Copied!' : 'Copy Pickup Pass',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: pickupPassText));
                                    triggerFeedback('Pickup Pass copied to clipboard!', passCopied: true);
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // Subtle Done button
                          Center(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              child: Text(
                                'DONE',
                                style: TextStyle(
                                  color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
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

      final result = await _trackingService.batchStageOutboundPackages(
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
                Text('Successfully registered ${result.packages.length} packages for pickup via $_selectedCourierBatch.'),
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
                      children: [
                        Icon(result.doorConfirmed ? Icons.lock_open : Icons.warning_amber_rounded,
                          color: result.doorConfirmed ? UserTheme.statusSuccess : UserTheme.statusWarning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.doorConfirmed
                                ? 'Pickup lock confirmed unlocked. You can deposit the parcels.'
                                : 'Parcels registered. The dropbox did not confirm an unlock.',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

  InputDecoration _buildInputDecoration({
    required String label,
    String? hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
    bool isDark = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(prefixIcon, color: UserTheme.primaryOrange, size: 20),
      suffixIcon: suffixIcon,
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
    );
  }

  Widget _buildCourierChips({
    required List<String> couriers,
    required String selectedCourier,
    required ValueChanged<String> onSelected,
    required bool isDark,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: couriers.map((courier) {
        final isSelected = selectedCourier == courier;
        return InkWell(
          onTap: () => onSelected(courier),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? UserTheme.primaryOrange
                  : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? UserTheme.primaryOrange
                    : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
              ),
            ),
            child: Text(
              courier,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
              ),
            ),
          ),
        );
      }).toList(),
    );
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
          title: 'Schedule Pickup',
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: UserTheme.primaryOrange,
            indicatorWeight: 2.5,
            labelColor: UserTheme.primaryOrange,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelColor: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
            tabs: const [
              Tab(text: 'Single Order'),
              Tab(text: 'Batch'),
              Tab(text: 'Personal'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Single Outbound Customer Order Staging
            SingleChildScrollView(
              padding: UserUi.listPadding(context, top: 20, bottom: 40),
              child: Form(
                key: _formKeyOutbound,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Register an outgoing package to generate a pickup QR pass for your courier.',
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _outboundTrackingController,
                      decoration: _buildInputDecoration(
                        label: 'Order / Waybill Tracking ID',
                        prefixIcon: Icons.local_shipping_outlined,
                        isDark: isDark,
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
                              icon: const Icon(Icons.content_paste_rounded),
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
                      decoration: _buildInputDecoration(
                        label: 'Customer Name',
                        hint: 'e.g. Sarah Smith',
                        prefixIcon: Icons.person_outline_rounded,
                        isDark: isDark,
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter customer name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customerPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _buildInputDecoration(
                        label: 'Customer Phone / WhatsApp (Optional)',
                        hint: 'e.g. 60123456789',
                        prefixIcon: Icons.phone_outlined,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    UserUi.sectionTitle(context, 'Courier Partner', subtitle: 'Select rider logistics service'),
                    const SizedBox(height: 10),
                    _buildCourierChips(
                      couriers: ['J&T Express', 'Spx', 'Flash Express', 'NinjaVan', 'PosLaju', 'DHL Express', 'Lalamove'],
                      selectedCourier: _selectedCourierOutbound,
                      onSelected: (val) => setState(() => _selectedCourierOutbound = val),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _riderPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _buildInputDecoration(
                        label: 'Courier / Rider Phone (optional)',
                        hint: 'e.g. 09123456789 (Optional)',
                        prefixIcon: Icons.sms_outlined,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 28),
                    UserUi.premiumButton(
                      label: _isLoading ? 'Creating Pass...' : 'Create Pickup Pass',
                      onTap: _isLoading ? () {} : _stageOutboundCustomerOrder,
                      icon: Icons.qr_code_rounded,
                      fontSize: 14.5,
                      isLoading: _isLoading,
                    ),
                  ],
                ),
              ),
            ),

            // Tab 2: Batch Outbound Staging & 1-Tap Unlock
            SingleChildScrollView(
              padding: UserUi.listPadding(context, top: 20, bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Scan multiple waybills or paste a list to stage several pickups at once.',
                    style: TextStyle(
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  UserUi.premiumButton(
                    label: 'Scan Waybills',
                    fontSize: 14.5,
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
                    decoration: _buildInputDecoration(
                      label: 'Scanned / Pasted Tracking IDs',
                      hint: 'JNT9901001\nJNT9901002\nJNT9901003',
                      prefixIcon: Icons.list_alt_rounded,
                      isDark: isDark,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste_rounded),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            setState(() => _batchTrackingTextController.text = data!.text!);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  UserUi.sectionTitle(context, 'Courier Partner for Batch', subtitle: 'Applied to all batch packages'),
                  const SizedBox(height: 10),
                  _buildCourierChips(
                    couriers: ['J&T Express', 'NinjaVan', 'PosLaju', 'DHL Express', 'Spx', 'Lalamove'],
                    selectedCourier: _selectedCourierBatch,
                    onSelected: (val) => setState(() => _selectedCourierBatch = val),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),
                  UserUi.surfaceCard(
                    context,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Unlock Dropbox Door Immediately',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                  ),
                  const SizedBox(height: 24),
                  UserUi.premiumButton(
                    label: _isLoading ? 'Registering Batch...' : 'Register Batch',
                    onTap: _isLoading ? () {} : _stageBatchOutboundCustomerOrders,
                    icon: Icons.lock_open_rounded,
                    fontSize: 14.5,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),

            // Tab 3: Personal Pickup
            SingleChildScrollView(
              padding: UserUi.listPadding(context, top: 20, bottom: 40),
              child: Form(
                key: _formKeyPersonal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Register returns or personal packages to be collected from your Dropbox.',
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _personalTrackingIdController,
                      decoration: _buildInputDecoration(
                        label: 'Tracking ID',
                        prefixIcon: Icons.tag_rounded,
                        isDark: isDark,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange),
                          onPressed: () => _scanBarcode(
                            onScanned: (code) => setState(() => _personalTrackingIdController.text = code),
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter tracking ID' : null,
                    ),
                    const SizedBox(height: 20),
                    UserUi.sectionTitle(context, 'Courier / Service', subtitle: 'Select return carrier'),
                    const SizedBox(height: 10),
                    _buildCourierChips(
                      couriers: ['Spx', 'J&T Express', 'Lalamove', 'NinjaVan', 'PosLaju'],
                      selectedCourier: _selectedCourierPersonal,
                      onSelected: (val) => setState(() => _selectedCourierPersonal = val),
                      isDark: isDark,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: _buildInputDecoration(
                        label: 'Description',
                        prefixIcon: Icons.description_outlined,
                        isDark: isDark,
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'Please enter description' : null,
                    ),
                    const SizedBox(height: 28),
                    UserUi.premiumButton(
                      label: _isLoading ? 'Scheduling...' : 'Schedule Personal Pickup',
                      fontSize: 14.5,
                      onTap: _isLoading ? () {} : _registerPersonalPickup,
                      isLoading: _isLoading,
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
