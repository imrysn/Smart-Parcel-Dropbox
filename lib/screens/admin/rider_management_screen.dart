import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/api_config.dart';

class RiderManagementScreen extends StatefulWidget {
  final bool isEmbedded;
  const RiderManagementScreen({Key? key, this.isEmbedded = false}) : super(key: key);

  @override
  State<RiderManagementScreen> createState() => _RiderManagementScreenState();
}

class _RiderManagementScreenState extends State<RiderManagementScreen> {
  List<dynamic> _riders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/riders'));
      if (response.statusCode == 200) {
        setState(() {
          _riders = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching riders: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addRider(String riderId, String name) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/riders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'riderId': riderId, 'name': name}),
      );
      if (response.statusCode == 201) {
        _fetchRiders(); // Refresh
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${jsonDecode(response.body)['message']}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error adding rider: $e');
    }
  }

  Future<void> _deleteRider(String id) async {
    try {
      final response = await http.delete(Uri.parse('${ApiConfig.baseUrl}/riders/$id'));
      if (response.statusCode == 200) {
        _fetchRiders(); // Refresh
      }
    } catch (e) {
      debugPrint('Error deleting rider: $e');
    }
  }

  void _showAddRiderDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register Rider Access'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the QR/Barcode from the courier manifest or handover tracking ID. The rider will scan this to open the box.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Courier / Rider Name',
                hintText: 'e.g. J&T Express / John Doe',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Manifest Barcode / ID',
                hintText: 'e.g. PH-JNT-123456',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && idController.text.isNotEmpty) {
                _addRider(idController.text, nameController.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  void _showQRCodeDialog(String riderId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('QR Code: $name'),
        content: SizedBox(
          width: 200,
          height: 250,
          child: Column(
            children: [
              QrImageView(
                data: riderId,
                version: QrVersions.auto,
                size: 200.0,
              ),
              const SizedBox(height: 10),
              Text(
                riderId,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isEmbedded 
          ? null 
          : AppBar(
              title: const Text('Manage Delivery Riders'),
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRiderDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Rider'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _riders.isEmpty
              ? const Center(child: Text('No riders registered yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 100),
                  itemCount: _riders.length,
                  itemBuilder: (context, index) {
                    final rider = _riders[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade100,
                          child: const Icon(Icons.motorcycle, color: Colors.orange),
                        ),
                        title: Text(rider['name'] ?? 'Unknown'),
                        subtitle: Text('ID: ${rider['riderId']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.qr_code, color: Colors.blue),
                              tooltip: 'Show QR Code',
                              onPressed: () => _showQRCodeDialog(rider['riderId'], rider['name']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Revoke Access',
                              onPressed: () => _deleteRider(rider['_id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
