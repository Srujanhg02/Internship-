import 'package:flutter/material.dart';
import '../config/theme.dart';

class StatusBadge extends StatelessWidget {
  final bool synced;

  const StatusBadge({super.key, required this.synced});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: synced
            ? AppTheme.successColor.withValues(alpha: 0.15)
            : AppTheme.warningColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: synced
              ? AppTheme.successColor.withValues(alpha: 0.4)
              : AppTheme.warningColor.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            synced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
            size: 14,
            color: synced ? AppTheme.successColor : AppTheme.warningColor,
          ),
          const SizedBox(width: 4),
          Text(
            synced ? 'Synced' : 'Pending',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: synced ? AppTheme.successColor : AppTheme.warningColor,
            ),
          ),
        ],
      ),
    );
  }
}
