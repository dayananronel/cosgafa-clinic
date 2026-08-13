import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/clinic_api.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/clinic_app_bar.dart';
import '../../widgets/dashboard_stat_card.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/status_badge.dart';
import 'check_in_screen.dart';
import 'intake_screen.dart';
import 'waiting_queue_screen.dart';

/// Spec 10.1: Secretary Dashboard — today's date, status counts, and the
/// primary check-in action, kept to a single screen so the secretary
/// (the clinic's single operational bottleneck, spec 2.2 Problem E) never
/// has to dig through navigation.
class SecretaryDashboardScreen extends StatelessWidget {
  const SecretaryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicApi>();
    final waitingIntake = repo.waitingForIntakeQueue.length + repo.inIntakeQueue.length;

    return Scaffold(
      appBar: const ClinicAppBar(title: 'Secretary Dashboard'),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              Formatters.date(DateTime.now()),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CheckInScreen()),
                  );
                },
                icon: const Icon(Icons.how_to_reg, size: 24),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('CHECK IN PATIENT', style: TextStyle(fontSize: 18)),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 560 ? 2 : 1);
              final items = [
                DashboardStatCard(
                  label: 'WAITING FOR INTAKE',
                  count: waitingIntake,
                  color: QueueColors.waitingForIntake,
                  icon: Icons.assignment_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WaitingQueueScreen(initialTabIndex: 0)),
                  ),
                ),
                DashboardStatCard(
                  label: 'WAITING FOR DOCTOR',
                  count: repo.countWaitingForDoctor,
                  color: QueueColors.waitingForDoctor,
                  icon: Icons.event_seat_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WaitingQueueScreen(initialTabIndex: 1)),
                  ),
                ),
                DashboardStatCard(
                  label: 'NEEDS DOCTOR DECISION',
                  count: repo.countNeedsDoctorDecision,
                  color: QueueColors.needsDecision,
                  icon: Icons.help_outline,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WaitingQueueScreen(initialTabIndex: 2)),
                  ),
                ),
                DashboardStatCard(
                  label: 'IN CONSULTATION',
                  count: repo.countInConsultation,
                  color: QueueColors.inConsultation,
                  icon: Icons.local_hospital_outlined,
                ),
                DashboardStatCard(
                  label: 'COMPLETED',
                  count: repo.countCompleted,
                  color: QueueColors.completed,
                  icon: Icons.check_circle_outline,
                ),
              ];
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: cols == 1 ? 3.2 : 2.6,
                children: items,
              );
            }),
            const SizedBox(height: 28),
            Row(
              children: [
                Text('Waiting for Intake', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WaitingQueueScreen()),
                  ),
                  child: const Text('View full queue'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (repo.waitingForIntakeQueue.isEmpty && repo.inIntakeQueue.isEmpty)
              const _EmptyRow(text: 'No patients waiting for intake.')
            else ...[
              for (final entry in repo.waitingForIntakeQueue)
                _IntakeRow(entry: entry, repo: repo),
              for (final entry in repo.inIntakeQueue)
                _IntakeRow(entry: entry, repo: repo),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntakeRow extends StatelessWidget {
  const _IntakeRow({required this.entry, required this.repo});

  final QueueEntry entry;
  final ClinicApi repo;

  @override
  Widget build(BuildContext context) {
    final patient = repo.patientForQueueEntry(entry);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: PatientAvatar(patient.initials),
        title: Text('${entry.displayNumber}  ·  ${patient.fullName}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('Arrived ${Formatters.shortTime(entry.checkedInAt)} · ${patient.ageDisplay}'),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(entry.status, dense: true),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => IntakeScreen(queueEntryId: entry.id)),
                );
              },
              child: const Text('Intake'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}
