import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class PatientListPage extends StatefulWidget {
  const PatientListPage({super.key});
  @override
  State<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends State<PatientListPage> {
  List<Map<String, dynamic>> _patients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = AppState.caregiverId.value;
    if (id == null) return;
    try {
      final list = await ApiService.getPatientsForCaregiver(id);
      if (mounted)
        setState(() => _patients = list.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CAREGIVER', style: SovaTheme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Text('My Patients', style: SovaTheme.textTheme.displayMedium),
              Text(
                '${_patients.length}/4 patients assigned',
                style: TextStyle(color: SovaColors.sage, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _patients.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        itemCount: _patients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (_, i) =>
                            _PatientCard(patient: _patients[i])
                                .animate()
                                .fadeIn(delay: (i * 80).ms)
                                .slideY(begin: 0.08),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: SovaColors.sensorNeutral),
          const SizedBox(height: 16),
          Text('No patients assigned yet',
              style: TextStyle(
                  color: SovaColors.sage,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Patients will appear here once a relative assigns you.',
              style: TextStyle(color: SovaColors.sage, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> patient;
  const _PatientCard({required this.patient});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AlertType>(
      valueListenable: AppState.alertStatus,
      builder: (_, alert, __) {
        final hasAlert = alert != AlertType.none;
        final statusColor = hasAlert ? SovaColors.coral : SovaColors.success;
        final statusLabel = hasAlert ? 'Alert' : 'Stable';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: hasAlert
                  ? SovaColors.coral.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SovaColors.navy.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: SovaColors.navy),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient['name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: SovaColors.charcoal)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: AppState.heartRate,
                    builder: (_, bpm, __) => Text(
                      '$bpm BPM',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: SovaColors.charcoal),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<String?>(
                    valueListenable: AppState.patientId,
                    builder: (_, currentPatientId, __) {
                      final isMonitoring =
                          currentPatientId == patient['id'].toString();
                      if (isMonitoring) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: SovaColors.sensorNeutral,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Monitoring',
                              style: TextStyle(
                                  color: Colors.black38,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        );
                      }
                      return GestureDetector(
                        onTap: () {
                          AppState.patientId.value = patient['id'].toString();
                          AppState.patientName.value =
                              patient['name'] as String? ?? '';
                          AppState.currentNavIndex.value = 0;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: SovaColors.navy,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Monitor',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
