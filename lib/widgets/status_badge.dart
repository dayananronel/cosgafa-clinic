import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/theme.dart';

Color colorForStatus(QueueStatus status) {
  switch (status) {
    case QueueStatus.checkedIn:
    case QueueStatus.waitingForIntake:
    case QueueStatus.inIntake:
    case QueueStatus.vitalsComplete:
      return QueueColors.waitingForIntake;
    case QueueStatus.needsDoctorDecision:
      return QueueColors.needsDecision;
    case QueueStatus.waitingForDoctor:
    case QueueStatus.called:
      return QueueColors.waitingForDoctor;
    case QueueStatus.inConsultation:
      return QueueColors.inConsultation;
    case QueueStatus.completed:
      return QueueColors.completed;
    case QueueStatus.skipped:
      return QueueColors.skipped;
    case QueueStatus.cancelled:
      return QueueColors.cancelled;
    case QueueStatus.temporarilyAway:
      return QueueColors.away;
    case QueueStatus.noShow:
      return QueueColors.skipped;
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.dense = false});

  final QueueStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = colorForStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 11 : 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.category, {super.key});

  final PriorityCategory category;

  @override
  Widget build(BuildContext context) {
    final isOverride = category.priorityLevel == 1;
    final color = isOverride ? QueueColors.doctorPriority : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOverride) Icon(Icons.priority_high, size: 14, color: color),
          if (isOverride) const SizedBox(width: 2),
          Text(
            category.name,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
