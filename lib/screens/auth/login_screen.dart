import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/clinic_logo.dart';
import '../public/public_display_screen.dart';
import 'home_for_role.dart';

/// ASSUMPTION: sign-in here simply picks a seeded staff account, standing
/// in for real authenticated access (spec section 14/15) until a backend
/// with password hashing and session tokens exists. See
/// AuthProvider's doc comment. CONFIRMATION REQUIRED before production use.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final users = auth.availableUsers;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ClinicLogo(size: 84),
                  const SizedBox(height: 20),
                  Text(
                    'Dr. Michelle Cosgafa\nPaediatrics Clinic',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reception & Queue Management',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sign in as',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users.map(
                    (u) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UserTile(
                        user: u,
                        onTap: () {
                          context.read<AuthProvider>().signIn(u);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => homeForRole(u.role)),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PublicDisplayScreen()),
                      );
                    },
                    icon: const Icon(Icons.tv_outlined),
                    label: const Text('View Public Queue Display'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});

  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (user.role) {
      UserRole.secretary => Icons.support_agent,
      UserRole.doctor => Icons.medical_services_outlined,
      UserRole.admin => Icons.admin_panel_settings_outlined,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(user.role.label,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
