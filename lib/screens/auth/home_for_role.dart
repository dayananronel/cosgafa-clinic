import 'package:flutter/widgets.dart';

import '../../models/models.dart';
import '../doctor/doctor_dashboard_screen.dart';
import '../secretary/secretary_dashboard_screen.dart';

/// The landing screen for a signed-in staff member, shared by both the
/// demo account-picker login and the real Supabase email/password login.
Widget homeForRole(UserRole role) {
  switch (role) {
    case UserRole.secretary:
    case UserRole.admin:
      return const SecretaryDashboardScreen();
    case UserRole.doctor:
      return const DoctorDashboardScreen();
  }
}
