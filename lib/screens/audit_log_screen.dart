import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/clinic_api.dart';
import '../utils/formatters.dart';
import '../widgets/clinic_app_bar.dart';

/// Spec section 17: every meaningful queue modification must be
/// traceable — who did what, and when. This screen surfaces the append-
/// only [QueueEvent] audit trail that every service method writes to.
class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicApi>();
    final events = repo.todayEvents;

    return Scaffold(
      appBar: const ClinicAppBar(title: 'Audit Log — Today'),
      body: events.isEmpty
          ? Center(
              child: Text('No queue activity recorded yet today.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = events[index];
                return ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 68,
                    child: Text(Formatters.time(e.createdAt), style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(e.eventType.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    [
                      if (e.oldStatus != null && e.newStatus != null) '${e.oldStatus} → ${e.newStatus}',
                      if (e.oldPriority != null && e.newPriority != null) 'Priority: ${e.oldPriority} → ${e.newPriority}',
                      if (e.reason != null && e.reason!.isNotEmpty) 'Reason: ${e.reason}',
                    ].join('   ·   '),
                  ),
                  trailing: Text('By ${e.performedBy}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                );
              },
            ),
    );
  }
}
