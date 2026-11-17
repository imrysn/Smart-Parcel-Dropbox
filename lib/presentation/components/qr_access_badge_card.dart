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
    final primaryText =
        isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText =
        isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary;
    final surfaceColor = isDark ? UserTheme.nightSurface : UserTheme.daySurface;
    final hasToken = qrToken != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: hasToken
              ? primary.withValues(alpha: isDark ? 0.34 : 0.28)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.07)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Quick Unlock QR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: primaryText,
                            ),
                          ),
                        ),
                        if (hasToken) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: UserTheme.statusSuccess
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Ready',
                              style: TextStyle(
                                color: UserTheme.statusSuccess,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasToken
                          ? 'Active pass · Show to box scanner'
                          : 'One-time owner verification pass',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  onRefresh == null
                      ? Icons.hourglass_top_rounded
                      : Icons.refresh_rounded,
                  size: 19,
                ),
                color: primary,
                onPressed: onRefresh,
                style: IconButton.styleFrom(
                  backgroundColor: primary.withValues(alpha: 0.10),
                  minimumSize: const Size(38, 38),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip:
                    hasToken ? 'Refresh Access QR' : 'Generate Access QR',
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: !hasToken
                ? SizedBox(
                    key: const ValueKey('qr-empty'),
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text(
                        onRefresh == null
                            ? 'Generating QR…'
                            : 'Generate one-time QR',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primary,
                        backgroundColor: surfaceColor,
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(
                          color: primary.withValues(alpha: 0.25),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  )
                : Container(
                    key: ValueKey('qr-$qrToken'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(1.0);
                        final stacked =
                            constraints.maxWidth < 250 || textScale > 1.3;
                        final qrBox = Container(
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
                            size: 74,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(2),
                          ),
                        );
                        final description = Column(
                          crossAxisAlignment: stacked
                              ? CrossAxisAlignment.center
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan at Dropbox Camera',
                              textAlign:
                                  stacked ? TextAlign.center : TextAlign.start,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: primaryText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hold this QR near your Dropbox scanner to verify identity and unlock.',
                              textAlign:
                                  stacked ? TextAlign.center : TextAlign.start,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryText,
                                height: 1.4,
                              ),
                            ),
                          ],
                        );

                        if (stacked) {
                          return Column(
                            children: [
                              qrBox,
                              const SizedBox(height: 12),
                              description,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            qrBox,
                            const SizedBox(width: 14),
                            Expanded(child: description),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
