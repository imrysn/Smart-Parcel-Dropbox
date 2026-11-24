import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../widgets/user_ui.dart';

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
    final theme = Theme.of(context);
    final token = qrToken;
    final secondaryText = theme.textTheme.bodyMedium?.copyWith(
      color: UserUi.dashboardColors(context).secondary,
      fontSize: 13,
    );

    return UserUi.dashboardCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick Unlock QR',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            token == null
                ? 'Create a one-time pass for your Dropbox scanner.'
                : 'Hold this QR code in front of the Dropbox scanner.',
            style: secondaryText,
          ),
          if (token != null) ...[
            const SizedBox(height: UserUi.sM),
            Center(
              child: Semantics(
                image: true,
                label: 'One-time access QR code',
                child: QrImageView(
                  data: token,
                  size: 168,
                  padding: const EdgeInsets.all(12),
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
          const SizedBox(height: UserUi.sS),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: onRefresh,
              child: Text(
                onRefresh == null
                    ? 'Generating QR…'
                    : (token == null
                        ? 'Generate one-time QR'
                        : 'Generate new QR'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
