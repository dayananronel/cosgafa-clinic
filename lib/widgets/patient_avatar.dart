import 'package:flutter/material.dart';

/// Shows initials only, never a full patient name graphic — used
/// anywhere a lightweight identity marker is enough (spec 10.4: staff
/// queue lists may show "patient initials or private identifier").
class PatientAvatar extends StatelessWidget {
  const PatientAvatar(this.initials, {super.key, this.size = 44});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
