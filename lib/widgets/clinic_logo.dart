import 'package:flutter/material.dart';

/// The clinic's mark: a coral circle with a pale heart-and-cross, on a
/// light-blue tile. Rendered from `assets/branding/logo.png`.
class ClinicLogo extends StatelessWidget {
  const ClinicLogo({super.key, this.size = 72, this.borderRadius});

  final double size;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
