import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/payment_qr_model.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class PaymentService {
  static PaymentService? _instance;

  factory PaymentService() {
    _instance ??= PaymentService._internal();
    return _instance!;
  }

  PaymentService._internal();

  final _authService = AuthService();

  /// Fetch merchant payment config (GCash, Maya, Bank)
  Future<PaymentQrModel?> fetchPaymentConfig() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.payments}/config'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return PaymentQrModel.fromMap(body['data'] ?? {});
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching payment config: $e');
      return null;
    }
  }

  /// Save / Update merchant payment config
  Future<PaymentQrModel> savePaymentConfig({
    String? gcashName,
    String? gcashNumber,
    String? mayaName,
    String? mayaNumber,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.payments}/config'),
        headers: headers,
        body: jsonEncode({
          'gcashName': gcashName,
          'gcashNumber': gcashNumber,
          'mayaName': mayaName,
          'mayaNumber': mayaNumber,
          'bankName': bankName,
          'bankAccountName': bankAccountName,
          'bankAccountNumber': bankAccountNumber,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return PaymentQrModel.fromMap(body['data']);
      } else {
        throw body['message'] ?? 'Failed to save payment settings';
      }
    } catch (e) {
      throw 'Save payment settings error: $e';
    }
  }

  /// Generate customer payment invoice request
  Future<Map<String, String>> generateInvoice({
    required String customerName,
    required String orderItem,
    required double amount,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.payments}/generate-invoice'),
        headers: headers,
        body: jsonEncode({
          'customerName': customerName,
          'orderItem': orderItem,
          'amount': amount,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final data = body['data'] ?? {};
        return {
          'text': data['text']?.toString() ?? '',
          'shareText': (data['shareText'] ?? data['text'])?.toString() ?? '',
        };
      } else {
        throw body['message'] ?? 'Failed to generate invoice';
      }
    } catch (e) {
      throw 'Generate invoice error: $e';
    }
  }
}
