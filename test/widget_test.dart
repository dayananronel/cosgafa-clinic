import 'package:flutter_test/flutter_test.dart';

import 'package:cosgafa_clinic/main.dart';
import 'package:cosgafa_clinic/providers/auth_provider.dart';
import 'package:cosgafa_clinic/screens/auth/login_screen.dart';
import 'package:cosgafa_clinic/services/clinic_repository.dart';
import 'package:cosgafa_clinic/services/seed_data.dart';

void main() {
  testWidgets('App boots to the login screen with seeded staff accounts', (tester) async {
    final repository = ClinicRepository();
    await seedDemoData(repository);

    await tester.pumpWidget(CosgafaClinicApp(
      clinicApi: repository,
      authSession: AuthProvider(repository),
      home: const LoginScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Michelle Cosgafa\nPaediatrics Clinic'), findsOneWidget);
    expect(find.text('Sign in as'), findsOneWidget);
    expect(find.text('Grace Villanueva'), findsOneWidget);
    expect(find.text('Dr. Ramon Cosgafa'), findsOneWidget);
  });

  testWidgets('Secretary can sign in and reach the dashboard', (tester) async {
    final repository = ClinicRepository();
    await seedDemoData(repository);

    await tester.pumpWidget(CosgafaClinicApp(
      clinicApi: repository,
      authSession: AuthProvider(repository),
      home: const LoginScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grace Villanueva'));
    await tester.pumpAndSettle();

    expect(find.text('Secretary Dashboard'), findsOneWidget);
    expect(find.text('CHECK IN PATIENT'), findsOneWidget);
  });
}
