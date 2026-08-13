import 'enums.dart';

/// Immutable audit record of a queue-entry change (spec 9.7, section 17).
/// Queue history must never be silently overwritten — every meaningful
/// change is appended as a new event, never edited or deleted.
class QueueEvent {
  final String id;
  final String queueEntryId;
  final QueueEventType eventType;
  final String? oldStatus;
  final String? newStatus;
  final String? oldPriority;
  final String? newPriority;
  final String? reason;
  final String performedBy;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const QueueEvent({
    required this.id,
    required this.queueEntryId,
    required this.eventType,
    this.oldStatus,
    this.newStatus,
    this.oldPriority,
    this.newPriority,
    this.reason,
    required this.performedBy,
    required this.createdAt,
    this.metadata = const {},
  });
}
