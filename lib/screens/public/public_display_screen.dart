import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/clinic_api.dart';

/// Spec 10.6 / 12: Public Queue Display. Shows only queue numbers — never
/// patient names, addresses, phone numbers, medical history, diagnosis,
/// reason for visit, or vital signs (spec 10.6's explicit "never
/// display" list). Safe to project on a TV in the waiting room — meant
/// to be viewed by nobody signed in, so it triggers its own
/// unauthenticated-safe data fetch (see [ClinicApi.ensurePublicQueueVisible])
/// rather than depending on a staff sign-in having already populated the
/// cache, the way every staff-facing screen does.
class PublicDisplayScreen extends StatefulWidget {
  const PublicDisplayScreen({super.key});

  @override
  State<PublicDisplayScreen> createState() => _PublicDisplayScreenState();
}

class _PublicDisplayScreenState extends State<PublicDisplayScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ClinicApi>().ensurePublicQueueVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<ClinicApi>();
    final current = repo.currentlyServingEntry;
    final next = repo.doctorQueueSorted.take(3).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Scales the whole display by available width so it
                      // reads well on a phone, a tablet, or a waiting-room
                      // TV without ever overflowing horizontally.
                      final w = constraints.maxWidth;
                      final labelSize = (w * 0.052).clamp(14.0, 22.0);
                      final numberSize = (w * 0.30).clamp(56.0, 120.0);
                      final nextLabelSize = (w * 0.045).clamp(12.0, 18.0);
                      final nextNumberSize = (w * 0.11).clamp(28.0, 40.0);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'NOW SERVING',
                              style: TextStyle(
                                color: const Color(0xFF8FA3C4),
                                fontSize: labelSize,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FittedBox(
                              child: Text(
                                current != null ? current.displayNumber : '—',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: numberSize,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              current != null
                                  ? 'Please proceed to the doctor’s room'
                                  : 'Please wait for your number to be called',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: const Color(0xFFB8C4DA), fontSize: nextLabelSize + 2),
                            ),
                            const SizedBox(height: 56),
                            Container(height: 1, color: Colors.white24),
                            const SizedBox(height: 40),
                            Text(
                              'NEXT',
                              style: TextStyle(
                                color: const Color(0xFF8FA3C4),
                                fontSize: nextLabelSize,
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
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: nextNumberSize,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ))
                                        .toList(),
                                  ),
                          ],
                        ),
                      );
                    },
                  ),
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
