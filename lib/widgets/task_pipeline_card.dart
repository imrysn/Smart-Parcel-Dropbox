import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task_model.dart';
import '../config/user_theme.dart';
import 'user_ui.dart';

class TaskPipelineCard extends StatelessWidget {
  final TaskModel task;
  final Function(String newStage, {bool openDoor})? onMoveStage;
  final VoidCallback? onDelete;

  const TaskPipelineCard({
    super.key,
    required this.task,
    this.onMoveStage,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Platform Badge + Title + Delete
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: task.platformColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(task.platformIcon, color: task.platformColor, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: task.platformColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: task.platformColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        task.platform.toUpperCase(),
                        style: TextStyle(
                          color: task.platformColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                UserUi.statusPill(
                  label: task.stageLabel,
                  color: task.stageColor,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Task Title
            Text(
              task.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Customer Info & Phone
            if (task.customerName != null && task.customerName!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                  const SizedBox(width: 6),
                  Text(
                    task.customerName!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                    ),
                  ),
                  if (task.customerPhone != null && task.customerPhone!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• ${task.customerPhone}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
            ],

            // Tracking ID & OTP if assigned
            if (task.trackingId != null && task.trackingId!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.tag_rounded, size: 14, color: UserTheme.primaryOrange),
                  const SizedBox(width: 6),
                  Text(
                    'Tracking: ${task.trackingId}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                    ),
                  ),
                  if (task.courierOtp != null && task.courierOtp!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'OTP: ${task.courierOtp}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Stage Transition Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: UserTheme.statusError, size: 20),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (task.stage == 'INQUIRY') ...[
                      ElevatedButton.icon(
                        onPressed: () => onMoveStage?.call('CRAFTING'),
                        icon: const Icon(Icons.palette_outlined, size: 16),
                        label: const Text('START CRAFTING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UserTheme.primaryOrange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                    if (task.stage == 'CRAFTING') ...[
                      ElevatedButton.icon(
                        onPressed: () => onMoveStage?.call('READY_FOR_BOX', openDoor: true),
                        icon: const Icon(Icons.lock_open_rounded, size: 16),
                        label: const Text('DEPOSIT IN DROPBOX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                    if (task.stage == 'READY_FOR_BOX') ...[
                      TextButton.icon(
                        onPressed: () async {
                          final text = "Hi ${task.customerName ?? 'Valued Customer'}! Your order #${task.trackingId ?? ''} is staged in our Smart Dropbox for pickup!";
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Customer receipt copied to clipboard!'), backgroundColor: UserTheme.statusSuccess),
                            );
                          }
                        },
                        icon: const Icon(Icons.share, size: 14),
                        label: const Text('SHARE PROOF', style: TextStyle(fontSize: 11)),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => onMoveStage?.call('SHIPPED'),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('MARK SHIPPED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: UserTheme.statusSuccess,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
