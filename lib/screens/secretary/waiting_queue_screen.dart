import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/clinic_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/clinic_app_bar.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/status_badge.dart';
import 'intake_screen.dart';

/// Spec 10.4 Waiting Queue: queue #, patient identity, category, arrival
/// time, status, and priority — staff-only view, so full identity may be
/// shown (unlike the public display).
class WaitingQueueScreen extends StatefulWidget {
  const WaitingQueueScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<WaitingQueueScreen> createState() => _WaitingQueueScreenState();
}

class _WaitingQueueScreenState extends State<WaitingQueueScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicRepository>();
    final actor = context.read<AuthProvider>().currentUser?.name ?? 'Secretary';

    return Scaffold(
      appBar: const ClinicAppBar(title: 'Waiting Queue'),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [
                Tab(text: 'Waiting for Intake (${repo.waitingForIntakeQueue.length + repo.inIntakeQueue.length})'),
                Tab(text: 'Waiting for Doctor (${repo.doctorQueueSorted.length})'),
                Tab(text: 'Needs Decision (${repo.needsDecisionQueue.length})'),
                Tab(text: 'Skipped & Away (${repo.skippedQueue.length + repo.temporarilyAwayQueue.length})'),
                Tab(text: 'Completed (${repo.completedTodayQueue.length})'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _EntryList(
                  entries: [...repo.waitingForIntakeQueue, ...repo.inIntakeQueue],
                  repo: repo,
                  emptyText: 'No patients waiting for intake.',
                  actionBuilder: (entry) => FilledButton.tonal(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => IntakeScreen(queueEntryId: entry.id)),
                    ),
                    child: const Text('Intake'),
                  ),
                ),
                _EntryList(
                  entries: repo.doctorQueueSorted,
                  repo: repo,
                  emptyText: 'No patients waiting for the doctor.',
                  showPosition: true,
                  actionBuilder: (entry) => OutlinedButton(
                    onPressed: () {
                      repo.markTemporarilyAway(entry.id, actor: actor);
                    },
                    child: const Text('Mark Away'),
                  ),
                ),
                _EntryList(
                  entries: repo.needsDecisionQueue,
                  repo: repo,
                  emptyText: 'No patients need a doctor decision right now.',
                  actionBuilder: (entry) => const Chip(label: Text('Awaiting doctor')),
                ),
                _EntryList(
                  entries: [...repo.skippedQueue, ...repo.temporarilyAwayQueue],
                  repo: repo,
                  emptyText: 'No skipped or temporarily-away patients.',
                  actionBuilder: (entry) => entry.status == QueueStatus.skipped
                      ? FilledButton.tonal(
                          onPressed: () => repo.requeue(entry.id, actor: actor),
                          child: const Text('Requeue'),
                        )
                      : OutlinedButton(
                          onPressed: () => repo.returnFromAway(entry.id, actor: actor),
                          child: const Text('Returned'),
                        ),
                ),
                _EntryList(
                  entries: repo.completedTodayQueue,
                  repo: repo,
                  emptyText: 'No completed visits yet today.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.entries,
    required this.repo,
    required this.emptyText,
    this.actionBuilder,
    this.showPosition = false,
  });

  final List<QueueEntry> entries;
  final ClinicRepository repo;
  final String emptyText;
  final Widget Function(QueueEntry entry)? actionBuilder;
  final bool showPosition;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(emptyText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final patient = repo.patientForQueueEntry(entry);
        final category = repo.categoryById(entry.priorityCategoryId);

        final leading = Row(
          children: [
            if (showPosition)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            if (showPosition) const SizedBox(width: 12),
            PatientAvatar(patient.initials),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(entry.displayNumber, style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PriorityBadge(category),
                      Text('Arrived ${Formatters.shortTime(entry.checkedInAt)}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      StatusBadge(entry.status, dense: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Below this width, a trailing action button crowds the
                // patient name (and the identity + priority + status
                // content already needs room for showPosition/badges), so
                // the action drops to its own full-width row instead.
                final stackAction = actionBuilder != null && constraints.maxWidth < 380;
                if (actionBuilder == null) return leading;
                if (stackAction) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leading,
                      const SizedBox(height: 10),
                      actionBuilder!(entry),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: leading),
                    const SizedBox(width: 8),
                    actionBuilder!(entry),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
