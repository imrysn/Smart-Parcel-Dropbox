import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import 'user_ui.dart';

class DailyDigestCard extends StatelessWidget {
  final Map<String, dynamic>? digestData;
  final VoidCallback? onRefresh;
  final VoidCallback? onAddOutbound;

  const DailyDigestCard({
    Key? key,
    this.digestData,
    this.onRefresh,
    this.onAddOutbound,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final outbound = digestData?['outbound'] ?? {};
    final inbound = digestData?['inbound'] ?? {};
    final capacity = digestData?['capacity'] ?? {};

    final stagedToday = outbound['totalStagedToday'] ?? 0;
    final collectedToday = outbound['collectedToday'] ?? 0;
    final pendingPickup = outbound['pendingPickupCount'] ?? 0;
    final inboundDelivered = inbound['deliveredToday'] ?? 0;

    final capacityPercent = (capacity['percent'] ?? 0) as int;
    final capacityStatus = capacity['status'] ?? 'HEALTHY';

    final progress = stagedToday > 0 ? (collectedToday / stagedToday).clamp(0.0, 1.0) : 0.0;

    Color capacityColor = UserTheme.statusSuccess;
    if (capacityStatus == 'CRITICAL') {
      capacityColor = UserTheme.statusError;
    } else if (capacityStatus == 'WARNING') {
      capacityColor = UserTheme.statusWarning;
    }

    final cardBg = isDark ? UserTheme.nightCard : UserTheme.dayCard;
    final textPrimary = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final textSecondary = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final textMuted = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;
    final subCardBg = isDark ? UserTheme.nightSurface : UserTheme.daySurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: UserUi.glassCard(
        context,
        blur: 16,
        padding: const EdgeInsets.all(20),
        color: cardBg,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.primaryOrange.withOpacity(0.15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: UserTheme.primaryOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DAILY BUSINESS DIGEST",
                          style: TextStyle(
                            color: UserTheme.primaryOrange,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Logistics & Fulfillment",
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Capacity Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: capacityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: capacityColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, color: capacityColor, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        "$capacityPercent% Cap",
                        style: TextStyle(
                          color: capacityColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Outbound Fulfillment Progress Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Outbound Fulfillment",
                  style: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  "$collectedToday / $stagedToday Collected",
                  style: TextStyle(
                    color: UserTheme.primaryOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: isDark ? Colors.white10 : UserTheme.daySurface,
                valueColor: const AlwaysStoppedAnimation<Color>(UserTheme.primaryOrange),
              ),
            ),

            const SizedBox(height: 18),

            // Stat Cards Grid
            Row(
              children: [
                // Pending Courier Pickup
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: subCardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Awaiting Pickup",
                          style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              "$pendingPickup",
                              style: const TextStyle(
                                color: UserTheme.primaryOrange,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text("parcels", style: TextStyle(color: textMuted, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Inbound Stock Received Today
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: subCardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Supplier Stock In",
                          style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              "$inboundDelivered",
                              style: const TextStyle(
                                color: UserTheme.statusSuccess,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text("received", style: TextStyle(color: textMuted, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Action Button
            UserUi.premiumButton(
              label: 'STAGE NEW OUTGOING CUSTOMER ORDER',
              onTap: onAddOutbound ?? () {},
              icon: Icons.add_task_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
