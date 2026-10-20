import 'package:flutter/material.dart';
import '../../state/emergency_controller.dart';
import '../../models/emergency.dart';
import '../theme.dart';

class EmergencyCountdownOverlay extends StatelessWidget {
  const EmergencyCountdownOverlay({required this.emergency, super.key});

  final EmergencyController emergency;

  @override
  Widget build(BuildContext context) {
    if (emergency.state != EmergencyState.countdown) {
      return const SizedBox.shrink();
    }

    final double progress = emergency.seconds / emergency.countdownSeconds;

    return Container(
      color: Colors.black.withOpacity(0.92),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Warning Pulse Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: SafeHelmTheme.emergencyRed.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: SafeHelmTheme.emergencyRed),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: SafeHelmTheme.emergencyRed, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${emergency.kind ?? "EMERGENCY"} DETECTED',
                    style: const TextStyle(
                      color: SafeHelmTheme.emergencyRed,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Countdown Circular Gauge
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 14,
                      backgroundColor: SafeHelmTheme.surfaceHighlight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        SafeHelmTheme.emergencyRed,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${emergency.seconds}',
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w900,
                          color: SafeHelmTheme.textBright,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'SECONDS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SafeHelmTheme.textMuted,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 36),
            const Text(
              'Autonomous Emergency Dispatch',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: SafeHelmTheme.textBright,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'High-accuracy GPS location and autonomous SMS alert will be broadcast to all designated emergency contacts upon countdown expiry.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: SafeHelmTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ),
            const Spacer(),

            // Abort Button
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: SafeHelmTheme.successGreen,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: emergency.cancel,
                icon: const Icon(Icons.check_circle_outline, size: 28),
                label: const Text(
                  "I'M OK — CANCEL ALERT",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
