import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Standalone single-responsibility component for Carrier Brand Badges.
class CarrierBadge extends StatelessWidget {
  final String shopName;

  const CarrierBadge({
    super.key,
    required this.shopName,
  });

  @override
  Widget build(BuildContext context) {
    final lowerName = shopName.toLowerCase();
    Color badgeColor = UserTheme.primaryOrange;
    IconData badgeIcon = Icons.local_shipping_rounded;
    String label = shopName;

    if (lowerName.contains('shopee')) {
      badgeColor = const Color(0xFFEE4D2D);
      badgeIcon = Icons.shopping_bag_rounded;
      label = 'Shopee';
    } else if (lowerName.contains('lazada')) {
      badgeColor = const Color(0xFF0F146D);
      badgeIcon = Icons.storefront_rounded;
      label = 'Lazada';
    } else if (lowerName.contains('tiktok')) {
      badgeColor = Colors.black;
      badgeIcon = Icons.music_note_rounded;
      label = 'TikTok Shop';
    } else if (lowerName.contains('amazon')) {
      badgeColor = const Color(0xFFFF9900);
      badgeIcon = Icons.shopping_cart_rounded;
      label = 'Amazon';
    } else if (lowerName.contains('fedex')) {
      badgeColor = const Color(0xFF4D148C);
      label = 'FedEx';
    } else if (lowerName.contains('dhl')) {
      badgeColor = const Color(0xFFFFCC00);
      label = 'DHL';
    } else if (lowerName.contains('j&t') || lowerName.contains('jnt')) {
      badgeColor = const Color(0xFFE30613);
      label = 'J&T Express';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 14, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
