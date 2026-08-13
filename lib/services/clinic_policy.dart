/// Clinic-configurable operational policy.
///
/// The spec repeatedly warns against inventing clinical/administrative
/// policy silently (Rule 2). Where the spec leaves a behavior for the
/// clinic to decide, that behavior is exposed here as a flag, not
/// hard-coded, and flagged as an assumption requiring clinic confirmation.
class ClinicPolicy {
  /// Spec section 13, "Patient is called but does not respond": the clinic
  /// must decide whether a requeued patient keeps its original priority
  /// and arrival time, or receives a new queue position.
  ///
  /// ASSUMPTION: requeued patients retain their original priority level
  /// and original check-in time, so they return to the same relative
  /// position rather than going to the back of the line.
  /// CONFIRMATION REQUIRED from clinic policy.
  final bool requeueRetainsPriorityAndArrival;

  /// Spec section 8 / Scenario 9: "Doctor can decrease priority if
  /// permitted by clinic policy." Secretary-level priority changes are
  /// always restricted to non-clinical categories (never the doctor
  /// override level); this flag governs whether the doctor may lower an
  /// existing prioritization back to normal, in addition to raising it.
  ///
  /// ASSUMPTION: enabled by default — a doctor may both raise and lower
  /// priority. CONFIRMATION REQUIRED from clinic policy.
  final bool doctorCanDecreasePriority;

  /// ASSUMPTION: the queue number sequence resets every operating day
  /// (spec section 6, Step 2 and Rule 9's own example). CONFIRMATION
  /// REQUIRED from clinic policy.
  final bool queueNumberResetsDaily;

  const ClinicPolicy({
    this.requeueRetainsPriorityAndArrival = true,
    this.doctorCanDecreasePriority = true,
    this.queueNumberResetsDaily = true,
  });
}
