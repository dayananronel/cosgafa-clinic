import '../models/models.dart';
import '../services/clinic_api.dart';
import 'auth_session.dart';

/// Session state for the currently signed-in staff member, for the
/// in-memory demo backend ([ClinicRepository]).
///
/// ASSUMPTION: this prototype signs in by picking a seeded demo account,
/// with no password check. Spec section 14/15 requires real authenticated
/// staff access (hashed passwords, POST /auth/login, secure session
/// tokens) before any production deployment. CONFIRMATION REQUIRED — do
/// not treat this as production authentication. See
/// `SupabaseAuthProvider` for the real-auth Phase 2 equivalent used when
/// the app is running against a Supabase backend.
class AuthProvider extends AuthSession {
  AuthProvider(this._repository);

  final ClinicApi _repository;
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;
  @override
  bool get isSignedIn => _currentUser != null;

  List<AppUser> get availableUsers => _repository.users;

  void signIn(AppUser user) {
    _currentUser = user;
    notifyListeners();
  }

  @override
  void signOut() {
    _currentUser = null;
    notifyListeners();
  }
}
