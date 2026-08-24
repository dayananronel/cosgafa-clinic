import '../models/models.dart';
import 'clinic_api.dart';
import 'exceptions.dart';
import 'id_generator.dart';

/// In-memory implementation of [ClinicApi] — the Phase 1 prototype
/// backend (spec section 19, "Build clickable/mock UI before backend
/// implementation"). All state lives in memory for the app session; see
/// docs/PHASE_2_BACKEND_SCOPE.md for [SupabaseClinicApi], the real
/// networked implementation of this same interface.
///
/// ASSUMPTION: no persistence, no real authentication. CONFIRMATION
/// REQUIRED before this is treated as production-ready.
class ClinicRepository extends ClinicApi {
  ClinicRepository({super.policy});

  int _queueNumberCounter = 0;
  DateTime? _queueNumberCounterDate;
  int _patientNumberCounter = 0;

  // ------------------------------------------------------------------
  // Seeding / configuration (not part of the ClinicApi contract — used
  // at startup by seed_data.dart for this demo backend only).
  // ------------------------------------------------------------------

  void seedPriorityCategories(List<PriorityCategory> categories) {
    priorityCategoriesList
      ..clear()
      ..addAll(categories);
  }

  void seedUsers(List<AppUser> users) {
    usersList
      ..clear()
      ..addAll(users);
  }

  void addPatientDirect(Patient patient) => patientsById[patient.id] = patient;

  // ------------------------------------------------------------------
  // Patient Service (spec 9.1)
  // ------------------------------------------------------------------

  @override
  Future<Patient> registerPatient({
    required String firstName,
    String middleName = '',
    required String lastName,
    required DateTime birthdate,
    required Sex sex,
    required String address,
    required String guardianName,
    required String guardianContact,
    required String actor,
  }) async {
    final now = DateTime.now();
    _patientNumberCounter++;
    final patient = Patient(
      id: IdGenerator.newId(),
      patientNumber: 'P${now.year}-${_patientNumberCounter.toString().padLeft(5, '0')}',
      firstName: firstName.trim(),
      middleName: middleName.trim(),
      lastName: lastName.trim(),
      birthdate: birthdate,
      sex: sex,
      address: address.trim(),
      guardianName: guardianName.trim(),
      guardianContact: guardianContact.trim(),
      createdAt: now,
      updatedAt: now,
      createdBy: actor,
      updatedBy: actor,
    );
    patientsById[patient.id] = patient;
    notifyListeners();
    return patient;
  }

  // ------------------------------------------------------------------
  // Queue Service (spec 9.3, 7, 16) — the core business logic.
  // ------------------------------------------------------------------

  int _nextQueueNumber() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!policy.queueNumberResetsDaily) {
      _queueNumberCounter++;
      return _queueNumberCounter;
    }
    if (_queueNumberCounterDate == null || _queueNumberCounterDate != today) {
      _queueNumberCounterDate = today;
      _queueNumberCounter = 0;
    }
    _queueNumberCounter++;
    return _queueNumberCounter;
  }

  void _logEvent({
    required String queueEntryId,
    required QueueEventType type,
    QueueStatus? oldStatus,
    QueueStatus? newStatus,
    String? oldPriority,
    String? newPriority,
    String? reason,
    required String performedBy,
    Map<String, dynamic> metadata = const {},
  }) {
    queueEventsList.add(QueueEvent(
      id: IdGenerator.newId(),
      queueEntryId: queueEntryId,
      eventType: type,
      oldStatus: oldStatus?.label,
      newStatus: newStatus?.label,
      oldPriority: oldPriority,
      newPriority: newPriority,
      reason: reason,
      performedBy: performedBy,
      createdAt: DateTime.now(),
      metadata: metadata,
    ));
  }

  @override
  Future<({Patient patient, Visit visit, QueueEntry queueEntry})> checkIn({
    Patient? existingPatient,
    Patient? newlyRegisteredPatient,
    required String reasonForVisit,
    required String actor,
  }) async {
    final patient = existingPatient ?? newlyRegisteredPatient;
    if (patient == null) {
      throw ArgumentError('A patient must be selected or registered before check-in.');
    }

    // Spec section 13 "Duplicate visit": prevent a second active visit for
    // the same patient on the same clinic day (e.g. accidental double
    // submission of the check-in button).
    final hasOpenVisitToday = visitsById.values.any((v) =>
        v.patientId == patient.id && isToday(v.visitDate) && v.status == VisitStatus.open);
    if (hasOpenVisitToday) {
      throw DuplicateOperationException(
        '${patient.fullName} already has an active visit today.',
      );
    }

    final now = DateTime.now();
    final visit = Visit(
      id: IdGenerator.newId(),
      patientId: patient.id,
      visitDate: now,
      reasonForVisit: reasonForVisit.trim(),
      status: VisitStatus.open,
      createdAt: now,
      updatedAt: now,
      createdBy: actor,
      updatedBy: actor,
    );
    visitsById[visit.id] = visit;

    if (newlyRegisteredPatient != null) {
      _logEvent(
        queueEntryId: '', // patient-level event, not yet tied to a queue entry
        type: QueueEventType.patientRegistered,
        performedBy: actor,
        metadata: {'patientId': patient.id},
      );
    }

    final normal = normalCategory;
    final entry = QueueEntry(
      id: IdGenerator.newId(),
      visitId: visit.id,
      queueNumber: _nextQueueNumber(),
      checkedInAt: now,
      priorityCategoryId: normal.id,
      priorityLevel: normal.priorityLevel,
      status: QueueStatus.waitingForIntake,
      createdAt: now,
      updatedAt: now,
    );
    queueEntriesById[entry.id] = entry;

    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.visitCreated,
      performedBy: actor,
      metadata: {'reasonForVisit': reasonForVisit},
    );
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.checkIn,
      newStatus: QueueStatus.checkedIn,
      performedBy: actor,
    );
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.queueCreated,
      oldStatus: QueueStatus.checkedIn,
      newStatus: QueueStatus.waitingForIntake,
      performedBy: actor,
      metadata: {'queueNumber': entry.queueNumber},
    );

    notifyListeners();
    return (patient: patient, visit: visit, queueEntry: entry);
  }

  static const _guestActor = 'Guest (self check-in)';

  @override
  Future<({Patient patient, Visit visit, QueueEntry queueEntry})> guestCheckIn({
    required String firstName,
    String middleName = '',
    required String lastName,
    required DateTime birthdate,
    required Sex sex,
    required String address,
    required String guardianName,
    required String guardianContact,
    required String reasonForVisit,
  }) async {
    final patient = await registerPatient(
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      birthdate: birthdate,
      sex: sex,
      address: address,
      guardianName: guardianName,
      guardianContact: guardianContact,
      actor: _guestActor,
    );
    return checkIn(newlyRegisteredPatient: patient, reasonForVisit: reasonForVisit, actor: _guestActor);
  }

  QueueEntry _requireEntry(String id) {
    final e = queueEntriesById[id];
    if (e == null) throw ArgumentError('Unknown queue entry: $id');
    return e;
  }

  void _requireStatus(QueueEntry entry, Set<QueueStatus> allowed, String action) {
    if (!allowed.contains(entry.status)) {
      throw InvalidQueueTransitionException(
        'Cannot $action while status is ${entry.status.label}.',
      );
    }
  }

  @override
  Future<QueueEntry> startIntake(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.waitingForIntake}, 'start intake');
    final updated = entry.copyWith(status: QueueStatus.inIntake);
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.intakeStarted,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> recordVitals(
    String queueEntryId, {
    double? weightKg,
    double? temperatureC,
    double? heightCm,
    double? oxygenSaturation,
    required String actor,
  }) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {QueueStatus.inIntake, QueueStatus.vitalsComplete},
      'record vitals',
    );

    vitalsByVisitId[entry.visitId] = Vitals(
      id: IdGenerator.newId(),
      visitId: entry.visitId,
      weightKg: weightKg,
      temperatureC: temperatureC,
      heightCm: heightCm,
      oxygenSaturation: oxygenSaturation,
      recordedAt: DateTime.now(),
      recordedBy: actor,
    );

    final updated = entry.status == QueueStatus.inIntake
        ? entry.copyWith(status: QueueStatus.vitalsComplete)
        : entry;
    queueEntriesById[entry.id] = updated;

    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.vitalsRecorded,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  /// Completes intake: assigns the administrative queue category and
  /// places the patient into the doctor's queue, or flags
  /// `NEEDS_DOCTOR_DECISION` when the secretary is uncertain (spec Step
  /// 8–10). Secretaries may never assign the doctor-only override
  /// category here (enforced below, not just hidden in the UI).
  @override
  Future<QueueEntry> completeIntake(
    String queueEntryId, {
    required String priorityCategoryId,
    bool needsDoctorDecision = false,
    String? reasonForVisitOverride,
    required String actor,
  }) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.vitalsComplete}, 'complete intake');

    final category = categoryById(priorityCategoryId);
    if (category.id == doctorOverrideCategory.id) {
      throw AuthorizationException(
        'Only a doctor may assign the doctor-priority category.',
      );
    }

    if (reasonForVisitOverride != null && reasonForVisitOverride.trim().isNotEmpty) {
      final visit = visitsById[entry.visitId]!;
      visitsById[visit.id] = visit.copyWith(
        reasonForVisit: reasonForVisitOverride.trim(),
        updatedAt: DateTime.now(),
        updatedBy: actor,
      );
    }

    final oldCategory = categoryById(entry.priorityCategoryId);
    final newStatus =
        needsDoctorDecision ? QueueStatus.needsDoctorDecision : QueueStatus.waitingForDoctor;

    final updated = entry.copyWith(
      priorityCategoryId: category.id,
      priorityLevel: category.priorityLevel,
      status: newStatus,
    );
    queueEntriesById[entry.id] = updated;

    if (oldCategory.id != category.id) {
      _logEvent(
        queueEntryId: entry.id,
        type: QueueEventType.priorityChanged,
        oldPriority: oldCategory.name,
        newPriority: category.name,
        performedBy: actor,
      );
    }
    _logEvent(
      queueEntryId: entry.id,
      type: needsDoctorDecision
          ? QueueEventType.needsDoctorDecision
          : QueueEventType.queueCreated,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> callPatient(String queueEntryId, {required String actor}) async {
    if (currentlyServingEntry != null && currentlyServingEntry!.id != queueEntryId) {
      throw InvalidQueueTransitionException(
        'A patient is already being served. Complete or skip that consultation first.',
      );
    }
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.waitingForDoctor}, 'call this patient');
    final updated = entry.copyWith(status: QueueStatus.called, calledAt: DateTime.now());
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.called,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> callNext({required String actor}) async {
    final next = nextPatientForDoctor;
    if (next == null) {
      throw InvalidQueueTransitionException('No patients are waiting for the doctor.');
    }
    return callPatient(next.id, actor: actor);
  }

  @override
  Future<QueueEntry> startConsultation(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.called}, 'start consultation');
    final updated = entry.copyWith(
      status: QueueStatus.inConsultation,
      consultationStartedAt: DateTime.now(),
    );
    queueEntriesById[entry.id] = updated;
    final visit = visitsById[entry.visitId]!;
    visitsById[visit.id] = visit.copyWith(
      status: VisitStatus.inConsultation,
      updatedAt: DateTime.now(),
      updatedBy: actor,
    );
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.consultationStarted,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> completeConsultation(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.inConsultation}, 'complete consultation');
    final now = DateTime.now();
    final updated = entry.copyWith(status: QueueStatus.completed, completedAt: now);
    queueEntriesById[entry.id] = updated;
    final visit = visitsById[entry.visitId]!;
    visitsById[visit.id] =
        visit.copyWith(status: VisitStatus.completed, updatedAt: now, updatedBy: actor);
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.completed,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> skip(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.called}, 'mark as skipped');
    final updated = entry.copyWith(status: QueueStatus.skipped, clearCalledAt: true);
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.skipped,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> requeue(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.skipped}, 'requeue this patient');
    // Per ClinicPolicy.requeueRetainsPriorityAndArrival: retaining keeps the
    // entry's original priority/check-in time (same relative position);
    // otherwise the patient is requeued as a fresh normal-priority arrival.
    final updated = policy.requeueRetainsPriorityAndArrival
        ? entry.copyWith(status: QueueStatus.waitingForDoctor)
        : QueueEntry(
            id: entry.id,
            visitId: entry.visitId,
            queueNumber: entry.queueNumber,
            checkedInAt: DateTime.now(),
            priorityCategoryId: normalCategory.id,
            priorityLevel: normalCategory.priorityLevel,
            status: QueueStatus.waitingForDoctor,
            createdAt: entry.createdAt,
            updatedAt: DateTime.now(),
          );
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.requeued,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
      metadata: {'retainedOriginalPosition': policy.requeueRetainsPriorityAndArrival},
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> markTemporarilyAway(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {QueueStatus.waitingForDoctor, QueueStatus.needsDoctorDecision, QueueStatus.waitingForIntake},
      'mark temporarily away',
    );
    final updated = entry.copyWith(status: QueueStatus.temporarilyAway);
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.temporarilyAway,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
      metadata: {'previousStatus': entry.status.name},
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> returnFromAway(String queueEntryId, {required String actor}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.temporarilyAway}, 'return from temporarily away');
    final events = eventsForQueueEntry(queueEntryId);
    final awayEvent = events.lastWhere((e) => e.eventType == QueueEventType.temporarilyAway);
    final previousStatusName = awayEvent.metadata['previousStatus'] as String?;
    final restoredStatus = QueueStatus.values.firstWhere(
      (s) => s.name == previousStatusName,
      orElse: () => QueueStatus.waitingForDoctor,
    );
    final updated = entry.copyWith(status: restoredStatus);
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.returned,
      oldStatus: entry.status,
      newStatus: updated.status,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  @override
  Future<QueueEntry> cancelQueueEntry(String queueEntryId, {required String actor, required String reason}) async {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {
        QueueStatus.waitingForIntake,
        QueueStatus.inIntake,
        QueueStatus.vitalsComplete,
        QueueStatus.waitingForDoctor,
        QueueStatus.needsDoctorDecision,
        QueueStatus.temporarilyAway,
      },
      'cancel this visit',
    );
    final updated = entry.copyWith(status: QueueStatus.cancelled);
    queueEntriesById[entry.id] = updated;
    final visit = visitsById[entry.visitId]!;
    visitsById[visit.id] = visit.copyWith(
      status: VisitStatus.cancelled,
      updatedAt: DateTime.now(),
      updatedBy: actor,
    );
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.cancelled,
      oldStatus: entry.status,
      newStatus: updated.status,
      reason: reason,
      performedBy: actor,
    );
    notifyListeners();
    return updated;
  }

  /// Doctor-authorized priority override (spec section 7.6, 11). Not a
  /// single silent button: a reason is always recorded, and this is the
  /// only path that can assign the doctor-priority category.
  @override
  Future<QueueEntry> doctorOverride(
    String queueEntryId, {
    required String reason,
    String? otherExplanation,
    required AppUser actor,
  }) async {
    if (actor.role != UserRole.doctor) {
      throw AuthorizationException('Only a doctor may issue a priority override.');
    }
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {QueueStatus.waitingForDoctor, QueueStatus.needsDoctorDecision},
      'override priority',
    );

    final oldCategory = categoryById(entry.priorityCategoryId);
    final newCategory = doctorOverrideCategory;
    final finalReason = reason == 'Other' && (otherExplanation?.trim().isNotEmpty ?? false)
        ? otherExplanation!.trim()
        : reason;

    final updated = entry.copyWith(
      priorityCategoryId: newCategory.id,
      priorityLevel: newCategory.priorityLevel,
      status: QueueStatus.waitingForDoctor,
    );
    queueEntriesById[entry.id] = updated;

    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.doctorOverride,
      oldStatus: entry.status,
      newStatus: updated.status,
      oldPriority: oldCategory.name,
      newPriority: newCategory.name,
      reason: finalReason,
      performedBy: actor.name,
    );
    notifyListeners();
    return updated;
  }

  /// Doctor keeping the current priority after review of a
  /// `NEEDS_DOCTOR_DECISION` entry — still an explicit, auditable
  /// decision (spec Step 9 / Scenario 6), just not an escalation.
  @override
  Future<QueueEntry> doctorKeepNormalPriority(String queueEntryId, {required AppUser actor}) async {
    if (actor.role != UserRole.doctor) {
      throw AuthorizationException('Only a doctor may resolve a priority decision.');
    }
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.needsDoctorDecision}, 'resolve priority decision');
    final updated = entry.copyWith(status: QueueStatus.waitingForDoctor);
    queueEntriesById[entry.id] = updated;
    _logEvent(
      queueEntryId: entry.id,
      type: QueueEventType.priorityChanged,
      oldStatus: entry.status,
      newStatus: updated.status,
      reason: 'Doctor reviewed and kept current priority',
      performedBy: actor.name,
    );
    notifyListeners();
    return updated;
  }
}
