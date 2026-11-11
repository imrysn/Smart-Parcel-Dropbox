import 'package:flutter/material.dart';
import '../config/user_theme.dart';

class TransactionModel {
  final String id;
  final String userId;
  final String type; // REVENUE, EXPENSE_SHIPPING, EXPENSE_MATERIAL, EXPENSE_OTHER
  final double amount;
  final String category;
  final String? description;
  final String? referenceId;
  final DateTime date;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.category = 'General',
    this.description,
    this.referenceId,
    required this.date,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> data) {
    return TransactionModel(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      type: data['type']?.toString() ?? 'REVENUE',
      amount: (data['amount'] ?? 0.0) is int ? (data['amount'] as int).toDouble() : (data['amount'] ?? 0.0) as double,
      category: data['category']?.toString() ?? 'General',
      description: data['description']?.toString(),
      referenceId: data['referenceId']?.toString(),
      date: data['date'] != null ? DateTime.parse(data['date'].toString()) : DateTime.now(),
    );
  }

  bool get isRevenue => type == 'REVENUE';

  Color get typeColor {
    if (isRevenue) return UserTheme.statusSuccess;
    if (type == 'EXPENSE_SHIPPING') return Colors.indigo;
    if (type == 'EXPENSE_MATERIAL') return UserTheme.primaryOrange;
    return UserTheme.statusError;
  }

  IconData get typeIcon {
    if (isRevenue) return Icons.arrow_downward_rounded;
    if (type == 'EXPENSE_SHIPPING') return Icons.local_shipping_outlined;
    if (type == 'EXPENSE_MATERIAL') return Icons.category_outlined;
    return Icons.arrow_upward_rounded;
  }
}

class FinancialSummaryModel {
  final double grossRevenue;
  final double totalExpenses;
  final double shippingExpenses;
  final double materialExpenses;
  final double netProfit;
  final double marginPercent;

  FinancialSummaryModel({
    required this.grossRevenue,
    required this.totalExpenses,
    required this.shippingExpenses,
    required this.materialExpenses,
    required this.netProfit,
    required this.marginPercent,
  });

  factory FinancialSummaryModel.fromMap(Map<String, dynamic> data) {
    return FinancialSummaryModel(
      grossRevenue: (data['grossRevenue'] ?? 0.0).toDouble(),
      totalExpenses: (data['totalExpenses'] ?? 0.0).toDouble(),
      shippingExpenses: (data['shippingExpenses'] ?? 0.0).toDouble(),
      materialExpenses: (data['materialExpenses'] ?? 0.0).toDouble(),
      netProfit: (data['netProfit'] ?? 0.0).toDouble(),
      marginPercent: (data['marginPercent'] ?? 0.0).toDouble(),
    );
  }
}
