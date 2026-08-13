/// Thrown when an actor attempts an action their role does not permit.
/// The backend/service layer enforces this independent of whether the UI
/// happens to show the control (spec Scenario 9 — the backend must
/// enforce authorization, not just hide the button).
class AuthorizationException implements Exception {
  final String message;
  AuthorizationException(this.message);
  @override
  String toString() => message;
}

/// Thrown when an operation would violate the queue state machine, e.g.
/// calling a patient who is not yet waiting for the doctor.
class InvalidQueueTransitionException implements Exception {
  final String message;
  InvalidQueueTransitionException(this.message);
  @override
  String toString() => message;
}

/// Thrown when a duplicate operation is attempted, e.g. checking in a
/// patient who already has an open visit today (spec section 13,
/// "Duplicate visit").
class DuplicateOperationException implements Exception {
  final String message;
  DuplicateOperationException(this.message);
  @override
  String toString() => message;
}
