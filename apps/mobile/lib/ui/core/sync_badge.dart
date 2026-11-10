import 'package:flutter/material.dart';

import 'app_theme.dart';

class SyncBadge extends StatelessWidget {
  const SyncBadge({
    required this.pendingCount,
    this.deadLetterCount = 0,
    this.error,
    super.key,
  });

  final int pendingCount;
  final int deadLetterCount;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasFailure = deadLetterCount > 0 || error != null;
    final hasPending = pendingCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (hasFailure ? Colors.redAccent : appLime).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: hasFailure ? Colors.redAccent : appLime),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFailure
                ? Icons.error_outline_rounded
                : hasPending
                ? Icons.sync_problem_rounded
                : Icons.cloud_done_rounded,
            size: 16,
            color: hasFailure ? Colors.redAccent : appLime,
          ),
          const SizedBox(width: 6),
          Text(
            hasFailure
                ? deadLetterCount > 0
                      ? '$deadLetterCount rechazo(s) por revisar'
                      : 'Problema de sincronización'
                : hasPending
                ? '$pendingCount pendiente(s)'
                : 'Sincronizado',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
