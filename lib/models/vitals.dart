/// Measurements for a specific visit (spec 9.4). Never merged into the
/// permanent patient profile — vitals belong to the visit that recorded
/// them.
///
/// ASSUMPTION: MVP vitals fields are weight, temperature, height, and
/// oxygen saturation, matching the spec's example set (section 7 / 9.4).
/// CONFIRMATION REQUIRED: the clinic must confirm which measurements it
/// actually uses; unused fields should be omitted, not guessed.
class Vitals {
  final String id;
  final String visitId;
  final double? weightKg;
  final double? temperatureC;
  final double? heightCm;
  final double? oxygenSaturation;
  final DateTime recordedAt;
  final String recordedBy;

  Vitals({
    required this.id,
    required this.visitId,
    this.weightKg,
    this.temperatureC,
    this.heightCm,
    this.oxygenSaturation,
    required this.recordedAt,
    required this.recordedBy,
  });
}
