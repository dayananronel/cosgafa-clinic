import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_session.dart';
import '../../services/clinic_api.dart';
import '../../services/exceptions.dart';
import '../../utils/formatters.dart';
import '../../widgets/clinic_app_bar.dart';
import '../../widgets/patient_avatar.dart';

enum _Stage { chooseType, searchExisting, confirmExisting, registerNew, reasonForVisit, done }

const _commonReasons = ['Follow-up', 'Fever', 'Cough/Cold', 'Vaccination', 'Other'];

/// Spec Step 3–6 / section 10.2: the Check-In Screen. Bundles patient
/// identification (existing lookup or new registration), reason for
/// visit, arrival recording, and queue-number assignment into one fast
/// flow, since the secretary is the clinic's only operator (spec 4.6,
/// Problem E).
class CheckInScreen extends StatefulWidget {
  const CheckInScreen({super.key});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  _Stage _stage = _Stage.chooseType;

  Patient? _pendingExistingPatient;
  Patient? _confirmedPatient;
  bool _isNewlyRegistered = false;

  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _selectedCommonReason;

  QueueEntry? _resultEntry;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _stage = _Stage.chooseType;
      _pendingExistingPatient = null;
      _confirmedPatient = null;
      _isNewlyRegistered = false;
      _searchController.clear();
      _reasonController.clear();
      _selectedCommonReason = null;
      _resultEntry = null;
      _error = null;
    });
  }

  Future<void> _submitCheckIn() async {
    final repo = context.read<ClinicApi>();
    final actor = context.read<AuthSession>().currentUser?.name ?? 'Secretary';
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Please enter or select a reason for visit.');
      return;
    }
    try {
      final result = await repo.checkIn(
        existingPatient: _isNewlyRegistered ? null : _confirmedPatient,
        newlyRegisteredPatient: _isNewlyRegistered ? _confirmedPatient : null,
        reasonForVisit: reason,
        actor: actor,
      );
      if (!mounted) return;
      setState(() {
        _resultEntry = result.queueEntry;
        _stage = _Stage.done;
        _error = null;
      });
    } on DuplicateOperationException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ClinicAppBar(
        title: 'Check In Patient',
        actions: [
          if (_stage != _Stage.chooseType && _stage != _Stage.done)
            TextButton(onPressed: _reset, child: const Text('Start over')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _buildStage(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case _Stage.chooseType:
        return _ChooseTypeStep(
          onExisting: () => setState(() => _stage = _Stage.searchExisting),
          onNew: () => setState(() => _stage = _Stage.registerNew),
        );
      case _Stage.searchExisting:
        return _SearchExistingStep(
          controller: _searchController,
          onSelect: (p) => setState(() {
            _pendingExistingPatient = p;
            _stage = _Stage.confirmExisting;
          }),
          onRegisterInstead: () => setState(() => _stage = _Stage.registerNew),
        );
      case _Stage.confirmExisting:
        return _ConfirmExistingStep(
          patient: _pendingExistingPatient!,
          onBack: () => setState(() => _stage = _Stage.searchExisting),
          onConfirm: () => setState(() {
            _confirmedPatient = _pendingExistingPatient;
            _isNewlyRegistered = false;
            _stage = _Stage.reasonForVisit;
          }),
        );
      case _Stage.registerNew:
        return _RegisterNewStep(
          onBack: () => setState(() => _stage = _Stage.chooseType),
          onRegistered: (p) => setState(() {
            _confirmedPatient = p;
            _isNewlyRegistered = true;
            _stage = _Stage.reasonForVisit;
          }),
        );
      case _Stage.reasonForVisit:
        return _ReasonForVisitStep(
          patient: _confirmedPatient!,
          isNew: _isNewlyRegistered,
          reasonController: _reasonController,
          selectedCommon: _selectedCommonReason,
          onSelectCommon: (r) => setState(() {
            _selectedCommonReason = r;
            _reasonController.text = r == 'Other' ? '' : r;
          }),
          error: _error,
          onSubmit: _submitCheckIn,
        );
      case _Stage.done:
        return _DoneStep(
          entry: _resultEntry!,
          patient: _confirmedPatient!,
          onCheckInAnother: _reset,
          onDoneReturn: () => Navigator.of(context).pop(),
        );
    }
  }
}

class _ChooseTypeStep extends StatelessWidget {
  const _ChooseTypeStep({required this.onExisting, required this.onNew});
  final VoidCallback onExisting;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text('Existing Patient?', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        _BigChoiceButton(
          icon: Icons.search,
          label: 'Search Existing Patient',
          onTap: onExisting,
        ),
        const SizedBox(height: 16),
        _BigChoiceButton(
          icon: Icons.person_add_alt_1,
          label: 'Register New Patient',
          onTap: onNew,
          filled: false,
        ),
      ],
    );
  }
}

class _BigChoiceButton extends StatelessWidget {
  const _BigChoiceButton({required this.icon, required this.label, required this.onTap, this.filled = true});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
    return filled
        ? FilledButton(onPressed: onTap, child: child)
        : OutlinedButton(onPressed: onTap, child: child);
  }
}

class _SearchExistingStep extends StatefulWidget {
  const _SearchExistingStep({required this.controller, required this.onSelect, required this.onRegisterInstead});
  final TextEditingController controller;
  final ValueChanged<Patient> onSelect;
  final VoidCallback onRegisterInstead;

  @override
  State<_SearchExistingStep> createState() => _SearchExistingStepState();
}

class _SearchExistingStepState extends State<_SearchExistingStep> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicApi>();
    final query = widget.controller.text;
    final results = repo.searchPatients(query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Search Existing Patient', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        TextField(
          controller: widget.controller,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Patient name, patient ID, guardian name, or contact number',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (query.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Start typing to search for a patient.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else if (results.isEmpty)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No matching patients found.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              OutlinedButton.icon(
                onPressed: widget.onRegisterInstead,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Register New Patient Instead'),
              ),
            ],
          )
        else
          ...results.map(
            (p) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: PatientAvatar(p.initials),
                title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p.patientNumber} · ${p.ageDisplay} · Guardian: ${p.guardianName}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onSelect(p),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfirmExistingStep extends StatelessWidget {
  const _ConfirmExistingStep({required this.patient, required this.onBack, required this.onConfirm});
  final Patient patient;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Confirm Patient', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  PatientAvatar(patient.initials, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(patient.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Text(patient.patientNumber),
                      ],
                    ),
                  ),
                ]),
                const Divider(height: 32),
                _InfoRow(label: 'Birthdate', value: '${Formatters.shortDate(patient.birthdate)} (${patient.ageDisplay})'),
                _InfoRow(label: 'Sex', value: patient.sex.label),
                _InfoRow(label: 'Parent/Guardian', value: patient.guardianName),
                _InfoRow(label: 'Phone', value: patient.guardianContact),
                _InfoRow(label: 'Address', value: patient.address),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: onBack, child: const Text('Back to Search'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(onPressed: onConfirm, child: const Text('Confirm Patient')),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _RegisterNewStep extends StatefulWidget {
  const _RegisterNewStep({required this.onBack, required this.onRegistered});
  final VoidCallback onBack;
  final ValueChanged<Patient> onRegistered;

  @override
  State<_RegisterNewStep> createState() => _RegisterNewStepState();
}

class _RegisterNewStepState extends State<_RegisterNewStep> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _address = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianContact = TextEditingController();
  DateTime? _birthdate;
  Sex _sex = Sex.male;
  List<Patient> _duplicates = const [];

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _address.dispose();
    _guardianName.dispose();
    _guardianContact.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 1),
      firstDate: DateTime(now.year - 21),
      lastDate: now,
      helpText: 'Select Birthdate',
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  void _checkDuplicates() {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty || _birthdate == null) {
      setState(() => _duplicates = const []);
      return;
    }
    final repo = context.read<ClinicApi>();
    setState(() {
      _duplicates = repo.findPotentialDuplicates(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        birthdate: _birthdate!,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _birthdate == null) {
      if (_birthdate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a birthdate.')),
        );
      }
      return;
    }
    final repo = context.read<ClinicApi>();
    final actor = context.read<AuthSession>().currentUser?.name ?? 'Secretary';
    final patient = await repo.registerPatient(
      firstName: _first.text.trim(),
      middleName: _middle.text.trim(),
      lastName: _last.text.trim(),
      birthdate: _birthdate!,
      sex: _sex,
      address: _address.text.trim(),
      guardianName: _guardianName.text.trim(),
      guardianContact: _guardianContact.text.trim(),
      actor: actor,
    );
    if (!mounted) return;
    widget.onRegistered(patient);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Register New Patient', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (_duplicates.isNotEmpty)
            Card(
              color: Colors.amber.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'A patient with the same name and birthdate already exists (${_duplicates.first.patientNumber}). '
                        'Consider searching for the existing patient instead.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                onChanged: (_) => _checkDuplicates(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _middle,
                decoration: const InputDecoration(labelText: 'Middle name'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _last,
            decoration: const InputDecoration(labelText: 'Last name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            onChanged: (_) => _checkDuplicates(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _pickBirthdate();
                  _checkDuplicates();
                },
                icon: const Icon(Icons.cake_outlined),
                label: Text(_birthdate == null ? 'Select Birthdate' : Formatters.shortDate(_birthdate!)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<Sex>(
                value: _sex,
                decoration: const InputDecoration(labelText: 'Sex'),
                items: Sex.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                onChanged: (v) => setState(() => _sex = v ?? _sex),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _guardianName,
            decoration: const InputDecoration(labelText: 'Parent/Guardian name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _guardianContact,
            decoration: const InputDecoration(labelText: 'Contact number'),
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: widget.onBack, child: const Text('Back'))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: _submit, child: const Text('Continue'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonForVisitStep extends StatelessWidget {
  const _ReasonForVisitStep({
    required this.patient,
    required this.isNew,
    required this.reasonController,
    required this.selectedCommon,
    required this.onSelectCommon,
    required this.error,
    required this.onSubmit,
  });

  final Patient patient;
  final bool isNew;
  final TextEditingController reasonController;
  final String? selectedCommon;
  final ValueChanged<String> onSelectCommon;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PatientAvatar(patient.initials),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(isNew ? 'New patient' : patient.patientNumber,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Reason for Visit', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonReasons.map((r) {
            final selected = selectedCommon == r;
            return ChoiceChip(
              label: Text(r),
              selected: selected,
              onSelected: (_) => onSelectCommon(r),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Describe the reason for this visit',
            errorText: error,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onSubmit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text('Complete Check-In', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.entry,
    required this.patient,
    required this.onCheckInAnother,
    required this.onDoneReturn,
  });

  final QueueEntry entry;
  final Patient patient;
  final VoidCallback onCheckInAnother;
  final VoidCallback onDoneReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, color: scheme.primary, size: 64),
        const SizedBox(height: 16),
        Text('Checked In', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(patient.fullName, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text('QUEUE NUMBER', style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(
                entry.displayNumber,
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w900, fontSize: 48),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Arrived ${Formatters.time(entry.checkedInAt)}', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: onDoneReturn, child: const Text('Back to Dashboard'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(onPressed: onCheckInAnother, child: const Text('Check In Another Patient')),
            ),
          ],
        ),
      ],
    );
  }
}
