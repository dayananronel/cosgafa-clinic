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

Patient _register(ClinicRepository repo, String first) {
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
    test('walks check-in through consultation completion', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Ana');
      final result = repo.checkIn(newlyRegisteredPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');

      var entry = repo.startIntake(result.queueEntry.id, actor: 'secretary');
      expect(entry.status, QueueStatus.inIntake);

      entry = repo.recordVitals(entry.id, weightKg: 10, temperatureC: 37.5, actor: 'secretary');
      expect(entry.status, QueueStatus.vitalsComplete);

      entry = repo.completeIntake(entry.id, priorityCategoryId: 'normal', actor: 'secretary');
      expect(entry.status, QueueStatus.waitingForDoctor);

      entry = repo.callPatient(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.called);

      entry = repo.startConsultation(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.inConsultation);

      entry = repo.completeConsultation(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.completed);
      expect(repo.getVisit(result.visit.id)!.status, VisitStatus.completed);
    });
  });

  group('Scenario 2 — Existing patient, no duplicate record', () {
    test('reuses the existing patient id across visits', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Renzo');
      expect(repo.patients.length, 1);

      repo.checkIn(existingPatient: patient, reasonForVisit: 'Follow-up', actor: 'secretary');
      expect(repo.patients.length, 1);
      expect(repo.visitsForPatient(patient.id).length, 1);
    });
  });

  group('Scenario 3 & 4 — Arrival order', () {
    test('same-priority patients are ordered strictly by check-in time', () {
      final repo = _repoWithCategories();
      final a = _register(repo, 'A');
      final b = _register(repo, 'B');
      final c = _register(repo, 'C');

      for (final p in [a, b, c]) {
        final r = repo.checkIn(existingPatient: p, reasonForVisit: 'Checkup', actor: 'secretary');
        repo.startIntake(r.queueEntry.id, actor: 'secretary');
        repo.recordVitals(r.queueEntry.id, actor: 'secretary');
        repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');
      }

      final order = repo.doctorQueueSorted.map((e) => repo.patientForQueueEntry(e).firstName).toList();
      expect(order, ['A', 'B', 'C']);
    });
  });

  group('Scenario 5 — Doctor override', () {
    test('prioritized patient moves to the front and the change is audited', () {
      final repo = _repoWithCategories();
      final a = _register(repo, 'A');
      final b = _register(repo, 'B');
      final c = _register(repo, 'C');
      final entries = <QueueEntry>[];
      for (final p in [a, b, c]) {
        final r = repo.checkIn(existingPatient: p, reasonForVisit: 'Checkup', actor: 'secretary');
        repo.startIntake(r.queueEntry.id, actor: 'secretary');
        repo.recordVitals(r.queueEntry.id, actor: 'secretary');
        entries.add(repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary'));
      }

      final doctorUser = AppUser(id: 'd1', name: 'Dr. Test', username: 'doctor', role: UserRole.doctor);
      repo.doctorOverride(entries[2].id, reason: 'Clinical concern', actor: doctorUser);

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
    test('flags NEEDS_DOCTOR_DECISION and the doctor resolves it', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Ella');
      final r = repo.checkIn(existingPatient: patient, reasonForVisit: 'Unclear', actor: 'secretary');
      repo.startIntake(r.queueEntry.id, actor: 'secretary');
      repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      final entry = repo.completeIntake(
        r.queueEntry.id,
        priorityCategoryId: 'normal',
        needsDoctorDecision: true,
        actor: 'secretary',
      );
      expect(entry.status, QueueStatus.needsDoctorDecision);
      expect(repo.needsDecisionQueue, contains(entry));

      final doctorUser = AppUser(id: 'd1', name: 'Dr. Test', username: 'doctor', role: UserRole.doctor);
      final resolved = repo.doctorKeepNormalPriority(entry.id, actor: doctorUser);
      expect(resolved.status, QueueStatus.waitingForDoctor);
    });
  });

  group('Scenario 7 — Skip and requeue', () {
    test('a called patient who does not respond can be requeued', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Miguel');
      final r = repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      repo.startIntake(r.queueEntry.id, actor: 'secretary');
      repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      var entry = repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');
      entry = repo.callPatient(entry.id, actor: 'doctor');
      entry = repo.skip(entry.id, actor: 'doctor');
      expect(entry.status, QueueStatus.skipped);

      entry = repo.requeue(entry.id, actor: 'secretary');
      expect(entry.status, QueueStatus.waitingForDoctor);
    });
  });

  group('Scenario 9 — Unauthorized priority change', () {
    test('secretary cannot issue a doctor override', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Sofia');
      final r = repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      repo.startIntake(r.queueEntry.id, actor: 'secretary');
      repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      final entry = repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'normal', actor: 'secretary');

      final secretaryUser = AppUser(id: 's1', name: 'Secretary Test', username: 'secretary', role: UserRole.secretary);
      expect(
        () => repo.doctorOverride(entry.id, reason: 'Doctor decision', actor: secretaryUser),
        throwsA(isA<AuthorizationException>()),
      );
    });

    test('secretary cannot assign the doctor-priority category during intake', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Miguel');
      final r = repo.checkIn(existingPatient: patient, reasonForVisit: 'Checkup', actor: 'secretary');
      repo.startIntake(r.queueEntry.id, actor: 'secretary');
      repo.recordVitals(r.queueEntry.id, actor: 'secretary');
      expect(
        () => repo.completeIntake(r.queueEntry.id, priorityCategoryId: 'doctor', actor: 'secretary'),
        throwsA(isA<AuthorizationException>()),
      );
    });
  });

  group('Duplicate prevention', () {
    test('checking in the same patient twice in one day throws', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Ana');
      repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');
      expect(
        () => repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever again', actor: 'secretary'),
        throwsA(isA<DuplicateOperationException>()),
      );
    });
  });

  group('Public display safety', () {
    test('queue entries expose only numbers, never patient identity', () {
      final repo = _repoWithCategories();
      final patient = _register(repo, 'Ana');
      final r = repo.checkIn(existingPatient: patient, reasonForVisit: 'Fever', actor: 'secretary');
      expect(r.queueEntry.displayNumber, matches(RegExp(r'^#\d{3,}$')));
    });
  });
}
