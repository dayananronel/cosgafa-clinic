import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'clinic_api.dart';
import 'exceptions.dart';
import 'supabase_codec.dart';

/// Real, networked implementation of [ClinicApi] — Phase 2. Backed by
/// the Postgres schema and RPC functions in supabase/migrations/. See
/// docs/PHASE_2_BACKEND_SCOPE.md for the design this implements.
///
/// Reads: an initial fetch populates the [ClinicDataCache] maps this
/// class inherits, then Supabase Realtime keeps them in sync — every
/// device (secretary tablet, doctor tablet, public display) converges
/// on the same state without polling, and every getter from
/// [ClinicDataCache] (`doctorQueueSorted`, `todayQueueEntries`, ...)
/// keeps working exactly as it does for the in-memory demo backend.
///
/// Writes: each method below calls a single Postgres RPC function that
/// performs the equivalent transition + audit-log insert in one
/// transaction — the write itself is a thin network call; Realtime
/// delivers the resulting row change back into the cache (this class
/// also applies the RPC's own return value immediately, so the caller
/// doesn't have to wait for the Realtime round trip to see its own
/// write reflected). Errors raised by the database (prefixed `AUTHZ:`,
/// `INVALID_TRANSITION:`, `DUPLICATE:` — see 0003_functions.sql) are
/// translated back into the same typed exceptions
/// (`AuthorizationException`, etc.) the demo backend throws, so
/// screens' existing catch blocks work unchanged.
class SupabaseClinicApi extends ClinicApi {
  SupabaseClinicApi(this._client, {super.policy});

  final SupabaseClient _client;
  final List<RealtimeChannel> _channels = [];
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await Future.wait([
      _loadTable('priority_categories', (rows) {
        priorityCategoriesList
          ..clear()
          ..addAll(rows.map(priorityCategoryFromJson));
      }),
      _loadTable('staff_profiles', (rows) {
        usersList
          ..clear()
          ..addAll(rows.map(staffProfileFromJson));
      }),
      _loadTable('patients', (rows) {
        patientsById
          ..clear()
          ..addEntries(rows.map(patientFromJson).map((p) => MapEntry(p.id, p)));
      }),
      _loadTable('visits', (rows) {
        visitsById
          ..clear()
          ..addEntries(rows.map(visitFromJson).map((v) => MapEntry(v.id, v)));
      }),
      _loadTable('queue_entries', (rows) {
        queueEntriesById
          ..clear()
          ..addEntries(rows.map(queueEntryFromJson).map((e) => MapEntry(e.id, e)));
      }),
      _loadTable('vitals', (rows) {
        vitalsByVisitId.clear();
        for (final row in rows) {
          final v = vitalsFromJson(row);
          // Keep the most recently recorded vitals per visit, matching
          // the demo backend's "one current vitals row per visit" model.
          final existing = vitalsByVisitId[v.visitId];
          if (existing == null || v.recordedAt.isAfter(existing.recordedAt)) {
            vitalsByVisitId[v.visitId] = v;
          }
        }
      }),
      _loadTable('queue_events', (rows) {
        queueEventsList
          ..clear()
          ..addAll(rows.map(queueEventFromJson));
      }),
    ]);

    _subscribeRealtime();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadTable(String table, void Function(List<Map<String, dynamic>> rows) apply) async {
    final rows = await _client.from(table).select();
    apply(List<Map<String, dynamic>>.from(rows as List));
  }

  void _subscribeRealtime() {
    _channels.add(
      _client.channel('public:clinic-sync')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patients',
          callback: (payload) => _applyChange(payload, patientsById, patientFromJson, (p) => p.id),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'visits',
          callback: (payload) => _applyChange(payload, visitsById, visitFromJson, (v) => v.id),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'queue_entries',
          callback: (payload) => _applyChange(payload, queueEntriesById, queueEntryFromJson, (e) => e.id),
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vitals',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            final v = vitalsFromJson(payload.newRecord);
            final existing = vitalsByVisitId[v.visitId];
            if (existing == null || v.recordedAt.isAfter(existing.recordedAt)) {
              vitalsByVisitId[v.visitId] = v;
              notifyListeners();
            }
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'queue_events',
          callback: (payload) {
            queueEventsList.add(queueEventFromJson(payload.newRecord));
            notifyListeners();
          },
        )
        ..subscribe(),
    );
  }

  void _applyChange<T>(
    PostgresChangePayload payload,
    Map<String, T> cache,
    T Function(Map<String, dynamic>) fromJson,
    String Function(T) idOf,
  ) {
    if (payload.eventType == PostgresChangeEvent.delete) {
      final oldId = payload.oldRecord['id'] as String?;
      if (oldId != null) cache.remove(oldId);
    } else {
      final item = fromJson(payload.newRecord);
      cache[idOf(item)] = item;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final channel in _channels) {
      _client.removeChannel(channel);
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // RPC helpers + error translation
  // ------------------------------------------------------------------

  Never _translateAndRethrow(Object error) {
    if (error is PostgrestException) {
      final message = error.message;
      if (message.startsWith('AUTHZ:')) {
        throw AuthorizationException(message.substring('AUTHZ:'.length).trim());
      }
      if (message.startsWith('INVALID_TRANSITION:')) {
        throw InvalidQueueTransitionException(message.substring('INVALID_TRANSITION:'.length).trim());
      }
      if (message.startsWith('DUPLICATE:')) {
        throw DuplicateOperationException(message.substring('DUPLICATE:'.length).trim());
      }
    }
    // ignore: only_throw_errors
    throw error;
  }

  Future<Map<String, dynamic>> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      final result = await _client.rpc(fn, params: params);
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      _translateAndRethrow(e);
    }
  }

  Future<QueueEntry> _rpcQueueEntry(String fn, Map<String, dynamic> params) async {
    final json = await _rpc(fn, params);
    final entry = queueEntryFromJson(json);
    queueEntriesById[entry.id] = entry;
    notifyListeners();
    return entry;
  }

  Future<Visit> _fetchVisit(String visitId) async {
    final row = await _client.from('visits').select().eq('id', visitId).single();
    final visit = visitFromJson(row);
    visitsById[visit.id] = visit;
    return visit;
  }

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
    final json = await _rpc('register_patient', {
      'p_first_name': firstName,
      'p_middle_name': middleName,
      'p_last_name': lastName,
      'p_birthdate': birthdate.toIso8601String().split('T').first,
      'p_sex': enumToDb(sex),
      'p_address': address,
      'p_guardian_name': guardianName,
      'p_guardian_contact': guardianContact,
    });
    final patient = patientFromJson(json);
    patientsById[patient.id] = patient;
    notifyListeners();
    return patient;
  }

  // ------------------------------------------------------------------
  // Queue Service (spec 9.3, 7, 16)
  // ------------------------------------------------------------------

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
    final json = await _rpc('check_in', {
      'p_patient_id': patient.id,
      'p_reason_for_visit': reasonForVisit,
      'p_newly_registered': newlyRegisteredPatient != null,
    });
    final entry = queueEntryFromJson(json);
    queueEntriesById[entry.id] = entry;
    notifyListeners();
    final visit = visitsById[entry.visitId] ?? await _fetchVisit(entry.visitId);
    return (patient: patient, visit: visit, queueEntry: entry);
  }

  @override
  Future<QueueEntry> startIntake(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('start_intake', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> recordVitals(
    String queueEntryId, {
    double? weightKg,
    double? temperatureC,
    double? heightCm,
    double? oxygenSaturation,
    required String actor,
  }) =>
      _rpcQueueEntry('record_vitals', {
        'p_queue_entry_id': queueEntryId,
        'p_weight_kg': weightKg,
        'p_temperature_c': temperatureC,
        'p_height_cm': heightCm,
        'p_oxygen_saturation': oxygenSaturation,
      });

  @override
  Future<QueueEntry> completeIntake(
    String queueEntryId, {
    required String priorityCategoryId,
    bool needsDoctorDecision = false,
    String? reasonForVisitOverride,
    required String actor,
  }) =>
      _rpcQueueEntry('complete_intake', {
        'p_queue_entry_id': queueEntryId,
        'p_priority_category_id': priorityCategoryId,
        'p_needs_doctor_decision': needsDoctorDecision,
        'p_reason_for_visit_override': reasonForVisitOverride,
      });

  @override
  Future<QueueEntry> callPatient(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('call_patient', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> callNext({required String actor}) => _rpcQueueEntry('call_next', {});

  @override
  Future<QueueEntry> startConsultation(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('start_consultation', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> completeConsultation(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('complete_consultation', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> skip(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('skip_patient', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> requeue(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('requeue_patient', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> markTemporarilyAway(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('mark_temporarily_away', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> returnFromAway(String queueEntryId, {required String actor}) =>
      _rpcQueueEntry('return_from_away', {'p_queue_entry_id': queueEntryId});

  @override
  Future<QueueEntry> cancelQueueEntry(String queueEntryId, {required String actor, required String reason}) =>
      _rpcQueueEntry('cancel_queue_entry', {'p_queue_entry_id': queueEntryId, 'p_reason': reason});

  @override
  Future<QueueEntry> doctorOverride(
    String queueEntryId, {
    required String reason,
    String? otherExplanation,
    required AppUser actor,
  }) =>
      _rpcQueueEntry('doctor_override', {
        'p_queue_entry_id': queueEntryId,
        'p_reason': reason,
        'p_other_explanation': otherExplanation,
      });

  @override
  Future<QueueEntry> doctorKeepNormalPriority(String queueEntryId, {required AppUser actor}) =>
      _rpcQueueEntry('doctor_keep_normal_priority', {'p_queue_entry_id': queueEntryId});
}
