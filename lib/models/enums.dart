/// Staff roles. No separate nurse role per spec section 9.6 — the clinic
/// has not requested one; do not invent it.
enum UserRole { admin, secretary, doctor }

enum Sex { male, female }

/// Visit-level status (spec 9.2).
enum VisitStatus { open, inConsultation, completed, cancelled }

/// Queue-entry operational state machine (spec 7.1).
///
/// ASSUMPTION: `needsDoctorDecision` is modeled as its own state, entered
/// from `inIntake`/`vitalsComplete` when the secretary is uncertain of
/// priority (spec step 9), and exited only by a doctor decision that moves
/// the entry to `waitingForDoctor`. `temporarilyAway` is included per the
/// edge case in spec section 13 ("Patient temporarily leaves").
/// CONFIRMATION REQUIRED: clinic policy should verify these transitions.
enum QueueStatus {
  checkedIn,
  waitingForIntake,
  inIntake,
  vitalsComplete,
  needsDoctorDecision,
  waitingForDoctor,
  called,
  inConsultation,
  completed,
  skipped,
  noShow,
  cancelled,
  temporarilyAway,
}

/// Audit event types (spec 9.7).
enum QueueEventType {
  checkIn,
  intakeStarted,
  patientRegistered,
  visitCreated,
  vitalsRecorded,
  queueCreated,
  priorityChanged,
  doctorOverride,
  called,
  skipped,
  requeued,
  consultationStarted,
  completed,
  cancelled,
  temporarilyAway,
  returned,
  needsDoctorDecision,
}

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Admin',
        UserRole.secretary => 'Secretary',
        UserRole.doctor => 'Doctor',
      };
}

extension SexX on Sex {
  String get label => switch (this) {
        Sex.male => 'Male',
        Sex.female => 'Female',
      };
}

extension VisitStatusX on VisitStatus {
  String get label => switch (this) {
        VisitStatus.open => 'Open',
        VisitStatus.inConsultation => 'In Consultation',
        VisitStatus.completed => 'Completed',
        VisitStatus.cancelled => 'Cancelled',
      };
}

extension QueueStatusX on QueueStatus {
  String get label => switch (this) {
        QueueStatus.checkedIn => 'Checked In',
        QueueStatus.waitingForIntake => 'Waiting for Intake',
        QueueStatus.inIntake => 'In Intake',
        QueueStatus.vitalsComplete => 'Vitals Complete',
        QueueStatus.needsDoctorDecision => 'Needs Doctor Decision',
        QueueStatus.waitingForDoctor => 'Waiting for Doctor',
        QueueStatus.called => 'Called',
        QueueStatus.inConsultation => 'In Consultation',
        QueueStatus.completed => 'Completed',
        QueueStatus.skipped => 'Skipped',
        QueueStatus.noShow => 'No Show',
        QueueStatus.cancelled => 'Cancelled',
        QueueStatus.temporarilyAway => 'Temporarily Away',
      };

  bool get isActiveInQueue => !{
        QueueStatus.completed,
        QueueStatus.cancelled,
        QueueStatus.noShow,
      }.contains(this);

  bool get isEligibleForDoctorQueue => {
        QueueStatus.waitingForDoctor,
        QueueStatus.needsDoctorDecision,
      }.contains(this);
}

extension QueueEventTypeX on QueueEventType {
  String get label => switch (this) {
        QueueEventType.checkIn => 'Checked in',
        QueueEventType.intakeStarted => 'Intake started',
        QueueEventType.patientRegistered => 'Patient registered',
        QueueEventType.visitCreated => 'Visit created',
        QueueEventType.vitalsRecorded => 'Vitals recorded',
        QueueEventType.queueCreated => 'Added to queue',
        QueueEventType.priorityChanged => 'Priority changed',
        QueueEventType.doctorOverride => 'Doctor override',
        QueueEventType.called => 'Called',
        QueueEventType.skipped => 'Skipped',
        QueueEventType.requeued => 'Requeued',
        QueueEventType.consultationStarted => 'Consultation started',
        QueueEventType.completed => 'Consultation completed',
        QueueEventType.cancelled => 'Cancelled',
        QueueEventType.temporarilyAway => 'Marked temporarily away',
        QueueEventType.returned => 'Returned from temporarily away',
        QueueEventType.needsDoctorDecision => 'Flagged: needs doctor decision',
      };
}
