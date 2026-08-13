import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_session.dart';
import '../../services/clinic_api.dart';
import '../../services/exceptions.dart';

const _overrideReasons = ['Doctor decision', 'Clinical concern', 'Other'];

/// Spec section 11: a doctor override is never a single silent button.
/// The doctor must pick a reason (with a required explanation for
/// "Other") and explicitly confirm that this changes the queue order.
/// Every override is logged via [ClinicApi.doctorOverride].
Future<void> showPriorityOverrideDialog(
  BuildContext context, {
  required QueueEntry entry,
  required Patient patient,
  required int currentPosition,
}) {
  return showDialog(
    context: context,
    builder: (_) => _PriorityOverrideDialog(
      entry: entry,
      patient: patient,
      currentPosition: currentPosition,
    ),
  );
}

class _PriorityOverrideDialog extends StatefulWidget {
  const _PriorityOverrideDialog({required this.entry, required this.patient, required this.currentPosition});

  final QueueEntry entry;
  final Patient patient;
  final int currentPosition;

  @override
  State<_PriorityOverrideDialog> createState() => _PriorityOverrideDialogState();
}

class _PriorityOverrideDialogState extends State<_PriorityOverrideDialog> {
  String? _reason;
  final _otherController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_reason == null) {
      setState(() => _error = 'Please select a reason.');
      return;
    }
    if (_reason == 'Other' && _otherController.text.trim().isEmpty) {
      setState(() => _error = 'Please explain the reason.');
      return;
    }
    final repo = context.read<ClinicApi>();
    final actor = context.read<AuthSession>().currentUser;
    if (actor == null) return;
    try {
      await repo.doctorOverride(
        widget.entry.id,
        reason: _reason!,
        otherExplanation: _otherController.text,
        actor: actor,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthorizationException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Patient ${widget.entry.displayNumber}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patient.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Current position: #${widget.currentPosition}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.priority_high, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('This changes the queue order.', style: TextStyle(fontWeight: FontWeight.w700))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _overrideReasons.map((r) {
                return ChoiceChip(
                  label: Text(r),
                  selected: _reason == r,
                  onSelected: (_) => setState(() {
                    _reason = r;
                    _error = null;
                  }),
                );
              }).toList(),
            ),
            if (_reason == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherController,
                decoration: const InputDecoration(hintText: 'Explain the reason'),
                maxLines: 2,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _confirm, child: const Text('CONFIRM OVERRIDE')),
      ],
    );
  }
}
