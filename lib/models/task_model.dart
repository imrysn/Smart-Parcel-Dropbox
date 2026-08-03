import 'package:flutter/material.dart';
import '../config/user_theme.dart';

class TaskModel {
  final String id;
  final String userId;
  final String title;
  final String stage; // INQUIRY, CRAFTING, READY_FOR_BOX, SHIPPED
  final String platform; // SHOPEE, TIKTOK, INSTAGRAM, CUSTOM
  final String? customerName;
  final String? customerPhone;
  final String? trackingId;
  final String? courierName;
  final String? courierOtp;
  final DateTime? dueDate;
  final String? notes;
  final DateTime? createdAt;

  TaskModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.stage,
    this.platform = 'CUSTOM',
    this.customerName,
    this.customerPhone,
    this.trackingId,
    this.courierName,
    this.courierOtp,
    this.dueDate,
    this.notes,
    this.createdAt,
  });

  factory TaskModel.fromMap(Map<String, dynamic> data) {
    return TaskModel(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      stage: data['stage']?.toString() ?? 'INQUIRY',
      platform: data['platform']?.toString() ?? 'CUSTOM',
      customerName: data['customerName']?.toString(),
      customerPhone: data['customerPhone']?.toString(),
      trackingId: data['trackingId']?.toString(),
      courierName: data['courierName']?.toString(),
      courierOtp: data['courierOtp']?.toString(),
      dueDate: data['dueDate'] != null ? DateTime.tryParse(data['dueDate'].toString()) : null,
      notes: data['notes']?.toString(),
      createdAt: data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'stage': stage,
      'platform': platform,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'trackingId': trackingId,
      'courierName': courierName,
      'courierOtp': courierOtp,
      'dueDate': dueDate?.toIso8601String(),
      'notes': notes,
    };
  }

  TaskModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? stage,
    String? platform,
    String? customerName,
    String? customerPhone,
    String? trackingId,
    String? courierName,
    String? courierOtp,
    DateTime? dueDate,
    String? notes,
    DateTime? createdAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      stage: stage ?? this.stage,
      platform: platform ?? this.platform,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      trackingId: trackingId ?? this.trackingId,
      courierName: courierName ?? this.courierName,
      courierOtp: courierOtp ?? this.courierOtp,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  IconData get platformIcon {
    switch (platform.toUpperCase()) {
      case 'SHOPEE':
        return Icons.shopping_bag_outlined;
      case 'TIKTOK':
        return Icons.music_note_outlined;
      case 'INSTAGRAM':
        return Icons.camera_alt_outlined;
      default:
        return Icons.storefront_outlined;
    }
  }

  Color get platformColor {
    switch (platform.toUpperCase()) {
      case 'SHOPEE':
        return Colors.deepOrange;
      case 'TIKTOK':
        return Colors.tealAccent.shade700;
      case 'INSTAGRAM':
        return Colors.purpleAccent;
      default:
        return UserTheme.primaryOrange;
    }
  }

  Color get stageColor {
    switch (stage) {
      case 'INQUIRY':
        return Colors.blueAccent;
      case 'CRAFTING':
        return UserTheme.primaryOrange;
      case 'READY_FOR_BOX':
        return Colors.indigoAccent;
      case 'SHIPPED':
        return UserTheme.statusSuccess;
      default:
        return Colors.grey;
    }
  }

  String get stageLabel {
    switch (stage) {
      case 'INQUIRY':
        return 'INQUIRY / LEAD';
      case 'CRAFTING':
        return 'IN CRAFTING';
      case 'READY_FOR_BOX':
        return 'READY FOR BOX';
      case 'SHIPPED':
        return 'SHIPPED & DONE';
      default:
        return stage;
    }
  }
}
