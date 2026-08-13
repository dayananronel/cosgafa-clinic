import 'package:flutter_test/flutter_test.dart';

import 'package:cosgafa_clinic/main.dart';
import 'package:cosgafa_clinic/services/clinic_repository.dart';
import 'package:cosgafa_clinic/services/seed_data.dart';

void main() {
  testWidgets('App boots to the login screen with seeded staff accounts', (tester) async {
    final repository = ClinicRepository();
    seedDemoData(repository);

    await tester.pumpWidget(CosgafaClinicApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Cosgafa Pediatric Clinic'), findsOneWidget);
    expect(find.text('Sign in as'), findsOneWidget);
    expect(find.text('Grace Villanueva'), findsOneWidget);
    expect(find.text('Dr. Ramon Cosgafa'), findsOneWidget);
  });

  testWidgets('Secretary can sign in and reach the dashboard', (tester) async {
    final repository = ClinicRepository();
    seedDemoData(repository);

    await tester.pumpWidget(CosgafaClinicApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Grace Villanueva'));
    await tester.pumpAndSettle();

    expect(find.text('Secretary Dashboard'), findsOneWidget);
    expect(find.text('CHECK IN PATIENT'), findsOneWidget);
  });
}
