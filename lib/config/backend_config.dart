/// Selects which [ClinicApi] implementation the app runs against, set at
/// build/run time via `--dart-define` — never hard-coded, so the same
/// codebase serves both the Phase 1 demo preview and a real Phase 2
/// deployment.
///
/// Demo (default): `flutter run` / `flutter build web` with no flags.
/// Supabase: `flutter run \
///   --dart-define=BACKEND=supabase \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...`
///
/// The anon key is designed by Supabase to be embedded in client apps —
/// it identifies the project, not a privileged credential. Row-Level
/// Security (see supabase/migrations/) is what actually restricts what
/// it can do, exactly as described in docs/PHASE_2_BACKEND_SCOPE.md §3.
enum BackendMode { demo, supabase }

class BackendConfig {
  const BackendConfig._();

  static const String _backendString = String.fromEnvironment('BACKEND', defaultValue: 'demo');
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static BackendMode get mode =>
      _backendString == 'supabase' ? BackendMode.supabase : BackendMode.demo;

  static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
