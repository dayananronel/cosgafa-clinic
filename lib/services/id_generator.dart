import 'package:uuid/uuid.dart';

/// Generates immutable internal IDs. Queue numbers are a separate,
/// human-facing, resettable sequence — never used as a primary key
/// (spec 7.2).
class IdGenerator {
  static const _uuid = Uuid();

  static String newId() => _uuid.v4();
}
