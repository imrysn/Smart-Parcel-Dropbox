import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/scan_log_service.dart';
import '../services/service_locator.dart';
import '../models/scan_log_model.dart';

/// Access Log Screen (Feature #7)
/// Shows a dedicated history of owner access attempts (approved, denied, expired).
class AccessLogScreen extends StatefulWidget {
  const AccessLogScreen({super.key});

  @override
  State<AccessLogScreen> createState() => _AccessLogScreenState();
}

class _AccessLogScreenState extends State<AccessLogScreen> {
  final ScanLogService _scanLogService = getIt<ScanLogService>();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: UserTheme.appBarGradient(
        title: 'Owner access history',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FutureBuilder<List<ScanLogModel>>(
        future: _scanLogService.getOwnerAccessLogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading access logs',
                    style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                  ),
                ],
              ),
            );
          }

          final logs = snapshot.data ?? [];

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No owner access attempts recorded',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildLogCard(log);
            },
          );
        },
      ),
      ),
    );
  }

  Widget _buildLogCard(ScanLogModel log) {
    // Determine visual status
    final isGranted = log.accessGranted;
    final isPending = log.status == 'pending'; // e.g., expired/unanswered QR
    
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (isPending) {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
      statusText = 'Unanswered / Expired';
    } else if (isGranted) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Access Granted';
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Access Denied';
    }

    // Attempt type details (reason)
    final String attemptType = log.reason?.replaceAll('_', ' ').toUpperCase() ?? 'UNKNOWN REQUEST';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 18, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  log.getFormattedDateTime(),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    attemptType,
                    style: const TextStyle(
                      fontSize: 12, 
                      fontWeight: FontWeight.bold, 
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
