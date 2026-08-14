import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/backend_config.dart';
import '../models/models.dart';
import '../providers/auth_session.dart';
import '../screens/audit_log_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/supabase_login_screen.dart';
import '../screens/public/public_display_screen.dart';

class ClinicAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ClinicAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    final user = auth.currentUser;
    // Below this width the user's name/role label is dropped and the icon
    // actions get tighter spacing so the bar never overflows on a phone.
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return AppBar(
      titleSpacing: isCompact ? 12 : null,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
        overflow: TextOverflow.ellipsis,
      ),
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
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 2 : 8),
            child: PopupMenuButton<String>(
              tooltip: user.name,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                    if (!isCompact) ...[
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
                  ],
                ),
              ),
              onSelected: (value) {
                if (value == 'signout') {
                  context.read<AuthSession>().signOut();
                  // Must match whichever backend is active: LoginScreen
                  // reads AuthProvider, which is only registered for the
                  // demo backend (main.dart) -- pushing it unconditionally
                  // threw ProviderNotFoundException in Supabase mode.
                  final loginScreen = BackendConfig.mode == BackendMode.supabase
                      ? const SupabaseLoginScreen()
                      : const LoginScreen();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => loginScreen),
                    (route) => false,
                  );
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'signout', child: Text('Sign out')),
              ],
            ),
          ),
        SizedBox(width: isCompact ? 2 : 8),
      ],
    );
  }
}
