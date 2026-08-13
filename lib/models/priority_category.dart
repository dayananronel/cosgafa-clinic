/// Clinic-configurable administrative queue category (spec 9.5, 7.5).
/// Lower [priorityLevel] is served first. The application must never
/// hard-code medical assumptions about which categories exist — clinic
/// staff define these.
class PriorityCategory {
  final String id;
  final String name;
  final int priorityLevel;
  final String description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PriorityCategory({
    required this.id,
    required this.name,
    required this.priorityLevel,
    this.description = '',
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });
}
