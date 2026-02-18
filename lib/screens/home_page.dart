import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../widgets/interactive_card.dart';
import '../app_state.dart';
import '../models/patient_models.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import 'vision_page.dart';
import 'add_relative_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: AppState.alertStatus,
      builder: (context, alert, child) {
        return ValueListenableBuilder(
          valueListenable: AppState.heartRate,
          builder: (context, bpm, child) {
            bool isEmergency = alert != AlertType.none || bpm == 0 || bpm > 120;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("SAVA", style: SovaTheme.textTheme.labelMedium),
                          const SizedBox(height: 4),
                          // ✅ CHANGED: reads from AppState not DatabaseService
                          ValueListenableBuilder<String>(
                            valueListenable: AppState.caregiverName,
                            builder: (context, caregiverName, _) {
                              return Text(
                                "Hi, $caregiverName",
                                style: SovaTheme.textTheme.displayMedium
                                    ?.copyWith(fontSize: 26),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => ApiService.simulateHeartRate(
                              bpm == 72 ? 145 : 72,
                            ),
                            icon: const Icon(
                              Icons.speed_rounded,
                              color: SovaColors.sage,
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                ApiService.processAiDetection(alert),
                            icon: const Icon(
                              Icons.science_rounded,
                              color: SovaColors.sage,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  InteractiveBentoCard(
                    onTap: () {},
                    color: const Color(0xFF0A0D12),
                    height: 140,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: MonitorGridPainterWidget(),
                        ),
                        Positioned.fill(
                          child: ECGWaveWidget(
                            bpm: bpm,
                            isEmergency: isEmergency,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEmergency ? "CRITICAL" : "LIVE ECG",
                                style: TextStyle(
                                  color: isEmergency
                                      ? SovaColors.danger.withOpacity(0.5)
                                      : Colors.white24,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    bpm == 0 ? "00" : "$bpm",
                                    style: TextStyle(
                                      color: isEmergency
                                          ? SovaColors.danger
                                          : SovaColors.success,
                                      fontSize: 36,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "BPM",
                                    style: TextStyle(
                                      color: Colors.white24,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),
                  const SizedBox(height: 16),
                  InteractiveBentoCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VisionPage(),
                      ),
                    ),
                    color: isEmergency ? SovaColors.danger : Colors.white,
                    height: 90,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(
                            isEmergency
                                ? Icons.warning_amber_rounded
                                : Icons.shield_moon_outlined,
                            color: isEmergency
                                ? Colors.white
                                : SovaColors.success,
                            size: 28,
                          ).animate(target: isEmergency ? 1 : 0).shake(),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              AppState.alertMessage,
                              style: TextStyle(
                                color: isEmergency
                                    ? Colors.white
                                    : SovaColors.charcoal,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<ActivityLog?>(
                    valueListenable: AppState.lastActivity,
                    builder: (context, log, _) {
                      if (log == null) return const SizedBox();
                      return InteractiveBentoCard(
                        onTap: () => AppState.currentNavIndex.value = 1,
                        color: DatabaseService.getActivityColor(log.title),
                        height: 140,
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  log.icon,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Last Activity",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      log.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      log.isFinished
                                          ? "Finished ${log.finishTime}"
                                          : "Undergoing",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ).animate().fadeIn(delay: 200.ms);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // ── Camera Card ──────────────────────────────────
                      Expanded(
                        child: InteractiveBentoCard(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const VisionPage(),
                            ),
                          ),
                          color: SovaColors.navy,
                          height: 120,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.videocam_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Camera View",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Zone Card ────────────────────────────────────
                      Expanded(
                        child: InteractiveBentoCard(
                          onTap: () {},
                          color: SovaColors.sage,
                          height: 120,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                // ✅ CHANGED: reads from AppState not DatabaseService
                                ValueListenableBuilder<String>(
                                  valueListenable: AppState.patientName,
                                  builder: (context, patientName, _) {
                                    return Text(
                                      "$patientName\nKitchen",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Add Relative Card ────────────────────────────
                      Expanded(
                        child: InteractiveBentoCard(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AddRelativePage(),
                            ),
                          ),
                          color: const Color(0xFF2D2D2D),
                          height: 120,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.face_retouching_natural,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  "Add Relative",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 300.ms),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// Include Painters below... (UNCHANGED)
class ECGWaveWidget extends StatefulWidget {
  final int bpm;
  final bool isEmergency;
  const ECGWaveWidget({
    super.key,
    required this.bpm,
    required this.isEmergency,
  });
  @override
  State<ECGWaveWidget> createState() => _ECGWaveWidgetState();
}

class _ECGWaveWidgetState extends State<ECGWaveWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ECGLinePainter(
            progress: _controller.value,
            bpm: widget.bpm,
            color: widget.isEmergency ? SovaColors.danger : SovaColors.success,
          ),
        );
      },
    );
  }
}

class ECGLinePainter extends CustomPainter {
  final double progress;
  final int bpm;
  final Color color;
  ECGLinePainter({
    required this.progress,
    required this.bpm,
    required this.color,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    Path path = Path();
    double width = size.width;
    double height = size.height;
    double midY = height / 2 + 20;
    path.moveTo(0, midY);
    double spikeFrequency = (bpm / 22);
    for (double x = 0; x <= width; x++) {
      double relativeX = (x / width + progress) % 1.0;
      double y = midY;
      double pulseCycle = (relativeX * spikeFrequency) % 1.0;
      if (pulseCycle > 0.1 && pulseCycle < 0.18)
        y -= math.sin((pulseCycle - 0.1) / 0.08 * math.pi) * 6;
      else if (pulseCycle >= 0.2 && pulseCycle < 0.22)
        y += 4;
      else if (pulseCycle >= 0.22 && pulseCycle < 0.26)
        y -= math.sin(((pulseCycle - 0.22) / 0.04) * math.pi) * 48;
      else if (pulseCycle >= 0.26 && pulseCycle < 0.28)
        y += 6;
      else if (pulseCycle > 0.4 && pulseCycle < 0.55)
        y -= math.sin((pulseCycle - 0.4) / 0.15 * math.pi) * 10;
      if (x == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ECGLinePainter oldDelegate) => true;
}

class MonitorGridPainterWidget extends StatelessWidget {
  const MonitorGridPainterWidget({super.key});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 25) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 25) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
