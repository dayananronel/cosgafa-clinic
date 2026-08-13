import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/clinic_repository.dart';
import '../../services/exceptions.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/clinic_app_bar.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/status_badge.dart';
import 'priority_override_dialog.dart';

/// Spec 10.5 Doctor Dashboard: current patient, next patients, and
/// patients needing a priority decision, with call/prioritize/requeue/
/// start/complete actions. The doctor is the sole clinical-priority
/// authority (spec 4.5) — this screen is the only place overrides happen.
class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicRepository>();
    final auth = context.watch<AuthProvider>();
    final actor = auth.currentUser?.name ?? 'Doctor';
    final current = repo.currentlyServingEntry;
    final queue = repo.doctorQueueSorted;
    final needsDecision = repo.needsDecisionQueue;
    final skipped = repo.skippedQueue;

    return Scaffold(
      appBar: const ClinicAppBar(title: 'Doctor Dashboard'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SectionHeader('Current Patient'),
          const SizedBox(height: 10),
          current == null
              ? _EmptyCard(
                  text: 'No patient is currently being served.',
                  action: queue.isEmpty
                      ? null
                      : FilledButton.icon(
                          onPressed: () {
                            try {
                              repo.callNext(actor: actor);
                            } on InvalidQueueTransitionException catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                            }
                          },
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('CALL NEXT PATIENT'),
                        ),
                )
              : _CurrentPatientCard(entry: current, repo: repo, actor: actor),
          const SizedBox(height: 28),
          if (needsDecision.isNotEmpty) ...[
            _SectionHeader('Needs Priority Decision', color: QueueColors.needsDecision),
            const SizedBox(height: 10),
            ...needsDecision.map((e) => _NeedsDecisionRow(entry: e, repo: repo, actor: actor)),
            const SizedBox(height: 28),
          ],
          _SectionHeader('Next Patients (${queue.length})'),
          const SizedBox(height: 10),
          if (queue.isEmpty)
            const _EmptyCard(text: 'No patients waiting for the doctor.')
          else
            ...List.generate(queue.length, (i) => _NextPatientRow(
                  entry: queue[i],
                  position: i + 1,
                  repo: repo,
                  actor: actor,
                  canCall: current == null && i == 0,
                )),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHeader('Skipped', color: QueueColors.skipped),
            const SizedBox(height: 10),
            ...skipped.map((e) => _SkippedRow(entry: e, repo: repo, actor: actor)),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (color != null) ...[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
        ],
        Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _CurrentPatientCard extends StatelessWidget {
  const _CurrentPatientCard({required this.entry, required this.repo, required this.actor});
  final QueueEntry entry;
  final ClinicRepository repo;
  final String actor;

  @override
  Widget build(BuildContext context) {
    final patient = repo.patientForQueueEntry(entry);
    final visit = repo.visitForQueueEntry(entry);
    final vitals = repo.vitalsForVisit(visit.id);
    final category = repo.categoryById(entry.priorityCategoryId);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PatientAvatar(patient.initials, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(entry.displayNumber, style: TextStyle(fontWeight: FontWeight.w900, color: scheme.primary, fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      ]),
                      Text('${patient.ageDisplay} · ${patient.sex.label} · ${patient.patientNumber}',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                StatusBadge(entry.status),
              ],
            ),
            const Divider(height: 32),
            _DetailRow(label: 'Reason for visit', value: visit.reasonForVisit),
            _DetailRow(label: 'Category', value: category.name),
            if (vitals != null)
              _DetailRow(
                label: 'Vitals',
                value: [
                  if (vitals.weightKg != null) '${vitals.weightKg} kg',
                  if (vitals.temperatureC != null) '${vitals.temperatureC} °C',
                  if (vitals.heightCm != null) '${vitals.heightCm} cm',
                  if (vitals.oxygenSaturation != null) 'SpO₂ ${vitals.oxygenSaturation}%',
                ].join('  ·  '),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (entry.status == QueueStatus.called) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => repo.skip(entry.id, actor: actor),
                      child: const Text('Skip (no response)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => repo.startConsultation(entry.id, actor: actor),
                      child: const Text('Start Consultation'),
                    ),
                  ),
                ] else if (entry.status == QueueStatus.inConsultation)
                  Expanded(
                    child: FilledButton(
                      onPressed: () => repo.completeConsultation(entry.id, actor: actor),
                      child: const Text('Complete Consultation'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _NeedsDecisionRow extends StatelessWidget {
  const _NeedsDecisionRow({required this.entry, required this.repo, required this.actor});
  final QueueEntry entry;
  final ClinicRepository repo;
  final String actor;

  @override
  Widget build(BuildContext context) {
    final patient = repo.patientForQueueEntry(entry);
    final visit = repo.visitForQueueEntry(entry);
    final auth = context.read<AuthProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: QueueColors.needsDecision.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PatientAvatar(patient.initials),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.displayNumber}  ${patient.fullName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(visit.reasonForVisit, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final user = auth.currentUser;
                      if (user == null) return;
                      try {
                        repo.doctorKeepNormalPriority(entry.id, actor: user);
                      } on AuthorizationException catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
                    child: const Text('Keep Normal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => showPriorityOverrideDialog(
                      context,
                      entry: entry,
                      patient: patient,
                      currentPosition: repo.needsDecisionQueue.indexOf(entry) + 1,
                    ),
                    child: const Text('PRIORITIZE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NextPatientRow extends StatelessWidget {
  const _NextPatientRow({
    required this.entry,
    required this.position,
    required this.repo,
    required this.actor,
    required this.canCall,
  });

  final QueueEntry entry;
  final int position;
  final ClinicRepository repo;
  final String actor;
  final bool canCall;

  @override
  Widget build(BuildContext context) {
    final patient = repo.patientForQueueEntry(entry);
    final category = repo.categoryById(entry.priorityCategoryId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: Text('$position', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            PatientAvatar(patient.initials),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${entry.displayNumber}  ${patient.fullName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PriorityBadge(category),
                      Text('Arrived ${Formatters.shortTime(entry.checkedInAt)}',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Prioritize',
              icon: const Icon(Icons.priority_high),
              onPressed: () => showPriorityOverrideDialog(
                context,
                entry: entry,
                patient: patient,
                currentPosition: position,
              ),
            ),
            if (canCall)
              FilledButton(
                onPressed: () => repo.callPatient(entry.id, actor: actor),
                child: const Text('Call'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkippedRow extends StatelessWidget {
  const _SkippedRow({required this.entry, required this.repo, required this.actor});
  final QueueEntry entry;
  final ClinicRepository repo;
  final String actor;

  @override
  Widget build(BuildContext context) {
    final patient = repo.patientForQueueEntry(entry);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: PatientAvatar(patient.initials),
        title: Text('${entry.displayNumber}  ${patient.fullName}'),
        subtitle: Text('Skipped at ${entry.calledAt != null ? Formatters.shortTime(entry.calledAt!) : '-'}'),
        trailing: FilledButton.tonal(
          onPressed: () => repo.requeue(entry.id, actor: actor),
          child: const Text('Requeue'),
        ),
      ),
    );
  }
}
