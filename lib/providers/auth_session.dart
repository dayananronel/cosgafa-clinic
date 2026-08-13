import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// The session surface every screen depends on, independent of how
/// sign-in actually happens. [AuthProvider] (demo: pick a seeded
/// account) and `SupabaseAuthProvider` (Phase 2: real email/password
/// auth) both implement this, so screens never need to know which
/// backend is active.
abstract class AuthSession extends ChangeNotifier {
  AppUser? get currentUser;
  bool get isSignedIn;
  void signOut();
}
