import 'enums.dart';

/// The patient's operational queue position for a single visit (spec 9.3).
/// Queue number identifies the visit's position for display purposes only
/// — the immutable [id] is the real identity, never the queue number.
class QueueEntry {
  final String id;
  final String visitId;
  final int queueNumber;
  final DateTime checkedInAt;
  final String priorityCategoryId;
  final int priorityLevel;
  final QueueStatus status;
  final DateTime? calledAt;
  final DateTime? consultationStartedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QueueEntry({
    required this.id,
    required this.visitId,
    required this.queueNumber,
    required this.checkedInAt,
    required this.priorityCategoryId,
    required this.priorityLevel,
    required this.status,
    this.calledAt,
    this.consultationStartedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  QueueEntry copyWith({
    String? priorityCategoryId,
    int? priorityLevel,
    QueueStatus? status,
    DateTime? calledAt,
    DateTime? consultationStartedAt,
    DateTime? completedAt,
    DateTime? updatedAt,
    bool clearCalledAt = false,
  }) {
    return QueueEntry(
      id: id,
      visitId: visitId,
      queueNumber: queueNumber,
      checkedInAt: checkedInAt,
      priorityCategoryId: priorityCategoryId ?? this.priorityCategoryId,
      priorityLevel: priorityLevel ?? this.priorityLevel,
      status: status ?? this.status,
      calledAt: clearCalledAt ? null : (calledAt ?? this.calledAt),
      consultationStartedAt: consultationStartedAt ?? this.consultationStartedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String get displayNumber => '#${queueNumber.toString().padLeft(3, '0')}';
}
