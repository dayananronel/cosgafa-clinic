import '../models/models.dart';

/// JSON <-> model mapping for the Supabase backend. Kept out of
/// lib/models/ deliberately — the domain models stay backend-agnostic
/// (spec Rule 1: don't introduce a new architecture without reason);
/// this file is the one place that knows about Postgres column names
/// and enum string encoding.

String _camelToScreamingSnake(String s) {
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final isUpper = c.toUpperCase() == c && c.toLowerCase() != c;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(c.toUpperCase());
  }
  return buffer.toString();
}

String enumToDb(Enum value) => _camelToScreamingSnake(value.name);

T enumFromDb<T extends Enum>(List<T> values, String dbValue) =>
    values.firstWhere((v) => enumToDb(v) == dbValue);

QueueStatus? queueStatusFromDbNullable(String? v) =>
    v == null ? null : enumFromDb(QueueStatus.values, v);

DateTime _dt(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _dtn(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
double? _numn(dynamic v) => v == null ? null : (v as num).toDouble();

Patient patientFromJson(Map<String, dynamic> j) => Patient(
      id: j['id'] as String,
      patientNumber: j['patient_number'] as String,
      firstName: j['first_name'] as String,
      middleName: (j['middle_name'] as String?) ?? '',
      lastName: j['last_name'] as String,
      birthdate: DateTime.parse(j['birthdate'] as String),
      sex: enumFromDb(Sex.values, j['sex'] as String),
      address: j['address'] as String,
      guardianName: j['guardian_name'] as String,
      guardianContact: j['guardian_contact'] as String,
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
      createdBy: (j['created_by'] as String?) ?? '',
      updatedBy: (j['updated_by'] as String?) ?? '',
    );

Visit visitFromJson(Map<String, dynamic> j) => Visit(
      id: j['id'] as String,
      patientId: j['patient_id'] as String,
      visitDate: DateTime.parse(j['visit_date'] as String),
      reasonForVisit: j['reason_for_visit'] as String,
      status: enumFromDb(VisitStatus.values, j['status'] as String),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
      createdBy: (j['created_by'] as String?) ?? '',
      updatedBy: (j['updated_by'] as String?) ?? '',
    );

QueueEntry queueEntryFromJson(Map<String, dynamic> j) => QueueEntry(
      id: j['id'] as String,
      visitId: j['visit_id'] as String,
      queueNumber: j['queue_number'] as int,
      checkedInAt: _dt(j['checked_in_at']),
      priorityCategoryId: j['priority_category_id'] as String,
      priorityLevel: j['priority_level'] as int,
      status: enumFromDb(QueueStatus.values, j['status'] as String),
      calledAt: _dtn(j['called_at']),
      consultationStartedAt: _dtn(j['consultation_started_at']),
      completedAt: _dtn(j['completed_at']),
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

Vitals vitalsFromJson(Map<String, dynamic> j) => Vitals(
      id: j['id'] as String,
      visitId: j['visit_id'] as String,
      weightKg: _numn(j['weight_kg']),
      temperatureC: _numn(j['temperature_c']),
      heightCm: _numn(j['height_cm']),
      oxygenSaturation: _numn(j['oxygen_saturation']),
      recordedAt: _dt(j['recorded_at']),
      recordedBy: (j['recorded_by'] as String?) ?? '',
    );

PriorityCategory priorityCategoryFromJson(Map<String, dynamic> j) => PriorityCategory(
      id: j['id'] as String,
      name: j['name'] as String,
      priorityLevel: j['priority_level'] as int,
      description: (j['description'] as String?) ?? '',
      isActive: (j['is_active'] as bool?) ?? true,
      createdAt: _dt(j['created_at']),
      updatedAt: _dt(j['updated_at']),
    );

QueueEvent queueEventFromJson(Map<String, dynamic> j) => QueueEvent(
      id: j['id'] as String,
      queueEntryId: (j['queue_entry_id'] as String?) ?? '',
      eventType: enumFromDb(QueueEventType.values, j['event_type'] as String),
      oldStatus: queueStatusFromDbNullable(j['old_status'] as String?)?.label,
      newStatus: queueStatusFromDbNullable(j['new_status'] as String?)?.label,
      oldPriority: j['old_priority'] as String?,
      newPriority: j['new_priority'] as String?,
      reason: j['reason'] as String?,
      // performed_by is null for Guest Mode events (0005_guest_check_in.sql
      // — there is no staff id to attribute an unauthenticated check-in to).
      performedBy: (j['performed_by'] as String?) ?? 'Guest (self check-in)',
      createdAt: _dt(j['created_at']),
      metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );

AppUser staffProfileFromJson(Map<String, dynamic> j) => AppUser(
      id: j['id'] as String,
      name: j['name'] as String,
      username: (j['email'] as String?) ?? j['id'] as String,
      role: enumFromDb(UserRole.values, j['role'] as String),
      isActive: (j['is_active'] as bool?) ?? true,
    );
