import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Clean typographic merchant/carrier label with normalized brand naming.
class CarrierBadge extends StatelessWidget {
  final String shopName;
  final double fontSize;

  const CarrierBadge({
    super.key,
    required this.shopName,
    this.fontSize = 15,
  });

  static String resolveLabel(String shopName) {
    final trimmed = shopName.trim();
    final lowerName = trimmed.toLowerCase();

    if (lowerName.contains('shopee')) return 'Shopee';
    if (lowerName.contains('lazada')) return 'Lazada';
    if (lowerName.contains('tiktok')) return 'TikTok Shop';
    if (lowerName.contains('amazon')) return 'Amazon';
    if (lowerName.contains('fedex')) return 'FedEx';
    if (lowerName.contains('dhl')) return 'DHL';
    if (lowerName.contains('j&t') || lowerName.contains('jnt')) return 'J&T Express';
    return trimmed.isEmpty ? 'Parcel' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = resolveLabel(shopName);

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
      ),
    );
  }
}
