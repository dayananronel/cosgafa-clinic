import '../models/models.dart';
import 'clinic_repository.dart';

/// Demo data so the prototype (spec section 19, Phase 3) has something to
/// show. None of this represents real patients. In a production
/// deployment this seeding must not run.
void seedDemoData(ClinicRepository repo) {
  final now = DateTime.now();

  repo.seedUsers(const [
    AppUser(id: 'u-secretary', name: 'Grace Villanueva', username: 'secretary', role: UserRole.secretary),
    AppUser(id: 'u-doctor', name: 'Dr. Ramon Cosgafa', username: 'doctor', role: UserRole.doctor),
    AppUser(id: 'u-admin', name: 'Clinic Admin', username: 'admin', role: UserRole.admin),
  ]);

  // ASSUMPTION (spec 7.5 / Step 8): example administrative categories
  // only. The clinic must confirm its actual policy and names.
  repo.seedPriorityCategories([
    PriorityCategory(
      id: 'cat-doctor-priority',
      name: 'Doctor Priority',
      priorityLevel: 1,
      description: 'Reserved for doctor-authorized overrides only.',
      createdAt: now,
      updatedAt: now,
    ),
    PriorityCategory(
      id: 'cat-special',
      name: 'Special Assistance',
      priorityLevel: 2,
      description: 'Children requiring special assistance.',
      createdAt: now,
      updatedAt: now,
    ),
    PriorityCategory(
      id: 'cat-followup',
      name: 'Follow-up / Newborn',
      priorityLevel: 3,
      description: 'Follow-up visits and newborns.',
      createdAt: now,
      updatedAt: now,
    ),
    PriorityCategory(
      id: 'cat-normal',
      name: 'Normal',
      priorityLevel: 4,
      description: 'Standard walk-in visit.',
      createdAt: now,
      updatedAt: now,
    ),
  ]);

  Patient seedPatient({
    required String id,
    required String num,
    required String first,
    String middle = '',
    required String last,
    required DateTime birth,
    required Sex sex,
    required String guardian,
    required String contact,
  }) {
    final p = Patient(
      id: id,
      patientNumber: num,
      firstName: first,
      middleName: middle,
      lastName: last,
      birthdate: birth,
      sex: sex,
      address: 'Cosgafa, Philippines',
      guardianName: guardian,
      guardianContact: contact,
      createdAt: now,
      updatedAt: now,
      createdBy: 'seed',
      updatedBy: 'seed',
    );
    repo.addPatientDirect(p);
    return p;
  }

  final maria = seedPatient(
    id: 'p1',
    num: 'P2026-00001',
    first: 'Maria',
    middle: 'Santos',
    last: 'Dela Cruz',
    birth: DateTime(2025, 4, 10),
    sex: Sex.female,
    guardian: 'Juan Dela Cruz',
    contact: '0917 000 0001',
  );
  final renzo = seedPatient(
    id: 'p2',
    num: 'P2026-00002',
    first: 'Renzo',
    last: 'Domingo',
    birth: DateTime(2022, 11, 2),
    sex: Sex.male,
    guardian: 'Liza Domingo',
    contact: '0917 000 0002',
  );
  final ella = seedPatient(
    id: 'p3',
    num: 'P2026-00003',
    first: 'Ella',
    last: 'Reyes',
    birth: DateTime(2024, 1, 20),
    sex: Sex.female,
    guardian: 'Mark Reyes',
    contact: '0917 000 0003',
  );
  seedPatient(
    id: 'p4',
    num: 'P2026-00004',
    first: 'Miguel',
    last: 'Torres',
    birth: DateTime(2023, 6, 15),
    sex: Sex.male,
    guardian: 'Ana Torres',
    contact: '0917 000 0004',
  );
  seedPatient(
    id: 'p5',
    num: 'P2026-00005',
    first: 'Sofia',
    last: 'Bautista',
    birth: DateTime(2026, 5, 1),
    sex: Sex.female,
    guardian: 'Carmen Bautista',
    contact: '0917 000 0005',
  );

  // Completed visit: Maria, seen earlier this morning.
  final r1 = repo.checkIn(existingPatient: maria, reasonForVisit: 'Fever', actor: 'seed');
  repo.startIntake(r1.queueEntry.id, actor: 'seed');
  repo.recordVitals(r1.queueEntry.id, weightKg: 9.8, temperatureC: 37.1, heightCm: 78, actor: 'seed');
  repo.completeIntake(r1.queueEntry.id, priorityCategoryId: 'cat-normal', actor: 'seed');
  repo.callPatient(r1.queueEntry.id, actor: 'seed');
  repo.startConsultation(r1.queueEntry.id, actor: 'seed');
  repo.completeConsultation(r1.queueEntry.id, actor: 'seed');

  // Currently in consultation: Renzo.
  final r2 = repo.checkIn(existingPatient: renzo, reasonForVisit: 'Follow-up', actor: 'seed');
  repo.startIntake(r2.queueEntry.id, actor: 'seed');
  repo.recordVitals(r2.queueEntry.id, weightKg: 14.2, temperatureC: 36.8, heightCm: 92, actor: 'seed');
  repo.completeIntake(r2.queueEntry.id, priorityCategoryId: 'cat-followup', actor: 'seed');
  repo.callPatient(r2.queueEntry.id, actor: 'seed');
  repo.startConsultation(r2.queueEntry.id, actor: 'seed');

  // Waiting for doctor: Ella (needs doctor decision).
  final r3 = repo.checkIn(existingPatient: ella, reasonForVisit: 'Persistent cough, parent worried', actor: 'seed');
  repo.startIntake(r3.queueEntry.id, actor: 'seed');
  repo.recordVitals(r3.queueEntry.id, weightKg: 11.0, temperatureC: 38.4, heightCm: 84, oxygenSaturation: 96, actor: 'seed');
  repo.completeIntake(r3.queueEntry.id, priorityCategoryId: 'cat-normal', needsDoctorDecision: true, actor: 'seed');

  // Waiting for doctor: Miguel (normal).
  final miguel = repo.patients.firstWhere((p) => p.id == 'p4');
  final r4 = repo.checkIn(existingPatient: miguel, reasonForVisit: 'Vaccination', actor: 'seed');
  repo.startIntake(r4.queueEntry.id, actor: 'seed');
  repo.recordVitals(r4.queueEntry.id, weightKg: 12.5, temperatureC: 36.7, heightCm: 88, actor: 'seed');
  repo.completeIntake(r4.queueEntry.id, priorityCategoryId: 'cat-normal', actor: 'seed');

  // Waiting for intake: Sofia (newborn, just checked in).
  final sofia = repo.patients.firstWhere((p) => p.id == 'p5');
  repo.checkIn(existingPatient: sofia, reasonForVisit: 'Newborn check-up', actor: 'seed');
}
