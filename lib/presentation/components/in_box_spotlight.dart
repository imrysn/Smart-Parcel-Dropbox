import 'package:flutter/material.dart';
import '../../config/user_theme.dart';
import 'carrier_badge.dart';
import 'status_pill.dart';

/// Standalone single-responsibility component for In-Box Parcel Spotlight Card.
class InBoxSpotlight extends StatelessWidget {
  final dynamic inBoxParcel; // TrackingModel?
  final int totalInBoxCount;
  final VoidCallback onTapDetails;

  const InBoxSpotlight({
    super.key,
    required this.inBoxParcel,
    required this.totalInBoxCount,
    required this.onTapDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = UserTheme.primaryOrange;
    final hasParcel = inBoxParcel != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? (hasParcel ? [const Color(0xFF311B92), const Color(0xFF1A237E)] : [const Color(0xFF1E293B), const Color(0xFF0F172A)])
              : (hasParcel ? [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)] : [const Color(0xFFF8FAFC), const Color(0xFFEDF2F7)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        border: Border.all(
          color: hasParcel ? primary : (isDark ? Colors.white12 : Colors.black12),
          width: hasParcel ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasParcel ? primary.withOpacity(0.18) : Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hasParcel ? primary.withOpacity(0.2) : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasParcel ? Icons.mark_email_unread_rounded : Icons.inbox_rounded,
                  color: hasParcel ? primary : (isDark ? Colors.white60 : Colors.black54),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasParcel ? 'PARCEL WAITING IN BOX' : 'NO PARCELS IN BOX',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: hasParcel ? primary : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasParcel
                          ? '$totalInBoxCount package(s) deposited & ready for retrieval'
                          : 'Your Dropbox bin is currently empty',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasParcel)
                const StatusPill(label: 'READY', color: Color(0xFF10B981))
              else
                const StatusPill(label: 'CLEAR', color: Colors.grey),
            ],
          ),

          if (hasParcel) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.3) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  CarrierBadge(shopName: inBoxParcel.shopName ?? 'Parcel'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inBoxParcel.trackingId ?? 'N/A',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                            color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                          ),
                        ),
                        Text(
                          'Deposited into Dropbox Bin',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: onTapDetails,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'VIEW QR',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
