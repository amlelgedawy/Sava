import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../app_state.dart';
import '../screens/alerts_page.dart';

// ── Alert Bell Widget ─────────────────────────────────────────────────────────

class AlertBell extends StatelessWidget {
  const AlertBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AlertEntry>>(
      valueListenable: AppState.alertHistory,
      builder: (_, alerts, __) => Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsPage()),
            ),
            icon: const Icon(Icons.notifications_outlined,
                color: SovaColors.sage),
          ),
          if (alerts.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                    color: SovaColors.coral, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    alerts.length > 9 ? '9+' : '${alerts.length}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── ECG Widgets ───────────────────────────────────────────────────────────────

class ECGWaveWidget extends StatefulWidget {
  final int bpm;
  final bool isEmergency;
  const ECGWaveWidget(
      {super.key, required this.bpm, required this.isEmergency});

  @override
  State<ECGWaveWidget> createState() => _ECGWaveWidgetState();
}

class _ECGWaveWidgetState extends State<ECGWaveWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
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
      builder: (_, __) => CustomPaint(
        painter: ECGLinePainter(
          progress: _controller.value,
          bpm: widget.bpm,
          color: widget.isEmergency ? SovaColors.danger : SovaColors.success,
        ),
      ),
    );
  }
}

class ECGLinePainter extends CustomPainter {
  final double progress;
  final int bpm;
  final Color color;

  ECGLinePainter(
      {required this.progress, required this.bpm, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 4.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    Path path = Path();
    double width = size.width;
    double height = size.height;
    double midY = height / 2 + 20;
    path.moveTo(0, midY);
    double spikeFrequency = bpm / 22;
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
  bool shouldRepaint(covariant ECGLinePainter old) => true;
}

class MonitorGridPainterWidget extends StatelessWidget {
  const MonitorGridPainterWidget({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 25)
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += 25)
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
