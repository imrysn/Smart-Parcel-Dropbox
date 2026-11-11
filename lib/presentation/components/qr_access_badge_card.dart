import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/user_theme.dart';

/// Displays the owner's dynamic QR token for quick hardware scanner access.
class QrAccessBadgeCard extends StatelessWidget {
  final String? qrToken;
  final VoidCallback? onRefresh;

  const QrAccessBadgeCard({
    super.key,
    required this.qrToken,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primary = UserTheme.primaryOrange;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_scanner_rounded, color: primary, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quick Unlock QR',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? UserTheme.nightTextPrimary
                        : UserTheme.dayTextPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 19),
                color: primary,
                onPressed: onRefresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                tooltip: qrToken == null ? 'Generate Access QR' : 'Refresh Access QR',
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (qrToken == null)
            OutlinedButton(onPressed: onRefresh, child: const Text('Generate one-time QR'))
          else Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: QrImageView(
                  data: qrToken!,
                  version: QrVersions.auto,
                  size: 68,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(2),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan at Dropbox Camera',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? UserTheme.nightTextPrimary
                            : UserTheme.dayTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hold this QR near your Dropbox scanner to verify identity and open doors.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? UserTheme.nightTextMuted
                            : UserTheme.dayTextSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
