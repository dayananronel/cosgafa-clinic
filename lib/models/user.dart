import 'enums.dart';

/// Staff account (spec 9.6). No nurse role — the clinic has a single
/// secretary who also performs intake/vitals; do not add roles the spec
/// does not request.
class AppUser {
  final String id;
  final String name;
  final String username;
  final UserRole role;
  final bool isActive;

  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.isActive = true,
  });
}
