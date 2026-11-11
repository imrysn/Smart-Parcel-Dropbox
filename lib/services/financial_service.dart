import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class FinancialService {
  static FinancialService? _instance;

  factory FinancialService() {
    _instance ??= FinancialService._internal();
    return _instance!;
  }

  FinancialService._internal();

  final _authService = AuthService();

  /// Fetch financial summary & transactions
  Future<Map<String, dynamic>> fetchFinancialSummary() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.financial}/summary'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] ?? {};
        
        final summary = FinancialSummaryModel.fromMap(data['summary'] ?? {});
        final List txList = data['recentTransactions'] ?? [];
        final transactions = txList.map((json) => TransactionModel.fromMap(json)).toList();

        return {
          'summary': summary,
          'transactions': transactions,
        };
      }
      return {
        'summary': FinancialSummaryModel(grossRevenue: 0, totalExpenses: 0, shippingExpenses: 0, materialExpenses: 0, netProfit: 0, marginPercent: 0),
        'transactions': <TransactionModel>[],
      };
    } catch (e) {
      debugPrint('Error fetching financial summary: $e');
      return {
        'summary': FinancialSummaryModel(grossRevenue: 0, totalExpenses: 0, shippingExpenses: 0, materialExpenses: 0, netProfit: 0, marginPercent: 0),
        'transactions': <TransactionModel>[],
      };
    }
  }

  /// Create a new transaction (Revenue or Craft Supply Expense)
  Future<TransactionModel> createTransaction({
    required String type, // REVENUE, EXPENSE_SHIPPING, EXPENSE_MATERIAL, EXPENSE_OTHER
    required double amount,
    String category = 'General',
    String? description,
    String? referenceId,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.financial}/transactions'),
        headers: headers,
        body: jsonEncode({
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
          'referenceId': referenceId,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return TransactionModel.fromMap(body['data']);
      } else {
        throw body['message'] ?? 'Failed to record transaction';
      }
    } catch (e) {
      throw 'Transaction error: $e';
    }
  }

  /// Delete a transaction
  Future<void> deleteTransaction(String id) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.financial}/transactions/$id'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw body['message'] ?? 'Failed to delete transaction';
      }
    } catch (e) {
      throw 'Delete transaction error: $e';
    }
  }

  /// Sync Inbound Shopee/TikTok supply parcel arrival to Financial Ledger
  Future<TransactionModel> syncInboundSupplyExpense({
    required String trackingId,
    required double amount,
    String? supplyName,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.financial}/sync-inbound-supply'),
        headers: headers,
        body: jsonEncode({
          'trackingId': trackingId,
          'amount': amount,
          'supplyName': supplyName,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return TransactionModel.fromMap(body['data']);
      } else {
        throw body['message'] ?? 'Failed to sync inbound supply expense';
      }
    } catch (e) {
      throw 'Sync supply expense error: $e';
    }
  }

  /// Fetch 30-day cash flow trends & analytics
  Future<Map<String, dynamic>> fetchFinancialAnalytics() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.financial}/analytics'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data'] ?? {};
      }
      return {};
    } catch (e) {
      debugPrint('Error fetching financial analytics: $e');
      return {};
    }
  }
}
