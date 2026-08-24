import 'package:flutter_test/flutter_test.dart';

import 'package:cosgafa_clinic/models/models.dart';
import 'package:cosgafa_clinic/services/clinic_repository.dart';
import 'package:cosgafa_clinic/services/exceptions.dart';

ClinicRepository _repoWithCategories() {
  final repo = ClinicRepository();
  final now = DateTime.now();
  repo.seedPriorityCategories([
    PriorityCategory(id: 'doctor', name: 'Doctor Priority', priorityLevel: 1, createdAt: now, updatedAt: now),
    PriorityCategory(id: 'special', name: 'Special Assistance', priorityLevel: 2, createdAt: now, updatedAt: now),
    PriorityCategory(id: 'followup', name: 'Follow-up', priorityLevel: 3, createdAt: now, updatedAt: now),
    PriorityCategory(id: 'normal', name: 'Normal', priorityLevel: 4, createdAt: now, updatedAt: now),
  ]);
  return repo;
}

Future<Patient> _register(ClinicRepository repo, String first) {
  return repo.registerPatient(
    firstName: first,
    lastName: 'Test',
    birthdate: DateTime(2023, 1, 1),
    sex: Sex.male,
    address: 'Addr',
    guardianName: 'Guardian',
    guardianContact: '0900000000',
    actor: 'test',
  );
}

void main() {
  group('Scenario 1 — New patient full flow', () {
    test('walks check-in through consultation completion', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Ana');
      final result = await repo.checkIn(newlyRegisteredPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');

      var entry = await repo.startIntake(result.queueEntry.id, actor: 'secretary');
      expect(entry.status, QueueStatus.inIntake);

      entry = await repo.recordVitals(entry.id, weightKg: 10, temperatureC: 37.5, actor: 'secretary');
      expect(entry.status, QueueStatus.vitalsComplete);

      entry = await repo.completeIntake(entry.id, priorityCategoryId: 'normal', actor: 'secretary');
      expect(entry.status, QueueStatus.waitingForDoctor);

      entry = await repo.callPatient(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.called);

      entry = await repo.startConsultation(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.inConsultation);

      entry = await repo.completeConsultation(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.completed);
      expect(repo.getVisit(result.visit.id)!.status, VisitStatus.completed);
    });
  });

  group('Scenario 2 — Existing patient, no duplicate record', () {
    test('reuses the existing patient id across visits', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Renzo');
      expect(repo.patients.length, 1);

      await repo.checkIn(existingPatient: patient, reasonForVisit: 'Follow-up', actor: 'secretary');
      expect(repo.patients.length, 1);
      expect(repo.visitsForPatient(patient.id).length, 1);
    });
  });

  group('Scenario 3 & 4 — Arrival order', () {
    test('same-priority patients are ordered strictly by check-in time', () async {
      final repo = _repoWithCategories();
      final a = await _register(repo, 'A');
      final b = await _register(repo, 'B');
      final c = await _register(repo, 'C');

      for (final p in [a, b, c]) {
        final r = await repo.checkIn(existingPatient: p, reasonForVisit: 'Checkup', actor: 'secretary');
        await repo.startIntake(r.queueEntry.id, actor: 'secretary');
        await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
        await repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');
      }

      final order = repo.doctorQueueSorted.map((e) => repo.patientForQueueEntry(e).firstName).toList();
      expect(order, ['A', 'B', 'C']);
    });
  });

  group('Scenario 5 — Doctor override', () {
    test('prioritized patient moves to the front and the change is audited', () async {
      final repo = _repoWithCategories();
      final a = await _register(repo, 'A');
      final b = await _register(repo, 'B');
      final c = await _register(repo, 'C');
      final entries = <QueueEntry>[];
      for (final p in [a, b, c]) {
        final r = await repo.checkIn(existingPatient: p, reasonForVisit: 'Checkup', actor: 'secretary');
        await repo.startIntake(r.queueEntry.id, actor: 'secretary');
        await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
        entries.add(await repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary'));
      }

      final doctorUser = AppUser(id: 'd1', name: 'Dr. Test', username: 'doctor', role: UserRole.doctor);
      await repo.doctorOverride(entries[2].id, reason: 'Clinical concern', actor: doctorUser);

      final order = repo.doctorQueueSorted.map((e) => repo.patientForQueueEntry(e).firstName).toList();
      expect(order.first, 'C');

      final events = repo.eventsForQueueEntry(entries[2].id);
      final overrideEvent = events.firstWhere((e) => e.eventType == QueueEventType.doctorOverride);
      expect(overrideEvent.performedBy, 'Dr. Test');
      expect(overrideEvent.reason, 'Clinical concern');
      expect(overrideEvent.oldPriority, isNotNull);
      expect(overrideEvent.newPriority, 'Doctor Priority');
    });
  });

  group('Scenario 6 — Secretary uncertain', () {
    test('flags NEEDS_DOCTOR_DECISION and the doctor resolves it', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Ella');
      final r = await repo.checkIn(existingPatient: patient, reasonForVisit: 'Unclear', actor: 'secretary');
      await repo.startIntake(r.queueEntry.id, actor: 'secretary');
      await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      final entry = await repo.completeIntake(
        r.queueEntry.id,
        priorityCategoryId: 'normal',
        needsDoctorDecision: true,
        actor: 'secretary',
      );
      expect(entry.status, QueueStatus.needsDoctorDecision);
      expect(repo.needsDecisionQueue, contains(entry));

      final doctorUser = AppUser(id: 'd1', name: 'Dr. Test', username: 'doctor', role: UserRole.doctor);
      final resolved = await repo.doctorKeepNormalPriority(entry.id, actor: doctorUser);
      expect(resolved.status, QueueStatus.waitingForDoctor);
    });
  });

  group('Scenario 7 — Skip and requeue', () {
    test('a called patient who does not respond can be requeued', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Miguel');
      final r = await repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      await repo.startIntake(r.queueEntry.id, actor: 'secretary');
      await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      var entry = await repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');
      entry = await repo.callPatient(entry.id, actor: 'doctor');
      entry = await repo.skip(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.skipped);

      entry = await repo.requeue(entry.id, actor: 'secretary');
      expect(entry.status, QueueStatus.waitingForDoctor);
    });
  });

  group('Scenario 9 — Unauthorized priority change', () {
    test('secretary cannot issue a doctor override', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Sofia');
      final r = await repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      await repo.startIntake(r.queueEntry.id, actor: 'secretary');
      await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      final entry = await repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');

      final secretaryUser = AppUser(id: 's1', name: 'Secretary Test', username: 'secretary', role: UserRole.secretary);
      await expectLater(
        repo.doctorOverride(entry.id, reason: 'Doctor decision', actor: secretaryUser),
        throwsA(isA<AuthorizationException>()),
      );
    });

    test('secretary cannot assign the doctor-priority category during intake', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Miguel');
      final r = await repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      await repo.startIntake(r.queueEntry.id, actor: 'secretary');
      await repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      await expectLater(
        repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'doctor', actor: 'secretary'),
        throwsA(isA<AuthorizationException>()),
      );
    });
  });

  group('Duplicate prevention', () {
    test('checking in the same patient twice in one day throws', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Ana');
      await repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');
      await expectLater(
        repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever again', actor: 'secretary'),
        throwsA(isA<DuplicateOperationException>()),
      );
    });
  });

  group('Guest Mode', () {
    test('self check-in registers a new patient and enters the queue waiting for intake', () async {
      final repo = _repoWithCategories();
      final result = await repo.guestCheckIn(
        firstName: 'Guest',
        lastName: 'Walkin',
        birthdate: DateTime(2024, 3, 1),
        sex: Sex.female,
        address: 'Addr',
        guardianName: 'Guardian',
        guardianContact: '0900000000',
        reasonForVisit: 'Fever',
      );

      expect(result.patient.fullName, contains('Guest'));
      expect(result.queueEntry.status, QueueStatus.waitingForIntake);
      expect(repo.getPatient(result.patient.id), isNotNull);
      // No staff was signed in to perform this -- confirms it doesn't
      // silently require/assume an authenticated actor.
      expect(result.patient.createdBy, isNot(isEmpty));
    });

    test('two separate guest submissions each get their own patient and queue number', () async {
      final repo = _repoWithCategories();
      final first = await repo.guestCheckIn(
        firstName: 'First',
        lastName: 'Guest',
        birthdate: DateTime(2024, 1, 1),
        sex: Sex.male,
        address: 'Addr',
        guardianName: 'Guardian',
        guardianContact: '0900000001',
        reasonForVisit: 'Fever',
      );
      final second = await repo.guestCheckIn(
        firstName: 'Second',
        lastName: 'Guest',
        birthdate: DateTime(2024, 1, 1),
        sex: Sex.male,
        address: 'Addr',
        guardianName: 'Guardian',
        guardianContact: '0900000002',
        reasonForVisit: 'Fever',
      );

      expect(first.patient.id, isNot(equals(second.patient.id)));
      expect(first.queueEntry.queueNumber, isNot(equals(second.queueEntry.queueNumber)));
    });
  });

  group('Public display safety', () {
    test('queue entries expose only numbers, never patient identity', () async {
      final repo = _repoWithCategories();
      final patient = await _register(repo, 'Ana');
      final r = await repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');
      expect(r.queueEntry.displayNumber, matches(RegExp(r'^#\d{3,}$')));
    });
  });
}
