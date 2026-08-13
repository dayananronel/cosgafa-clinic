import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/supabase_codec.dart';
import 'auth_session.dart';

/// Real staff authentication for the Phase 2 Supabase backend — email +
/// password via Supabase Auth, with the signed-in user's clinic role
/// looked up from `staff_profiles` (spec 9.6). Replaces the seeded-
/// account picker ([AuthProvider]) used by the in-memory demo backend.
///
/// No self-registration: staff accounts are created by an admin ahead of
/// time (see supabase/README.md), matching the spec's closed staff
/// roster — there is no sign-up flow here.
class SupabaseAuthProvider extends AuthSession {
  SupabaseAuthProvider(this._client) {
    _client.auth.onAuthStateChange.listen((_) => _syncFromSession());
    _syncFromSession();
  }

  final SupabaseClient _client;
  AppUser? _currentUser;
  String? _lastError;

  @override
  AppUser? get currentUser => _currentUser;
  @override
  bool get isSignedIn => _currentUser != null;

  /// The reason the last [signInWithPassword] call failed, if any.
  String? get lastError => _lastError;

  void _syncFromSession() {
    final user = _client.auth.currentUser;
    if (user == null) {
      _currentUser = null;
      notifyListeners();
      return;
    }
    unawaited(_loadProfile(user.id));
  }

  Future<void> _loadProfile(String userId) async {
    try {
      final row = await _client.from('staff_profiles').select().eq('id', userId).single();
      _currentUser = staffProfileFromJson(row);
    } catch (_) {
      // Authenticated with Supabase but no matching staff_profiles row
      // yet (e.g. an admin hasn't run the insert from supabase/README.md).
      _currentUser = null;
    }
    notifyListeners();
  }

  Future<bool> signInWithPassword({required String email, required String password}) async {
    _lastError = null;
    try {
      final response = await _client.auth.signInWithPassword(email: email, password: password);
      if (response.user == null) {
        _lastError = 'Sign-in failed.';
        return false;
      }
      await _loadProfile(response.user!.id);
      if (_currentUser == null) {
        _lastError = 'This account has no staff profile yet. Ask an admin to set one up.';
        await _client.auth.signOut();
        return false;
      }
      return true;
    } on AuthException catch (e) {
      _lastError = e.message;
      return false;
    }
  }

  @override
  void signOut() {
    unawaited(_client.auth.signOut());
    _currentUser = null;
    notifyListeners();
  }
}
