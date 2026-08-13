import 'enums.dart';

/// Represents one clinic encounter for a patient (spec 9.2).
/// A patient can accumulate many visits over time; a visit never becomes
/// a duplicate patient record.
class Visit {
  final String id;
  final String patientId;
  final DateTime visitDate;
  final String reasonForVisit;
  final VisitStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;

  Visit({
    required this.id,
    required this.patientId,
    required this.visitDate,
    required this.reasonForVisit,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
  });

  Visit copyWith({
    String? reasonForVisit,
    VisitStatus? status,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return Visit(
      id: id,
      patientId: patientId,
      visitDate: visitDate,
      reasonForVisit: reasonForVisit ?? this.reasonForVisit,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
