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
import 'activity_timeline_page.dart';
import 'alerts_page.dart';
import 'auth/landing_page.dart';
import 'caregiver/medicine_schedule_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    DatabaseService.refreshDashboard();
    DatabaseService.fetchActivityHistory();
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: SovaColors.charcoal)),
        content: const Text('Are you sure you want to logout?',
            style: TextStyle(color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.black38)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              DatabaseService.stopAlertPolling();
              AppState.userId.value = null;
              AppState.caregiverId.value = null;
              AppState.patientId.value = null;
              AppState.currentUser.value = null;
              AppState.userRole.value = null;
              AppState.caregiverName.value = 'User';
              AppState.isLoggedIn.value = false;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LandingPage()),
                (_) => false,
              );
            },
            child: const Text('Logout',
                style: TextStyle(
                    color: SovaColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showCreatePatientDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create Patient',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: SovaColors.charcoal)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Patient Name',
                hintText: 'Enter patient name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.black38)),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              try {
                final relativeId = AppState.userId.value;
                if (relativeId == null) return;
                final patientData = await ApiService.createPatient(
                  relativeId: relativeId,
                  name: name,
                );
                AppState.patientId.value = patientData['id'].toString();
                AppState.patientName.value =
                    patientData['name'] as String? ?? '';
                DatabaseService.refreshDashboard();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to create patient: $e')),
                );
              }
            },
            child: const Text('Create',
                style: TextStyle(
                    color: SovaColors.success, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AlertType>(
      valueListenable: AppState.alertStatus,
      builder: (context, alert, _) {
        return ValueListenableBuilder<int>(
          valueListenable: AppState.heartRate,
          builder: (context, bpm, _) {
            final isEmergency =
                alert != AlertType.none || bpm == 0 || bpm > 120;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _showLogoutDialog,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: SovaColors.softGlass,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.logout_rounded,
                                  color: SovaColors.charcoal, size: 18),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SAVA',
                                  style: SovaTheme.textTheme.labelMedium),
                              const SizedBox(height: 4),
                              ValueListenableBuilder<String>(
                                valueListenable: AppState.caregiverName,
                                builder: (_, name, __) => Text(
                                  'Hi, $name',
                                  style: SovaTheme.textTheme.displayMedium
                                      ?.copyWith(fontSize: 26),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(children: [
                        IconButton(
                          onPressed: () => ApiService.simulateHeartRate(
                              bpm == 72 ? 145 : 72),
                          icon: const Icon(Icons.speed_rounded,
                              color: SovaColors.sage),
                        ),
                        IconButton(
                          onPressed: () => ApiService.processAiDetection(alert),
                          icon: const Icon(Icons.science_rounded,
                              color: SovaColors.sage),
                        ),
                        // ── Alerts Bell ─────────────────────────────────
                        _AlertBell(),
                      ]),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── ECG Monitor ───────────────────────────────────────────
                  InteractiveBentoCard(
                    onTap: () {},
                    color: const Color(0xFF0A0D12),
                    height: 140,
                    child: Stack(children: [
                      const Positioned.fill(child: MonitorGridPainterWidget()),
                      Positioned.fill(
                          child: ECGWaveWidget(
                              bpm: bpm, isEmergency: isEmergency)),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEmergency ? 'CRITICAL' : 'LIVE ECG',
                              style: TextStyle(
                                color: isEmergency
                                    ? SovaColors.danger.withValues(alpha: 0.5)
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
                                  bpm == 0 ? '00' : '$bpm',
                                  style: TextStyle(
                                    color: isEmergency
                                        ? SovaColors.danger
                                        : SovaColors.success,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text('BPM',
                                    style: TextStyle(
                                        color: Colors.white24, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ).animate().fadeIn(),

                  const SizedBox(height: 16),

                  // ── Alert Status Banner ────────────────────────────────────
                  InteractiveBentoCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AlertsPage()),
                    ),
                    color: isEmergency ? SovaColors.danger : Colors.white,
                    height: 90,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        Icon(
                          isEmergency
                              ? Icons.warning_amber_rounded
                              : Icons.shield_moon_outlined,
                          color:
                              isEmergency ? Colors.white : SovaColors.success,
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
                        Icon(Icons.chevron_right,
                            color:
                                isEmergency ? Colors.white54 : SovaColors.sage,
                            size: 18),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Activity Log Card (always visible) ────────────────────
                  ValueListenableBuilder<ActivityLog?>(
                    valueListenable: AppState.lastActivity,
                    builder: (_, log, __) {
                      final hasLog = log != null;
                      final color = hasLog
                          ? DatabaseService.getActivityColor(log.title)
                          : SovaColors.sensorNeutral;
                      final icon = log?.icon ?? Icons.hourglass_empty_rounded;
                      final title = log?.title ?? 'No Activity Yet';
                      final time = hasLog
                          ? (log.isFinished
                              ? 'Finished ${log.finishTime}'
                              : 'Undergoing')
                          : 'Waiting...';

                      return InteractiveBentoCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ActivityTimelinePage()),
                        ),
                        color: color,
                        height: 120,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(icon, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('LAST ACTIVITY',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1)),
                                  const SizedBox(height: 6),
                                  Text(title,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 2),
                                  Text(time,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: Colors.white54, size: 20),
                          ]),
                        ),
                      ).animate().fadeIn(delay: 200.ms);
                    },
                  ),

                  const SizedBox(height: 16),

                  // ── Next Medicine (pink) + Zone Status ────────────────────
                  Row(children: [
                    // Next Medicine
                    Expanded(
                      child: ValueListenableBuilder<List<Medication>>(
                        valueListenable: AppState.allMedications,
                        builder: (_, meds, __) {
                          Medication? next;
                          for (final m in meds) {
                            if (!m.isTaken) {
                              next = m;
                              break;
                            }
                          }
                          return InteractiveBentoCard(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const MedicineSchedulePage()),
                            ),
                            color: const Color(0xFFE83E8C),
                            height: 130,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.medication_liquid_outlined,
                                      color: Colors.white, size: 24),
                                  const Spacer(),
                                  const Text('NEXT MEDICINE',
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1)),
                                  const SizedBox(height: 4),
                                  Text(
                                    next?.name ?? '✓ All taken',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (next != null)
                                    Text(next.time,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Zone Status
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: AppState.patientName,
                        builder: (_, name, __) => InteractiveBentoCard(
                          onTap: () {},
                          color: SovaColors.sage,
                          height: 130,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on_rounded,
                                    color: Colors.white, size: 24),
                                const Spacer(),
                                Text(name,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const Text('is in',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 11)),
                                const Text('Kitchen',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]).animate().fadeIn(delay: 300.ms),

                  const SizedBox(height: 16),

                  // ── Camera View + Add Relative + Create Patient ─────────────────
                  Row(children: [
                    Expanded(
                      child: InteractiveBentoCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const VisionPage()),
                        ),
                        color: SovaColors.navy,
                        height: 120,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_rounded,
                                  color: Colors.white, size: 28),
                              SizedBox(height: 8),
                              Text('Camera View',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InteractiveBentoCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AddRelativePage()),
                        ),
                        color: const Color(0xFF2D2D2D),
                        height: 120,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.face_retouching_natural,
                                  color: Colors.white, size: 28),
                              SizedBox(height: 8),
                              Text('Add Relative',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InteractiveBentoCard(
                        onTap: () => _showCreatePatientDialog(),
                        color: const Color(0xFF4CAF50),
                        height: 120,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_add_rounded,
                                  color: Colors.white, size: 28),
                              SizedBox(height: 8),
                              Text('Create Patient',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]).animate().fadeIn(delay: 380.ms),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Alert Bell Widget ─────────────────────────────────────────────────────────

class _AlertBell extends StatelessWidget {
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

// ── ECG Widgets (unchanged) ───────────────────────────────────────────────────

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
