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
  late Future<List<ScanLogModel>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = _scanLogService.getOwnerAccessLogs();
  }

  Future<void> _refresh() async {
    setState(() {
      _logsFuture = _scanLogService.getOwnerAccessLogs();
    });
    await _logsFuture;
  }

  String _formatReason(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Standard Unlock Request';
    final words = raw.replaceAll('_', ' ').trim().split(RegExp(r'\s+'));
    return words
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: 'Owner Access History',
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: FutureBuilder<List<ScanLogModel>>(
          future: _logsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return UserUi.shimmerList(context, count: 4, cardHeight: 84);
            }

            if (snapshot.hasError) {
              return RefreshIndicator(
                color: UserTheme.primaryOrange,
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 60),
                  child: UserUi.emptyState(
                    context,
                    icon: Icons.cloud_off_rounded,
                    title: 'Could Not Load Access Logs',
                    subtitle: 'Check your connection and pull down to try again.',
                  ),
                ),
              );
            }

            final logs = snapshot.data ?? [];

            if (logs.isEmpty) {
              return RefreshIndicator(
                color: UserTheme.primaryOrange,
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 60),
                  child: UserUi.emptyState(
                    context,
                    icon: Icons.history_rounded,
                    title: 'No Access Attempts Yet',
                    subtitle: 'Owner QR scans and unlock history will be logged here.',
                  ),
                ),
              );
            }

            return RefreshIndicator(
              color: UserTheme.primaryOrange,
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                itemCount: logs.length,
                itemBuilder: (context, index) => _buildLogCard(logs[index]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogCard(ScanLogModel log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGranted = log.accessGranted;
    final isPending = log.status == 'pending';

    final Color statusColor;
    final String statusText;

    if (isPending) {
      statusColor = UserTheme.statusWarning;
      statusText = 'Expired / Unanswered';
    } else if (isGranted) {
      statusColor = UserTheme.statusSuccess;
      statusText = 'Access Granted';
    } else {
      statusColor = UserTheme.statusError;
      statusText = 'Access Denied';
    }

    final attemptType = _formatReason(log.reason);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    attemptType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                UserUi.statusPill(label: statusText, color: statusColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              log.getFormattedDateTime(),
              style: TextStyle(
                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
