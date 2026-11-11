import 'package:flutter/material.dart';
import '../../config/user_theme.dart';
import 'carrier_badge.dart';

/// Spotlight card summarizing parcels currently secured inside the Dropbox.
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
    const primary = UserTheme.primaryOrange;
    final hasParcel = inBoxParcel != null;

    if (!hasParcel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 26,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Box is empty',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? UserTheme.nightTextPrimary
                          : UserTheme.dayTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Delivered parcels waiting inside will appear here.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? UserTheme.nightTextMuted
                          : UserTheme.dayTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.35 : 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapDetails,
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ready in box · $totalInBoxCount ${totalInBoxCount == 1 ? 'parcel' : 'parcels'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: UserTheme.statusSuccess,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CarrierBadge(
                      shopName: inBoxParcel.shopName ?? 'Parcel',
                      fontSize: 13.5,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inBoxParcel.trackingId ?? 'N/A',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? UserTheme.nightTextPrimary
                                  : UserTheme.dayTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Tap to view pickup QR & parcel details',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? UserTheme.nightTextMuted
                                  : UserTheme.dayTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.qr_code_2_rounded,
                      size: 24,
                      color: primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
