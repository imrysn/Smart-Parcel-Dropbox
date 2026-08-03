import 'package:flutter/material.dart';
import '../../../models/tracking_model.dart';

/// Single-responsibility ViewModel for HomeScreen business logic and data manipulation.
class HomeViewModel extends ChangeNotifier {
  final TextEditingController searchController = TextEditingController();
  String selectedFilterTag = 'All';

  void setFilterTag(String tag) {
    selectedFilterTag = tag;
    notifyListeners();
  }

  void onSearchQueryChanged(String query) {
    notifyListeners();
  }

  void clearSearch() {
    searchController.clear();
    notifyListeners();
  }

  /// Filters orders dynamically based on search query & active category tag
  List<TrackingModel> filterOrders(List<TrackingModel> allOrders) {
    return allOrders.where((order) {
      final query = searchController.text.toLowerCase();
      final matchesQuery = query.isEmpty ||
          order.trackingId.toLowerCase().contains(query) ||
          order.shopName.toLowerCase().contains(query);

      if (!matchesQuery) return false;

      if (selectedFilterTag == 'In Box') {
        return order.status == 'delivered';
      } else if (selectedFilterTag == 'In Transit') {
        return ['pending', 'in_transit'].contains(order.status);
      } else if (selectedFilterTag == 'Pickups') {
        return order.mode == 'pickup';
      } else if (selectedFilterTag == 'Collected') {
        return order.status == 'done';
      }
      return true;
    }).toList();
  }

  /// Calculates weekly data counts for sparklines/charts
  List<int> calculateWeeklyData(List<TrackingModel> orders, bool Function(TrackingModel) filter) {
    final now = DateTime.now();
    final List<int> dailyCounts = List.filled(7, 0);

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateString = date.toIso8601String().split('T')[0];

      int countForDay = orders.where((o) {
        if (!filter(o)) return false;
        if (o.registeredAt == null) return false;
        final regDateStr = o.registeredAt!.toIso8601String().split('T')[0];
        return regDateStr == dateString;
      }).length;

      dailyCounts[6 - i] = countForDay;
    }
    return dailyCounts;
  }

  /// Returns weekday labels for weekly charts
  List<String> getWeeklyLabels() {
    final now = DateTime.now();
    final List<String> labels = [];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      labels.add(days[date.weekday - 1]);
    }
    return labels;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
