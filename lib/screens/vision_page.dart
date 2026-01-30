import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';

class VisionPage extends StatelessWidget {
  const VisionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // No Bottom Nav Bar here because we are using Navigator.push
      body: ValueListenableBuilder<AlertType>(
        valueListenable: AppState.alertStatus,
        builder: (context, alert, child) {
          bool isEmergency = alert != AlertType.none;

          return Stack(
            children: [
              // 1. LIVE FEED
              Positioned.fill(
                child: Container(
                  color: SovaColors.charcoal,
                  child: const Center(
                    child: Icon(
                      Icons.camera_indoor_rounded,
                      color: Colors.white10,
                      size: 100,
                    ),
                  ),
                ),
              ),

              // 2. LIVE AR SQUARES
              if (alert == AlertType.fall)
                _buildARBox(
                  top: 450,
                  left: 80,
                  size: 220,
                  label: "CONFIRMED FALL",
                  isSafe: false,
                ),
              if (alert == AlertType.sharpObject)
                _buildARBox(
                  top: 400,
                  left: 150,
                  size: 120,
                  label: "UNSAFE: Knife",
                  isSafe: false,
                ),
              if (alert == AlertType.unknownPerson)
                _buildARBox(
                  top: 200,
                  left: 100,
                  size: 150,
                  label: "UNKNOWN PERSON",
                  isSafe: false,
                ),
              if (alert == AlertType.wandering)
                _buildARBox(
                  top: 300,
                  left: 50,
                  size: 180,
                  label: "WANDERING DETECTED",
                  isSafe: false,
                ),
              if (alert == AlertType.bathroomTimeout)
                _buildARBox(
                  top: 350,
                  left: 120,
                  size: 140,
                  label: "BATHROOM TIMEOUT",
                  isSafe: false,
                ),

              if (alert == AlertType.none) ...[
                _buildARBox(
                  top: 180,
                  left: 50,
                  size: 160,
                  label: "Relative: John",
                  isSafe: true,
                ),
                _buildARBox(
                  top: 450,
                  left: 150,
                  size: 100,
                  label: "Object: Glass",
                  isSafe: true,
                ),
              ],

              // 3. HUD OVERLAYS
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // THE CLOSE BUTTON (Goes back to Home)
                          _glassButton(
                            Icons.close,
                            () => Navigator.pop(context),
                          ),
                          _statusTag(isEmergency),
                        ],
                      ),
                      const Spacer(),

                      // AI STATUS PANEL
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            _aiRow(
                              Icons.sensors_rounded,
                              "System",
                              isEmergency ? "EMERGENCY" : "Stable",
                            ),
                            const Divider(color: Colors.white10, height: 20),
                            _aiRow(
                              Icons.remove_red_eye_outlined,
                              "AI Status",
                              isEmergency ? "Danger Confirmed" : "Monitoring",
                              color: isEmergency ? SovaColors.danger : null,
                            ),
                          ],
                        ),
                      ).animate().slideY(begin: 0.2),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // (Helper widgets remain the same)
  Widget _buildARBox({
    required double top,
    required double left,
    required double size,
    required String label,
    required bool isSafe,
  }) {
    final color = isSafe ? SovaColors.success : SovaColors.danger;
    return Positioned(
      top: top,
      left: left,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds);
  }

  Widget _glassButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _statusTag(bool isEmergency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isEmergency ? SovaColors.danger : SovaColors.success,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isEmergency ? "ALERT ACTIVE" : "SYSTEM SECURE",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _aiRow(IconData icon, String t, String v, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 18),
        const SizedBox(width: 12),
        Text(t, style: const TextStyle(color: Colors.white70)),
        const Spacer(),
        Text(
          v,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
