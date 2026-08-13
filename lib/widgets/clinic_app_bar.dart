import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../screens/audit_log_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/public/public_display_screen.dart';

class ClinicAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ClinicAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    return AppBar(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        ...?actions,
        IconButton(
          tooltip: 'Audit Log',
          icon: const Icon(Icons.history),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuditLogScreen()),
            );
          },
        ),
        IconButton(
          tooltip: 'Public Queue Display',
          icon: const Icon(Icons.tv_outlined),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PublicDisplayScreen()),
            );
          },
        ),
        if (user != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: PopupMenuButton<String>(
              tooltip: user.name,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        user.name.isNotEmpty ? user.name[0] : '?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(user.role.label,
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              onSelected: (value) {
                if (value == 'signout') {
                  context.read<AuthProvider>().signOut();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ],
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}
