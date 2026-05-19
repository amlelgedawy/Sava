import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../widgets/interactive_card.dart';
import '../../widgets/dashboard_widgets.dart';
import '../../app_state.dart';
import '../../models/patient_models.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';
import '../vision_page.dart';
import '../auth/landing_page.dart';

class CaregiverHomePage extends StatefulWidget {
  const CaregiverHomePage({super.key});
  @override
  State<CaregiverHomePage> createState() => _CaregiverHomePageState();
}

class _CaregiverHomePageState extends State<CaregiverHomePage> {
  @override
  void initState() {
    super.initState();
    DatabaseService.refreshDashboard();
    DatabaseService.fetchActivityHistory();
  }

  bool get _hasActivePatient =>
      AppState.patientId.value != null && AppState.patientId.value!.isNotEmpty;

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
              AppState.patientName.value = '';
              AppState.currentUser.value = null;
              AppState.userRole.value = null;
              AppState.caregiverName.value = 'User';
              AppState.isLoggedIn.value = false;
              AppState.currentNavIndex.value = 0;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LandingPage()),
                    (_) => false,
                  );
                }
              });
            },
            child: const Text('Logout',
                style: TextStyle(
                    color: SovaColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppState.patientId,
      builder: (context, _, __) {
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                        const AlertBell(),
                      ]),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Metrics Section (only show if patient exists) ──────
                  if (_hasActivePatient) ...[
                    // ── ECG Monitor ───────────────────────────────────────
                    InteractiveBentoCard(
                      onTap: () {},
                      color: const Color(0xFF0A0D12),
                      height: 140,
                      child: Stack(children: [
                        const Positioned.fill(
                            child: MonitorGridPainterWidget()),
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

                    // ── Alert Status Banner ────────────────────────────────
                    InteractiveBentoCard(
                      onTap: () => AppState.currentNavIndex.value = 5,
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
                              color: isEmergency
                                  ? Colors.white54
                                  : SovaColors.sage,
                              size: 18),
                        ]),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Activity Log Card ──────────────────────────────────
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
                          onTap: () => AppState.currentNavIndex.value = 3,
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
                                child:
                                    Icon(icon, color: Colors.white, size: 28),
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
                                            color: Colors.white70,
                                            fontSize: 12)),
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

                    // ── Next Medicine + Zone Status ────────────────────────
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
                              onTap: () => AppState.currentNavIndex.value = 4,
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

                    // ── Camera View ───────────────────────────────────────
                    InteractiveBentoCard(
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

                    const SizedBox(height: 16),

                    // ── Activity Timeline Card ─────────────────────────────
                    InteractiveBentoCard(
                      onTap: () => AppState.currentNavIndex.value = 3,
                      color: const Color(0xFF8DA399),
                      height: 120,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.timeline_rounded,
                                color: Colors.white, size: 28),
                            SizedBox(height: 8),
                            Text('Activity Timeline',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── Empty State when no patient ───────────────────────────
                  if (!_hasActivePatient)
                    Container(
                      padding: const EdgeInsets.all(48),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_rounded,
                                size: 64, color: SovaColors.sensorNeutral),
                            const SizedBox(height: 24),
                            Text('No Patient Assigned',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: SovaColors.charcoal)),
                            const SizedBox(height: 12),
                            Text(
                                'Wait for a relative to send you a contract request.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14, color: SovaColors.sage)),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            );
              },
            );
          },
        );
      },
    );
  }
}
