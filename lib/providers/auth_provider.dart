import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/clinic_repository.dart';

/// Session state for the currently signed-in staff member.
///
/// ASSUMPTION: this prototype signs in by picking a seeded demo account,
/// with no password check. Spec section 14/15 requires real authenticated
/// staff access (hashed passwords, POST /auth/login, secure session
/// tokens) before any production deployment. CONFIRMATION REQUIRED — do
/// not treat this as production authentication.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository);

  final ClinicRepository _repository;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  List<AppUser> get availableUsers => _repository.users;

  void signIn(AppUser user) {
    _currentUser = user;
    notifyListeners();
  }

  void signOut() {
    _currentUser = null;
    notifyListeners();
  }
}
