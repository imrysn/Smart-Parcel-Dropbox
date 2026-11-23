import 'package:flutter/material.dart';
import '../../../config/user_theme.dart';
import '../../../models/tracking_model.dart';
import '../../../screens/add_pickup_screen.dart';
import '../../../screens/add_tracking_screen.dart';
import '../../../screens/tracking_details_screen.dart';
import '../../../services/database_service.dart';
import '../../../widgets/user_ui.dart';
import '../../components/dropbox_hero_card.dart';
import '../../components/order_card.dart';

/// Home Dashboard Tab
///
/// Remodeled Smart App Home view featuring:
/// 1. Dynamic Greeting Header ("Hello, [Name]!" + time-of-day greeting).
/// 2. 3D Model Hero Card reusing the Dropbox Tab's Three.js viewer as a
///    real-time, non-rotatable background with dynamic dawn/day/dusk/night sky.
/// 3. Minimalist Quick Actions (Add Tracking, Schedule Pickup).
/// 4. Recent Deliveries section with View Orders shortcut.
/// 5. Live Activity Feed or Smart Vault Armed Empty State.
class HomeDashboardTab extends StatelessWidget {
  final String userId;
  final bool hasDropbox;
  final bool hardwareOnline;
  final String? deviceName;
  final DatabaseService databaseService;
  final bool devModeEnabled;
  final Future<void> Function()? onRefresh;
  final VoidCallback onSetupDropbox;
  final VoidCallback? onOpenCabinet;
  final VoidCallback onViewOrders;

  const HomeDashboardTab({
    super.key,
    required this.userId,
    required this.hasDropbox,
    required this.databaseService,
    required this.onSetupDropbox,
    required this.onViewOrders,
    this.hardwareOnline = true,
    this.devModeEnabled = false,
    this.deviceName,
    this.onOpenCabinet,
    this.onRefresh,
  });

  /// Computes contextual greeting matching the local time of day.
  static String getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return 'Good morning, your dropbox is secure.';
    } else if (hour >= 12 && hour < 17) {
      return 'Good afternoon, welcome back.';
    } else if (hour >= 17 && hour < 21) {
      return 'Good evening, all doors secured.';
    } else {
      return 'Good night, vault armed and locked.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: isDark ? Colors.white : Colors.black,
      onRefresh: onRefresh ??
          () async {
            await databaseService.refreshTracking(userId);
          },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UserUi.listPadding(context, top: 12, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── 1. Smart App Greeting Header (Matching Reference UI) ───
            FutureBuilder<Map<String, dynamic>?>(
              future: databaseService.getUserData(userId),
              builder: (context, userSnap) {
                final rawName = userSnap.data?['fullName'] as String?;
                final firstName =
                    (rawName != null && rawName.trim().isNotEmpty)
                        ? rawName.trim().split(' ').first
                        : 'User';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14, left: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? UserTheme.nightTextPrimary
                                : UserTheme.dayTextPrimary,
                            letterSpacing: -0.5,
                          ),
                          children: [
                            const TextSpan(text: 'Hello, '),
                            TextSpan(
                              text: '$firstName !',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        getTimeGreeting(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? UserTheme.nightTextSecondary
                              : UserTheme.dayTextSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            StreamBuilder<List<TrackingModel>>(
              stream: databaseService.getUserTrackingIds(userId),
              initialData: databaseService.cachedTracking,
              builder: (context, snapshot) {
                final allOrders = snapshot.data ?? [];
                final dropOffBinCount = allOrders
                    .where((o) =>
                        (o.mode == 'drop_off' || o.mode.isEmpty) &&
                        o.status == 'delivered')
                    .length;
                final pickupBinCount = allOrders
                    .where((o) =>
                        o.mode == 'pick_up' &&
                        (o.status == 'registered' || o.status == 'pending'))
                    .length;
                final inBoxParcel = allOrders
                    .where((o) => o.status == 'delivered')
                    .firstOrNull;
                final recentOrders = allOrders.take(2).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hasDropbox) ...[
                      _buildNoDropboxBanner(context, isDark),
                      const SizedBox(height: 14),
                    ],

                    // ─── 2. 3D Model Hero Card (Reusing Dropbox Tab 3D Scene) ───
                    DropboxHeroCard(
                      deviceName: deviceName ?? 'Smart Parcel Dropbox',
                      parcelCount: dropOffBinCount,
                      pickupCount: pickupBinCount,
                      doorStateStream: databaseService.getDropBoxDoorState(),
                      hardwareOnline: hardwareOnline,
                      simulationEnabled: devModeEnabled,
                      latestDelivery: inBoxParcel?.registeredAt,
                      onOpenCabinet: onOpenCabinet ?? onSetupDropbox,
                      onTap: inBoxParcel != null
                          ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => TrackingDetailsScreen(
                                      tracking: inBoxParcel),
                                ),
                              )
                          : (onOpenCabinet ?? onSetupDropbox),
                    ),

                    const SizedBox(height: 16),

                    // ─── 3. Minimalist Quick Actions ───
                    Row(
                      children: [
                        _buildQuickActionButton(
                          context: context,
                          icon: Icons.add_box_outlined,
                          label: 'Add Tracking',
                          onTap: () => Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                                builder: (_) => const AddTrackingScreen()),
                          )
                              .then((_) {
                            databaseService.refreshTracking(userId);
                          }),
                        ),
                        const SizedBox(width: 10),
                        _buildQuickActionButton(
                          context: context,
                          icon: Icons.local_shipping_outlined,
                          label: 'Schedule Pickup',
                          onTap: () => Navigator.of(context)
                              .push(
                            MaterialPageRoute(
                                builder: (_) => const AddPickupScreen()),
                          )
                              .then((_) {
                            databaseService.refreshTracking(userId);
                          }),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    // ─── 4. Recent Orders Section Header ───
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent Orders',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? UserTheme.nightTextPrimary
                                  : UserTheme.dayTextPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: onViewOrders,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Orders',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ─── 5. Recent 2 Orders Stream or Smart Vault Empty State ───
                    if (recentOrders.isEmpty) ...[
                      UserUi.emptyState(
                        context,
                        icon: Icons.inventory_2_outlined,
                        title: 'No Recent Orders',
                        subtitle:
                            'Incoming courier deliveries and staged pickups will appear here.',
                      ),
                    ] else ...[
                      ...recentOrders.map((order) =>
                          OrderCard(order: order, showDelete: false)),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 120), // Clearance for floating navbar
          ],
        ),
      ),
    );
  }

  Widget _buildNoDropboxBanner(BuildContext context, bool isDark) {
    final borderColor = isDark ? Colors.white : Colors.black;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : Colors.white,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: borderColor,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded,
                    color: borderColor, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Set Up Your Dropbox',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Register your Smart Parcel Dropbox to sync deliveries and pickups with your phone.',
              style: TextStyle(
                color: isDark
                    ? UserTheme.nightTextSecondary
                    : UserTheme.dayTextSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            UserUi.premiumButton(
              label: 'Register Hardware',
              onTap: onSetupDropbox,
              icon: Icons.arrow_forward_rounded,
              color: isDark ? Colors.white : Colors.black,
              textColor: isDark ? Colors.black : Colors.white,
            ),
          ],
        ),
      );
  }

  Widget _buildQuickActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white : Colors.black;
    final textColor = isDark ? Colors.white : Colors.black;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(UserTheme.radiusL),
              border: Border.all(
                color: borderColor,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: textColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
