import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'services/clinic_repository.dart';
import 'services/seed_data.dart';
import 'utils/theme.dart';

void main() {
  final repository = ClinicRepository();
  seedDemoData(repository);
  runApp(CosgafaClinicApp(repository: repository));
}

class CosgafaClinicApp extends StatelessWidget {
  const CosgafaClinicApp({super.key, required this.repository});

  final ClinicRepository repository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClinicRepository>.value(value: repository),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(repository)),
      ],
      child: MaterialApp(
        title: 'Cosgafa Pediatric Clinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const LoginScreen(),
      ),
    );
  }
}
