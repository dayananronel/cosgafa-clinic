import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'clinic_policy.dart';
import 'exceptions.dart';
import 'id_generator.dart';

/// In-memory simulation of the layered backend described in spec section
/// 22 (Patient Service / Visit Service / Queue Service over a database).
///
/// ASSUMPTION: this MVP prototype has no real network backend — all state
/// lives in memory for the app session, matching spec section 19 Phase 3
/// ("Build clickable/mock UI before backend implementation"). The method
/// boundaries below are deliberately kept as they would be on a real
/// server (validation, authorization, and audit logging all happen here,
/// never only in the UI) so a future real API can replace this class
/// without changing screen code. CONFIRMATION REQUIRED before this is
/// treated as production-ready: it does not persist data, authenticate
/// securely, or run on a trusted server.
class ClinicRepository extends ChangeNotifier {
  ClinicRepository({ClinicPolicy? policy}) : policy = policy ?? const ClinicPolicy();

  final ClinicPolicy policy;

  final Map<String, Patient> _patients = {};
  final Map<String, Visit> _visits = {};
  final Map<String, QueueEntry> _queueEntries = {};
  final Map<String, Vitals> _vitalsByVisit = {};
  final List<QueueEvent> _queueEvents = [];
  final List<PriorityCategory> _priorityCategories = [];
  final List<AppUser> _users = [];

  int _queueNumberCounter = 0;
  DateTime? _queueNumberCounterDate;
  int _patientNumberCounter = 0;

  // ------------------------------------------------------------------
  // Seeding / configuration (not part of the "API" — used at startup).
  // ------------------------------------------------------------------

  void seedPriorityCategories(List<PriorityCategory> categories) {
    _priorityCategories
      ..clear()
      ..addAll(categories);
  }

  void seedUsers(List<AppUser> users) {
    _users
      ..clear()
      ..addAll(users);
  }

  void addPatientDirect(Patient patient) => _patients[patient.id] = patient;

  // ------------------------------------------------------------------
  // Users (spec 9.6)
  // ------------------------------------------------------------------

  List<AppUser> get users => List.unmodifiable(_users);

  AppUser? findUserByUsername(String username) {
    for (final u in _users) {
      if (u.username.toLowerCase() == username.toLowerCase()) return u;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Priority categories (spec 9.5, 7.5)
  // ------------------------------------------------------------------

  List<PriorityCategory> get priorityCategories => List.unmodifiable(
        _priorityCategories.where((c) => c.isActive).toList()
          ..sort((a, b) => a.priorityLevel.compareTo(b.priorityLevel)),
      );

  PriorityCategory categoryById(String id) =>
      _priorityCategories.firstWhere((c) => c.id == id);

  /// The highest-priority category, reserved for doctor overrides (spec
  /// 7.5: "Priority 1 = Doctor/clinical override"). Secretaries are never
  /// authorized to assign this category directly (Scenario 9).
  PriorityCategory get doctorOverrideCategory =>
      _priorityCategories.reduce((a, b) => a.priorityLevel < b.priorityLevel ? a : b);

  /// The lowest-priority ("Normal") category, used as the default for
  /// ordinary walk-ins.
  PriorityCategory get normalCategory =>
      _priorityCategories.reduce((a, b) => a.priorityLevel > b.priorityLevel ? a : b);

  // ------------------------------------------------------------------
  // Patient Service (spec 9.1)
  // ------------------------------------------------------------------

  List<Patient> get patients => List.unmodifiable(_patients.values);

  Patient? getPatient(String id) => _patients[id];

  List<Patient> searchPatients(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _patients.values.where((p) {
      return p.fullName.toLowerCase().contains(q) ||
          p.patientNumber.toLowerCase().contains(q) ||
          p.guardianName.toLowerCase().contains(q) ||
          p.guardianContact.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.lastName.compareTo(b.lastName));
  }

  /// Spec section 13, "Duplicate patient": surface likely duplicates
  /// before a new record is created so the secretary can search first.
  List<Patient> findPotentialDuplicates({
    required String firstName,
    required String lastName,
    required DateTime birthdate,
  }) {
    return _patients.values.where((p) {
      final sameName = p.firstName.toLowerCase() == firstName.toLowerCase() &&
          p.lastName.toLowerCase() == lastName.toLowerCase();
      final sameBirthdate = p.birthdate.year == birthdate.year &&
          p.birthdate.month == birthdate.month &&
          p.birthdate.day == birthdate.day;
      return sameName && sameBirthdate;
    }).toList();
  }

  Patient registerPatient({
    required String firstName,
    String middleName = '',
    required String lastName,
    required DateTime birthdate,
    required Sex sex,
    required String address,
    required String guardianName,
    required String guardianContact,
    required String actor,
  }) {
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
    _patients[patient.id] = patient;
    notifyListeners();
    return patient;
  }

  // ------------------------------------------------------------------
  // Visit Service (spec 9.2)
  // ------------------------------------------------------------------

  Visit? getVisit(String id) => _visits[id];

  List<Visit> visitsForPatient(String patientId) =>
      _visits.values.where((v) => v.patientId == patientId).toList()
        ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

  // ------------------------------------------------------------------
  // Queue Service (spec 9.3, 7, 16) — the core business logic.
  // ------------------------------------------------------------------

  List<QueueEntry> get _allQueueEntries => _queueEntries.values.toList();

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  List<QueueEntry> get todayQueueEntries =>
      _allQueueEntries.where((e) => _isToday(e.checkedInAt)).toList();

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
    _queueEvents.add(QueueEvent(
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

  List<QueueEvent> eventsForQueueEntry(String queueEntryId) =>
      _queueEvents.where((e) => e.queueEntryId == queueEntryId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<QueueEvent> get todayEvents =>
      _queueEvents.where((e) => _isToday(e.createdAt)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Bundles the result of a check-in for the UI to navigate with.
  ({Patient patient, Visit visit, QueueEntry queueEntry}) checkIn({
    Patient? existingPatient,
    Patient? newlyRegisteredPatient,
    required String reasonForVisit,
    required String actor,
  }) {
    final patient = existingPatient ?? newlyRegisteredPatient;
    if (patient == null) {
      throw ArgumentError('A patient must be selected or registered before check-in.');
    }

    // Spec section 13 "Duplicate visit": prevent a second active visit for
    // the same patient on the same clinic day (e.g. accidental double
    // submission of the check-in button).
    final hasOpenVisitToday = _visits.values.any((v) =>
        v.patientId == patient.id && _isToday(v.visitDate) && v.status == VisitStatus.open);
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
    _visits[visit.id] = visit;

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
    _queueEntries[entry.id] = entry;

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

  QueueEntry _requireEntry(String id) {
    final e = _queueEntries[id];
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

  QueueEntry startIntake(String queueEntryId, {required String actor}) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.waitingForIntake}, 'start intake');
    final updated = entry.copyWith(status: QueueStatus.inIntake);
    _queueEntries[entry.id] = updated;
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

  QueueEntry recordVitals(
    String queueEntryId, {
    double? weightKg,
    double? temperatureC,
    double? heightCm,
    double? oxygenSaturation,
    required String actor,
  }) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {QueueStatus.inIntake, QueueStatus.vitalsComplete},
      'record vitals',
    );

    _vitalsByVisit[entry.visitId] = Vitals(
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
    _queueEntries[entry.id] = updated;

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

  Vitals? vitalsForVisit(String visitId) => _vitalsByVisit[visitId];

  /// Completes intake: assigns the administrative queue category and
  /// places the patient into the doctor's queue, or flags
  /// `NEEDS_DOCTOR_DECISION` when the secretary is uncertain (spec Step
  /// 8–10). Secretaries may never assign the doctor-only override
  /// category here (enforced below, not just hidden in the UI).
  QueueEntry completeIntake(
    String queueEntryId, {
    required String priorityCategoryId,
    bool needsDoctorDecision = false,
    String? reasonForVisitOverride,
    required String actor,
  }) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.vitalsComplete}, 'complete intake');

    final category = categoryById(priorityCategoryId);
    if (category.id == doctorOverrideCategory.id) {
      throw AuthorizationException(
        'Only a doctor may assign the doctor-priority category.',
      );
    }

    if (reasonForVisitOverride != null && reasonForVisitOverride.trim().isNotEmpty) {
      final visit = _visits[entry.visitId]!;
      _visits[visit.id] = visit.copyWith(
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
    _queueEntries[entry.id] = updated;

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

  /// Queue algorithm (spec section 16): eligible patients, sorted by
  /// active priority level then earliest check-in time. Doctor overrides
  /// are reflected simply because they change `priorityLevel`, so no
  /// separate override step is needed at read time.
  List<QueueEntry> get doctorQueueSorted {
    final list = todayQueueEntries
        .where((e) => e.status == QueueStatus.waitingForDoctor)
        .toList();
    list.sort((a, b) {
      final byPriority = a.priorityLevel.compareTo(b.priorityLevel);
      if (byPriority != 0) return byPriority;
      return a.checkedInAt.compareTo(b.checkedInAt);
    });
    return list;
  }

  List<QueueEntry> get needsDecisionQueue {
    final list = todayQueueEntries
        .where((e) => e.status == QueueStatus.needsDoctorDecision)
        .toList();
    list.sort((a, b) => a.checkedInAt.compareTo(b.checkedInAt));
    return list;
  }

  List<QueueEntry> get waitingForIntakeQueue {
    final list =
        todayQueueEntries.where((e) => e.status == QueueStatus.waitingForIntake).toList();
    list.sort((a, b) => a.checkedInAt.compareTo(b.checkedInAt));
    return list;
  }

  List<QueueEntry> get inIntakeQueue {
    final list = todayQueueEntries
        .where((e) => e.status == QueueStatus.inIntake || e.status == QueueStatus.vitalsComplete)
        .toList();
    list.sort((a, b) => a.checkedInAt.compareTo(b.checkedInAt));
    return list;
  }

  QueueEntry? get currentlyServingEntry {
    final active = todayQueueEntries.where(
      (e) => e.status == QueueStatus.called || e.status == QueueStatus.inConsultation,
    );
    return active.isEmpty ? null : active.first;
  }

  List<QueueEntry> get skippedQueue {
    final list = todayQueueEntries.where((e) => e.status == QueueStatus.skipped).toList();
    list.sort((a, b) => a.checkedInAt.compareTo(b.checkedInAt));
    return list;
  }

  List<QueueEntry> get temporarilyAwayQueue {
    final list =
        todayQueueEntries.where((e) => e.status == QueueStatus.temporarilyAway).toList();
    list.sort((a, b) => a.checkedInAt.compareTo(b.checkedInAt));
    return list;
  }

  List<QueueEntry> get completedTodayQueue {
    final list = todayQueueEntries.where((e) => e.status == QueueStatus.completed).toList();
    list.sort((a, b) => (b.completedAt ?? b.updatedAt).compareTo(a.completedAt ?? a.updatedAt));
    return list;
  }

  /// The next patient the doctor would see, per the deterministic
  /// algorithm in spec section 16. Does not include entries still needing
  /// a doctor decision — those require an explicit decision first.
  QueueEntry? get nextPatientForDoctor =>
      doctorQueueSorted.isEmpty ? null : doctorQueueSorted.first;

  QueueEntry callPatient(String queueEntryId, {required String actor}) {
    if (currentlyServingEntry != null && currentlyServingEntry!.id != queueEntryId) {
      throw InvalidQueueTransitionException(
        'A patient is already being served. Complete or skip that consultation first.',
      );
    }
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.waitingForDoctor}, 'call this patient');
    final updated = entry.copyWith(status: QueueStatus.called, calledAt: DateTime.now());
    _queueEntries[entry.id] = updated;
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

  QueueEntry callNext({required String actor}) {
    final next = nextPatientForDoctor;
    if (next == null) {
      throw InvalidQueueTransitionException('No patients are waiting for the doctor.');
    }
    return callPatient(next.id, actor: actor);
  }

  QueueEntry startConsultation(String queueEntryId, {required String actor}) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.called}, 'start consultation');
    final updated = entry.copyWith(
      status: QueueStatus.inConsultation,
      consultationStartedAt: DateTime.now(),
    );
    _queueEntries[entry.id] = updated;
    final visit = _visits[entry.visitId]!;
    _visits[visit.id] = visit.copyWith(
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

  QueueEntry completeConsultation(String queueEntryId, {required String actor}) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.inConsultation}, 'complete consultation');
    final now = DateTime.now();
    final updated = entry.copyWith(status: QueueStatus.completed, completedAt: now);
    _queueEntries[entry.id] = updated;
    final visit = _visits[entry.visitId]!;
    _visits[visit.id] =
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

  QueueEntry skip(String queueEntryId, {required String actor}) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.called}, 'mark as skipped');
    final updated = entry.copyWith(status: QueueStatus.skipped, clearCalledAt: true);
    _queueEntries[entry.id] = updated;
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

  QueueEntry requeue(String queueEntryId, {required String actor}) {
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
    _queueEntries[entry.id] = updated;
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

  QueueEntry markTemporarilyAway(String queueEntryId, {required String actor}) {
    final entry = _requireEntry(queueEntryId);
    _requireStatus(
      entry,
      {QueueStatus.waitingForDoctor, QueueStatus.needsDoctorDecision, QueueStatus.waitingForIntake},
      'mark temporarily away',
    );
    final updated = entry.copyWith(status: QueueStatus.temporarilyAway);
    _queueEntries[entry.id] = updated;
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

  QueueEntry returnFromAway(String queueEntryId, {required String actor}) {
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
    _queueEntries[entry.id] = updated;
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

  QueueEntry cancelQueueEntry(String queueEntryId, {required String actor, required String reason}) {
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
    _queueEntries[entry.id] = updated;
    final visit = _visits[entry.visitId]!;
    _visits[visit.id] = visit.copyWith(
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
  QueueEntry doctorOverride(
    String queueEntryId, {
    required String reason,
    String? otherExplanation,
    required AppUser actor,
  }) {
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
    _queueEntries[entry.id] = updated;

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
  QueueEntry doctorKeepNormalPriority(String queueEntryId, {required AppUser actor}) {
    if (actor.role != UserRole.doctor) {
      throw AuthorizationException('Only a doctor may resolve a priority decision.');
    }
    final entry = _requireEntry(queueEntryId);
    _requireStatus(entry, {QueueStatus.needsDoctorDecision}, 'resolve priority decision');
    final updated = entry.copyWith(status: QueueStatus.waitingForDoctor);
    _queueEntries[entry.id] = updated;
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

  // ------------------------------------------------------------------
  // Joins / read helpers for the UI layer.
  // ------------------------------------------------------------------

  Patient patientForQueueEntry(QueueEntry entry) {
    final visit = _visits[entry.visitId]!;
    return _patients[visit.patientId]!;
  }

  Visit visitForQueueEntry(QueueEntry entry) => _visits[entry.visitId]!;

  int get countWaitingForIntake => waitingForIntakeQueue.length + inIntakeQueue.length;
  int get countWaitingForDoctor => doctorQueueSorted.length;
  int get countNeedsDoctorDecision => needsDecisionQueue.length;
  int get countInConsultation =>
      todayQueueEntries.where((e) => e.status == QueueStatus.inConsultation).length;
  int get countCompleted => completedTodayQueue.length;
}
