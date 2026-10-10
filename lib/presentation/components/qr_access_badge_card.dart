import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/user_theme.dart';

/// Single-responsibility component for QR Access Badge Card.
class QrAccessBadgeCard extends StatelessWidget {
  final String qrToken;
  final VoidCallback onRefresh;

  const QrAccessBadgeCard({
    super.key,
    required this.qrToken,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = UserTheme.primaryOrange;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        border: Border.all(color: primary.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'QR Access Badge',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: primary,
                onPressed: onRefresh,
                tooltip: 'Refresh Digital QR Token',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrToken,
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
                      'Hold QR up to Scanner',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan this QR code using the MH-ET scanner on your physical Dropbox to unlock doors.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
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
