import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/clinic_api.dart';
import '../../services/exceptions.dart';
import '../../utils/formatters.dart';
import '../../widgets/clinic_logo.dart';

const _commonReasons = ['Follow-up', 'Fever', 'Cough/Cold', 'Vaccination', 'Other'];

/// Guest Mode: lets a patient/guardian register and check themselves into
/// the queue from an unauthenticated device (e.g. a waiting-room tablet),
/// so the secretary doesn't have to type in every patient's details by
/// hand. Reachable from the login screen without signing in — see
/// [ClinicApi.guestCheckIn].
///
/// New patients only: unlike the secretary's Check-In screen there is no
/// "existing patient" search here, since exposing patient search to an
/// unauthenticated device would let anyone browse other families' names,
/// addresses, and contact numbers.
class GuestCheckInScreen extends StatefulWidget {
  const GuestCheckInScreen({super.key});

  @override
  State<GuestCheckInScreen> createState() => _GuestCheckInScreenState();
}

class _GuestCheckInScreenState extends State<GuestCheckInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _address = TextEditingController();
  final _guardianName = TextEditingController();
  final _guardianContact = TextEditingController();
  final _reasonController = TextEditingController();
  DateTime? _birthdate;
  Sex _sex = Sex.male;
  String? _selectedCommonReason;
  bool _submitting = false;
  String? _error;

  ({Patient patient, QueueEntry queueEntry})? _result;

  @override
  void dispose() {
    _first.dispose();
    _middle.dispose();
    _last.dispose();
    _address.dispose();
    _guardianName.dispose();
    _guardianContact.dispose();
    _reasonController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _birthdate == null) {
      if (_birthdate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a birthdate.')),
        );
      }
      return;
    }
    if (_reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter or select a reason for visit.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repo = context.read<ClinicApi>();
      final result = await repo.guestCheckIn(
        firstName: _first.text.trim(),
        middleName: _middle.text.trim(),
        lastName: _last.text.trim(),
        birthdate: _birthdate!,
        sex: _sex,
        address: _address.text.trim(),
        guardianName: _guardianName.text.trim(),
        guardianContact: _guardianContact.text.trim(),
        reasonForVisit: _reasonController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _result = (patient: result.patient, queueEntry: result.queueEntry);
        _submitting = false;
      });
    } on DuplicateOperationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Please ask the front desk for help.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guest Check-In'),
        automaticallyImplyLeading: result == null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: result != null ? _DoneView(patient: result.patient, entry: result.queueEntry) : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: ClinicLogo(size: 64)),
          const SizedBox(height: 16),
          Text(
            'Check yourself in',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Fill in your details below and you\'ll get a queue number right away — no need to wait for the front desk.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _first,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickBirthdate,
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
          const SizedBox(height: 24),
          Text('Reason for Visit', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonReasons.map((r) {
              final selected = _selectedCommonReason == r;
              return ChoiceChip(
                label: Text(r),
                selected: selected,
                onSelected: (_) => setState(() {
                  _selectedCommonReason = r;
                  _reasonController.text = r == 'Other' ? '' : r;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Describe the reason for this visit',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _submitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Check Me In', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          Text(
            'If you\'ve visited before, please check in at the front desk instead so we can find your existing record.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.patient, required this.entry});

  final Patient patient;
  final QueueEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, color: scheme.primary, size: 64),
        const SizedBox(height: 16),
        Text('You\'re Checked In', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
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
              Text('YOUR QUEUE NUMBER', style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(
                entry.displayNumber,
                style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w900, fontSize: 48),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please have a seat — you\'ll be called for intake by number.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
