import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/scan_log_model.dart';

/// Scan Logs Screen - Displays parcel and access scan history.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

  String? _userId;
  String _filter = 'all'; // 'all', 'granted', 'denied'

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    _userId = await _authService.currentUserId;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
              : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    if (_userId == null) {
      return Container(
        decoration: UserUi.pageBackground(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: UserUi.shimmerList(context, count: 4, cardHeight: 92),
        ),
      );
    }

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: 'Scan Logs',
          centerTitle: false,
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
        ),
        body: Column(
          children: [
            UserUi.responsiveContainer(
              context,
              maxWidth: 600,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(
                  UserUi.horizontalGutter(context),
                  10,
                  UserUi.horizontalGutter(context),
                  6,
                ),
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Granted', 'granted'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Denied', 'denied'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<ScanLogModel>>(
                stream: _databaseService.getUserScanLogs(_userId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return UserUi.shimmerList(context, count: 4, cardHeight: 92);
                  }

                  if (snapshot.hasError) {
                    return UserUi.emptyState(
                      context,
                      icon: Icons.cloud_off_rounded,
                      title: 'Could Not Load Scan Logs',
                      subtitle: snapshot.error.toString(),
                    );
                  }

                  final allLogs = snapshot.data ?? [];
                  final filteredLogs = allLogs.where((log) {
                    if (_filter == 'granted') return log.accessGranted;
                    if (_filter == 'denied') return !log.accessGranted;
                    return true;
                  }).toList();

                  if (filteredLogs.isEmpty) {
                    return UserUi.emptyState(
                      context,
                      icon: Icons.history_rounded,
                      title: _filter == 'all'
                          ? 'No Scan Logs Yet'
                          : (_filter == 'granted' ? 'No Granted Scans' : 'No Denied Scans'),
                      subtitle: 'Barcode and QR scans at your Dropbox will appear here.',
                    );
                  }

                  return ListView.builder(
                    padding: UserUi.listPadding(context, top: 8, bottom: 32),
                    itemCount: filteredLogs.length,
                    itemBuilder: (context, index) => _buildLogCard(filteredLogs[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(ScanLogModel log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGranted = log.accessGranted;
    final statusColor = isGranted ? UserTheme.statusSuccess : UserTheme.statusError;
    final statusText = isGranted ? 'Access Granted' : 'Access Denied';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showLogDetails(context, log),
            borderRadius: BorderRadius.circular(UserTheme.radiusL),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserUi.statusPill(label: statusText, color: statusColor),
                      const Spacer(),
                      Text(
                        log.getFormattedDateTime(),
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    log.scannedCode,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                  if (log.trackingId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Waybill: ${log.trackingId!}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                      ),
                    ),
                  ],
                  if (!log.accessGranted && log.reason != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: UserTheme.statusError.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        log.reason!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: UserTheme.statusError,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        log.getFullFormattedDateTime(),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogDetails(BuildContext context, ScanLogModel log) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: const Text('Scan Details', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(context, 'Status', log.accessGranted ? 'Access Granted' : 'Access Denied'),
              _buildDetailRow(context, 'Date & Time', log.getFullFormattedDateTime()),
              _buildDetailRow(context, 'Scanned Code', log.scannedCode, isMonospace: true),
              if (log.trackingId != null)
                _buildDetailRow(context, 'Tracking ID', log.trackingId!, isMonospace: true),
              if (log.userId != null)
                _buildDetailRow(context, 'User ID', log.userId!, isMonospace: true),
              if (log.reason != null)
                _buildDetailRow(context, 'Reason', log.reason!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isMonospace = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: isMonospace ? 'monospace' : null,
              fontWeight: FontWeight.w600,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
