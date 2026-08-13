import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'clinic_policy.dart';

/// The service-layer contract every screen depends on (via `Provider`),
/// independent of where the data actually lives.
///
/// [ClinicRepository] (in-memory, Phase 1 prototype) and
/// [SupabaseClinicApi] (Phase 2, a real Postgres/Supabase backend) both
/// extend this class. All the *read* logic — queue ordering, status
/// filters, joins — lives once, here, via [ClinicDataCache], so the two
/// backends can never disagree about what "next patient" or "waiting for
/// doctor" means. Only the *write* operations below are backend-specific
/// (an in-memory mutation vs. a network call to a Postgres function),
/// which is exactly the seam described in
/// docs/PHASE_2_BACKEND_SCOPE.md section 7.
///
/// Every write returns a `Future` — even [ClinicRepository]'s in-memory
/// version, which resolves immediately — so screens await one consistent
/// contract regardless of backend rather than the interface silently
/// lying about a real network call being synchronous.
abstract class ClinicApi extends ChangeNotifier with ClinicDataCache {
  ClinicApi({ClinicPolicy? policy}) {
    this.policy = policy ?? const ClinicPolicy();
  }

  // ------------------------------------------------------------------
  // Patient Service (spec 9.1)
  // ------------------------------------------------------------------

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
  });

  // ------------------------------------------------------------------
  // Queue Service (spec 9.3, 7, 16) — the core business logic.
  // ------------------------------------------------------------------

  /// Bundles the result of a check-in for the UI to navigate with.
  Future<({Patient patient, Visit visit, QueueEntry queueEntry})> checkIn({
    Patient? existingPatient,
    Patient? newlyRegisteredPatient,
    required String reasonForVisit,
    required String actor,
  });

  Future<QueueEntry> startIntake(String queueEntryId, {required String actor});

  Future<QueueEntry> recordVitals(
    String queueEntryId, {
    double? weightKg,
    double? temperatureC,
    double? heightCm,
    double? oxygenSaturation,
    required String actor,
  });

  Future<QueueEntry> completeIntake(
    String queueEntryId, {
    required String priorityCategoryId,
    bool needsDoctorDecision = false,
    String? reasonForVisitOverride,
    required String actor,
  });

  Future<QueueEntry> callPatient(String queueEntryId, {required String actor});

  Future<QueueEntry> callNext({required String actor});

  Future<QueueEntry> startConsultation(String queueEntryId, {required String actor});

  Future<QueueEntry> completeConsultation(String queueEntryId, {required String actor});

  Future<QueueEntry> skip(String queueEntryId, {required String actor});

  Future<QueueEntry> requeue(String queueEntryId, {required String actor});

  Future<QueueEntry> markTemporarilyAway(String queueEntryId, {required String actor});

  Future<QueueEntry> returnFromAway(String queueEntryId, {required String actor});

  Future<QueueEntry> cancelQueueEntry(String queueEntryId, {required String actor, required String reason});

  /// Doctor-authorized priority override (spec section 7.6, 11).
  Future<QueueEntry> doctorOverride(
    String queueEntryId, {
    required String reason,
    String? otherExplanation,
    required AppUser actor,
  });

  Future<QueueEntry> doctorKeepNormalPriority(String queueEntryId, {required AppUser actor});
}

/// Read-only cache + derived queries shared by every [ClinicApi]
/// implementation. Subclasses populate the maps/lists below (directly for
/// an in-memory backend, or from initial fetch + Realtime events for a
/// networked one) and call `notifyListeners()` after each change; every
/// getter here is then a pure function of that cache.
mixin ClinicDataCache on ChangeNotifier {
  late ClinicPolicy policy;

  @protected
  final Map<String, Patient> patientsById = {};
  @protected
  final Map<String, Visit> visitsById = {};
  @protected
  final Map<String, QueueEntry> queueEntriesById = {};
  @protected
  final Map<String, Vitals> vitalsByVisitId = {};
  @protected
  final List<QueueEvent> queueEventsList = [];
  @protected
  final List<PriorityCategory> priorityCategoriesList = [];
  @protected
  final List<AppUser> usersList = [];

  bool isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // ---- Users (spec 9.6) ----

  List<AppUser> get users => List.unmodifiable(usersList);

  AppUser? findUserByUsername(String username) {
    for (final u in usersList) {
      if (u.username.toLowerCase() == username.toLowerCase()) return u;
    }
    return null;
  }

  // ---- Priority categories (spec 9.5, 7.5) ----

  List<PriorityCategory> get priorityCategories => List.unmodifiable(
        priorityCategoriesList.where((c) => c.isActive).toList()
          ..sort((a, b) => a.priorityLevel.compareTo(b.priorityLevel)),
      );

  PriorityCategory categoryById(String id) =>
      priorityCategoriesList.firstWhere((c) => c.id == id);

  /// The highest-priority category, reserved for doctor overrides (spec
  /// 7.5: "Priority 1 = Doctor/clinical override"). Secretaries are never
  /// authorized to assign this category directly (Scenario 9).
  PriorityCategory get doctorOverrideCategory =>
      priorityCategoriesList.reduce((a, b) => a.priorityLevel < b.priorityLevel ? a : b);

  /// The lowest-priority ("Normal") category, used as the default for
  /// ordinary walk-ins.
  PriorityCategory get normalCategory =>
      priorityCategoriesList.reduce((a, b) => a.priorityLevel > b.priorityLevel ? a : b);

  // ---- Patient Service (spec 9.1) ----

  List<Patient> get patients => List.unmodifiable(patientsById.values);

  Patient? getPatient(String id) => patientsById[id];

  List<Patient> searchPatients(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return patientsById.values.where((p) {
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
    return patientsById.values.where((p) {
      final sameName = p.firstName.toLowerCase() == firstName.toLowerCase() &&
          p.lastName.toLowerCase() == lastName.toLowerCase();
      final sameBirthdate = p.birthdate.year == birthdate.year &&
          p.birthdate.month == birthdate.month &&
          p.birthdate.day == birthdate.day;
      return sameName && sameBirthdate;
    }).toList();
  }

  // ---- Visit Service (spec 9.2) ----

  Visit? getVisit(String id) => visitsById[id];

  List<Visit> visitsForPatient(String patientId) =>
      visitsById.values.where((v) => v.patientId == patientId).toList()
        ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

  // ---- Queue Service (spec 9.3, 7, 16) ----

  List<QueueEntry> get _allQueueEntries => queueEntriesById.values.toList();

  List<QueueEntry> get todayQueueEntries =>
      _allQueueEntries.where((e) => isToday(e.checkedInAt)).toList();

  List<QueueEvent> eventsForQueueEntry(String queueEntryId) =>
      queueEventsList.where((e) => e.queueEntryId == queueEntryId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<QueueEvent> get todayEvents =>
      queueEventsList.where((e) => isToday(e.createdAt)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Queue algorithm (spec section 16): eligible patients, sorted by
  /// active priority level then earliest check-in time. Doctor overrides
  /// are reflected simply because they change `priorityLevel`, so no
  /// separate override step is needed at read time.
  List<QueueEntry> get doctorQueueSorted {
    final list =
        todayQueueEntries.where((e) => e.status == QueueStatus.waitingForDoctor).toList();
    list.sort((a, b) {
      final byPriority = a.priorityLevel.compareTo(b.priorityLevel);
      if (byPriority != 0) return byPriority;
      return a.checkedInAt.compareTo(b.checkedInAt);
    });
    return list;
  }

  List<QueueEntry> get needsDecisionQueue {
    final list =
        todayQueueEntries.where((e) => e.status == QueueStatus.needsDoctorDecision).toList();
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

  Vitals? vitalsForVisit(String visitId) => vitalsByVisitId[visitId];

  // ---- Joins / read helpers for the UI layer ----

  Patient patientForQueueEntry(QueueEntry entry) {
    final visit = visitsById[entry.visitId]!;
    return patientsById[visit.patientId]!;
  }

  Visit visitForQueueEntry(QueueEntry entry) => visitsById[entry.visitId]!;

  int get countWaitingForIntake => waitingForIntakeQueue.length + inIntakeQueue.length;
  int get countWaitingForDoctor => doctorQueueSorted.length;
  int get countNeedsDoctorDecision => needsDecisionQueue.length;
  int get countInConsultation =>
      todayQueueEntries.where((e) => e.status == QueueStatus.inConsultation).length;
  int get countCompleted => completedTodayQueue.length;
}
