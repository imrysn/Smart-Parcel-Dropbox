import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/task_model.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class TaskService {
  static TaskService? _instance;

  factory TaskService() {
    _instance ??= TaskService._internal();
    return _instance!;
  }

  TaskService._internal();

  final _authService = AuthService();

  /// Fetch all tasks grouped by stage
  Future<Map<String, List<TaskModel>>> fetchGroupedTasks() async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.get(
        Uri.parse(ApiConfig.tasks),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final Map<String, dynamic> data = body['data'] ?? {};
        
        final Map<String, List<TaskModel>> result = {
          'INQUIRY': [],
          'CRAFTING': [],
          'READY_FOR_BOX': [],
          'SHIPPED': [],
        };

        data.forEach((stage, list) {
          if (list is List) {
            result[stage] = list.map((json) => TaskModel.fromMap(json)).toList();
          }
        });

        return result;
      }
      return {'INQUIRY': [], 'CRAFTING': [], 'READY_FOR_BOX': [], 'SHIPPED': []};
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      return {'INQUIRY': [], 'CRAFTING': [], 'READY_FOR_BOX': [], 'SHIPPED': []};
    }
  }

  /// Create a new task or customer inquiry lead
  Future<TaskModel> createTask({
    required String title,
    String stage = 'INQUIRY',
    String platform = 'CUSTOM',
    String? customerName,
    String? customerPhone,
    String? trackingId,
    String? courierName,
    DateTime? dueDate,
    String? notes,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.post(
        Uri.parse(ApiConfig.tasks),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'stage': stage,
          'platform': platform,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'trackingId': trackingId,
          'courierName': courierName,
          'dueDate': dueDate?.toIso8601String(),
          'notes': notes,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return TaskModel.fromMap(body['data']);
      } else {
        throw body['message'] ?? 'Failed to create task';
      }
    } catch (e) {
      throw 'Task creation error: $e';
    }
  }

  /// Update task stage (e.g. Move from CRAFTING -> READY_FOR_BOX)
  Future<TaskModel> updateTaskStage({
    required String taskId,
    required String newStage,
    bool openDoor = false,
  }) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.patch(
        Uri.parse('${ApiConfig.tasks}/$taskId/stage'),
        headers: headers,
        body: jsonEncode({
          'stage': newStage,
          'openDoor': openDoor,
        }),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return TaskModel.fromMap(body['data']);
      } else {
        throw body['message'] ?? 'Failed to update task stage';
      }
    } catch (e) {
      throw 'Update task stage error: $e';
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    try {
      final headers = await _authService.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.tasks}/$taskId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        throw body['message'] ?? 'Failed to delete task';
      }
    } catch (e) {
      throw 'Delete task error: $e';
    }
  }
}
