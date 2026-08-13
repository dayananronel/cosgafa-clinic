import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/clinic_repository.dart';
import '../../utils/formatters.dart';
import '../../utils/theme.dart';
import '../../widgets/clinic_app_bar.dart';
import '../../widgets/patient_avatar.dart';
import '../../widgets/status_badge.dart';

const _commonReasons = ['Follow-up', 'Fever', 'Cough/Cold', 'Vaccination', 'Other'];

/// Spec 10.3 Intake Screen: reason for visit, vitals, and administrative
/// queue category in one page — "Do not force the secretary through
/// unnecessary pages."
class IntakeScreen extends StatefulWidget {
  const IntakeScreen({super.key, required this.queueEntryId});

  final String queueEntryId;

  @override
  State<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends State<IntakeScreen> {
  final _reasonController = TextEditingController();
  final _weightController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _heightController = TextEditingController();
  final _oxygenController = TextEditingController();

  String? _selectedCategoryId;
  bool _needsDoctorDecision = false;
  bool _initialized = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _weightController.dispose();
    _temperatureController.dispose();
    _heightController.dispose();
    _oxygenController.dispose();
    super.dispose();
  }

  void _ensureStarted(ClinicRepository repo, QueueEntry entry, String actor) {
    if (entry.status == QueueStatus.waitingForIntake) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        repo.startIntake(entry.id, actor: actor);
      });
    }
  }

  double? _parse(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.trim());
  }

  void _complete(ClinicRepository repo, QueueEntry entry, String actor) {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reason for visit.')),
      );
      return;
    }
    if (!_needsDoctorDecision && _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a queue category.')),
      );
      return;
    }

    repo.recordVitals(
      entry.id,
      weightKg: _parse(_weightController.text),
      temperatureC: _parse(_temperatureController.text),
      heightCm: _parse(_heightController.text),
      oxygenSaturation: _parse(_oxygenController.text),
      actor: actor,
    );
    repo.completeIntake(
      entry.id,
      priorityCategoryId: _selectedCategoryId ?? repo.normalCategory.id,
      needsDoctorDecision: _needsDoctorDecision,
      reasonForVisitOverride: _reasonController.text,
      actor: actor,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicRepository>();
    final actor = context.read<AuthProvider>().currentUser?.name ?? 'Secretary';
    final entry = repo.todayQueueEntries.firstWhere((e) => e.id == widget.queueEntryId);
    final patient = repo.patientForQueueEntry(entry);
    final visit = repo.visitForQueueEntry(entry);

    _ensureStarted(repo, entry, actor);

    if (!_initialized) {
      _reasonController.text = visit.reasonForVisit;
      _selectedCategoryId = repo.normalCategory.id;
      _initialized = true;
    }

    final assignableCategories =
        repo.priorityCategories.where((c) => c.id != repo.doctorOverrideCategory.id).toList();

    return Scaffold(
      appBar: const ClinicAppBar(title: 'Intake'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      PatientAvatar(patient.initials, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(entry.displayNumber,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Theme.of(context).colorScheme.primary,
                                        fontSize: 16)),
                                const SizedBox(width: 8),
                                Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('${patient.patientNumber} · ${patient.ageDisplay} · Arrived ${Formatters.shortTime(entry.checkedInAt)}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      StatusBadge(entry.status),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _SectionLabel('Reason for Visit'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _commonReasons.map((r) {
                  return ChoiceChip(
                    label: Text(r),
                    selected: _reasonController.text == r,
                    onSelected: (_) => setState(() => _reasonController.text = r),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'Reason for visit'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Vitals'),
              Row(children: [
                Expanded(
                  child: _VitalField(
                    controller: _weightController,
                    label: 'Weight',
                    suffix: 'kg',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _VitalField(
                    controller: _temperatureController,
                    label: 'Temperature',
                    suffix: '°C',
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _VitalField(
                    controller: _heightController,
                    label: 'Height',
                    suffix: 'cm',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _VitalField(
                    controller: _oxygenController,
                    label: 'O₂ Saturation',
                    suffix: '%',
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _SectionLabel('Queue Category'),
              Text(
                'Administrative category only — the system never determines clinical priority.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: assignableCategories.map((c) {
                  return ChoiceChip(
                    label: Text(c.name),
                    selected: !_needsDoctorDecision && _selectedCategoryId == c.id,
                    onSelected: _needsDoctorDecision
                        ? null
                        : (_) => setState(() => _selectedCategoryId = c.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Card(
                color: _needsDoctorDecision
                    ? QueueColors.needsDecision.withValues(alpha: 0.1)
                    : null,
                child: SwitchListTile(
                  value: _needsDoctorDecision,
                  onChanged: (v) => setState(() => _needsDoctorDecision = v),
                  title: const Text('Not sure? Ask the doctor to decide', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Flags this patient as NEEDS DOCTOR DECISION instead of guessing priority.'),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () => _complete(repo, entry, actor),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                child: const Text('Complete Intake', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _VitalField extends StatelessWidget {
  const _VitalField({required this.controller, required this.label, required this.suffix});
  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    );
  }
}
