import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../services/service_locator.dart';
import '../widgets/camera_barcode_scanner_dialog.dart';

class DropoffBatchesScreen extends StatefulWidget {
  const DropoffBatchesScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<DropoffBatchesScreen> createState() => _DropoffBatchesScreenState();
}

class _DropoffBatchesScreenState extends State<DropoffBatchesScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> _batches;
  bool _confirming = false;

  String get _boxUrl =>
      '${ApiConfig.dropbox}/${Uri.encodeComponent(widget.deviceId)}';

  @override
  void initState() {
    super.initState();
    _batches = _load();
  }

  Future<Map<String, List<Map<String, dynamic>>>> _load() async {
    final headers = await getIt<AuthService>().getAuthHeaders();
    final response = await http
        .get(Uri.parse('$_boxUrl/dropoff-batches'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const FormatException('Could not load drop-off batches.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final batches = <String, List<Map<String, dynamic>>>{};
    for (final item in (body['items'] as List).cast<Map<String, dynamic>>()) {
      (batches[item['batchId'] as String] ??= []).add(item);
    }
    return batches;
  }

  Future<void> _refresh() async {
    final batches = _load();
    setState(() => _batches = batches);
    try {
      await batches;
    } catch (_) {
      // FutureBuilder displays the request failure and a retry action.
    }
  }

  bool _needsReview(Map<String, dynamic> item) =>
      item['needsReview'] == true && item['reviewedAt'] == null;

  Future<void> _confirm(String receiptId) async {
    setState(() => _confirming = true);
    try {
      final scan = await CameraBarcodeScannerDialog.scan(context);
      if (scan == null || !mounted) return;
      final headers = await getIt<AuthService>().getAuthHeaders();
      final response = await http
          .post(
            Uri.parse(
              '$_boxUrl/dropoff-reviews/${Uri.encodeComponent(receiptId)}/confirm',
            ),
            headers: headers,
            body: jsonEncode({'barcode': scan.trackingId}),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode == 200) {
        await _refresh();
      } else {
        _showMessage(response.statusCode == 400
            ? 'The scanned waybill does not match this parcel.'
            : 'Could not confirm this parcel. Refresh and try again.');
      }
    } catch (_) {
      if (mounted) _showMessage('Could not confirm this parcel. Try again.');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drop-off batches')),
      body: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
        future: _batches,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: _refresh,
                child: const Text('Could not load batches. Retry'),
              ),
            );
          }
          final batches = snapshot.data!.values;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (batches.isEmpty)
                  const ListTile(title: Text('No batches synced yet')),
                for (final items in batches) _batchCard(items),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _batchCard(List<Map<String, dynamic>> items) {
    final reviewCount = items.where(_needsReview).length;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: reviewCount > 0,
        title: Text(
            '${items.length - reviewCount} delivered · $reviewCount need review'),
        children: [
          for (final item in items)
            ListTile(
              title: Text(item['trackingId'] as String),
              subtitle: Text(_needsReview(item) ? 'Needs review' : 'Delivered'),
              trailing: _needsReview(item)
                  ? TextButton(
                      onPressed: _confirming
                          ? null
                          : () => _confirm(item['_id'] as String),
                      child: const Text('Scan waybill'),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
