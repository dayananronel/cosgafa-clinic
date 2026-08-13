import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/backend_config.dart';
import 'providers/auth_provider.dart';
import 'providers/auth_session.dart';
import 'providers/supabase_auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/supabase_login_screen.dart';
import 'services/clinic_api.dart';
import 'services/clinic_repository.dart';
import 'services/seed_data.dart';
import 'services/supabase_clinic_api.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (BackendConfig.mode == BackendMode.supabase) {
    if (!BackendConfig.isSupabaseConfigured) {
      runApp(const _MissingSupabaseConfigApp());
      return;
    }
    await Supabase.initialize(
      url: BackendConfig.supabaseUrl,
      // supabase_flutter now calls this "publishableKey"; Supabase's own
      // dashboard still labels it "anon public key" as of this writing —
      // BackendConfig.supabaseAnonKey is the same value either way.
      publishableKey: BackendConfig.supabaseAnonKey,
    );
    final api = SupabaseClinicApi(Supabase.instance.client);
    final auth = SupabaseAuthProvider(Supabase.instance.client);
    // Every table's RLS read policy (0002_row_level_security.sql) requires
    // an authenticated staff session — initializing before sign-in would
    // fetch zero rows and, since initialize() only ever runs its bulk
    // fetch + realtime subscribe once, never pick up real data afterwards.
    // Wait for a real session instead; onAuthStateChange replays the
    // current session immediately, so this also covers a page reload with
    // an already-signed-in (persisted) session.
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        unawaited(api.initialize());
      }
    });
    runApp(CosgafaClinicApp(
      clinicApi: api,
      authSession: auth,
      home: const SupabaseLoginScreen(),
    ));
    return;
  }

  final repository = ClinicRepository();
  await seedDemoData(repository);
  final auth = AuthProvider(repository);
  runApp(CosgafaClinicApp(
    clinicApi: repository,
    authSession: auth,
    home: const LoginScreen(),
  ));
}

class CosgafaClinicApp extends StatelessWidget {
  const CosgafaClinicApp({
    super.key,
    required this.clinicApi,
    required this.authSession,
    required this.home,
  });

  final ClinicApi clinicApi;
  /// The concrete auth provider ([AuthProvider] or [SupabaseAuthProvider])
  /// — also exposed under the shared [AuthSession] type below so
  /// backend-agnostic screens never need to know which one is active.
  final AuthSession authSession;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClinicApi>.value(value: clinicApi),
        ChangeNotifierProvider<AuthSession>.value(value: authSession),
        if (authSession is AuthProvider)
          ChangeNotifierProvider<AuthProvider>.value(value: authSession as AuthProvider),
        if (authSession is SupabaseAuthProvider)
          ChangeNotifierProvider<SupabaseAuthProvider>.value(value: authSession as SupabaseAuthProvider),
      ],
      child: MaterialApp(
        title: 'Dr. Michelle Cosgafa Paediatrics Clinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: home,
      ),
    );
  }
}

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Configuration needed',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'BACKEND=supabase was set but SUPABASE_URL / SUPABASE_ANON_KEY '
              'were not provided. Pass them via --dart-define — see supabase/README.md.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
