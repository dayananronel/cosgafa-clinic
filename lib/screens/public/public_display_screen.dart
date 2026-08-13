import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/clinic_repository.dart';

/// Spec 10.6 / 12: Public Queue Display. Shows only queue numbers — never
/// patient names, addresses, phone numbers, medical history, diagnosis,
/// reason for visit, or vital signs (spec 10.6's explicit "never
/// display" list). Safe to project on a TV in the waiting room.
class PublicDisplayScreen extends StatelessWidget {
  const PublicDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicRepository>();
    final current = repo.currentlyServingEntry;
    final next = repo.doctorQueueSorted.take(3).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'NOW SERVING',
                      style: TextStyle(
                        color: Color(0xFF8FA3C4),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      current != null ? current.displayNumber : '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (current != null)
                      const Text(
                        'Please proceed to the doctor’s room',
                        style: TextStyle(color: Color(0xFFB8C4DA), fontSize: 18),
                      )
                    else
                      const Text(
                        'Please wait for your number to be called',
                        style: TextStyle(color: Color(0xFFB8C4DA), fontSize: 18),
                      ),
                    const SizedBox(height: 56),
                    Container(height: 1, color: Colors.white24),
                    const SizedBox(height: 40),
                    const Text(
                      'NEXT',
                      style: TextStyle(
                        color: Color(0xFF8FA3C4),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    next.isEmpty
                        ? const Text('—', style: TextStyle(color: Colors.white54, fontSize: 32))
                        : Wrap(
                            spacing: 24,
                            runSpacing: 16,
                            alignment: WrapAlignment.center,
                            children: next
                                .map((e) => Text(
                                      e.displayNumber,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 40,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ))
                                .toList(),
                          ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white54),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
