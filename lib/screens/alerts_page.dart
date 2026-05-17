import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../theme.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    if (canPop) ...[
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: SovaColors.softGlass,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new,
                              color: SovaColors.charcoal, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Alerts",
                            style: SovaTheme.textTheme.displayMedium),
                        const SizedBox(height: 4),
                        const Text(
                          "All alerts from today",
                          style: TextStyle(color: Colors.black45, fontSize: 13),
                        ),
                      ],
                    ),
                  ]),
                  // Clear all button
                  ValueListenableBuilder<List<AlertEntry>>(
                    valueListenable: AppState.alertHistory,
                    builder: (context, alerts, _) {
                      if (alerts.isEmpty) return const SizedBox();
                      return TextButton(
                        onPressed: () {
                          AppState.alertHistory.value = [];
                        },
                        child: const Text(
                          "Clear All",
                          style: TextStyle(color: Colors.black38, fontSize: 13),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ValueListenableBuilder<List<AlertEntry>>(
                  valueListenable: AppState.alertHistory,
                  builder: (context, alerts, _) {
                    if (alerts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.notifications_none_rounded,
                              size: 64,
                              color: Colors.black12,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "No alerts today",
                              style: TextStyle(
                                color: Colors.black38,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "All systems are secure",
                              style: TextStyle(
                                color: Colors.black26,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: alerts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final alert = alerts[alerts.length - 1 - index];
                        final actualIndex = alerts.length - 1 - index;
                        return _AlertCard(
                          alert: alert,
                          onAcknowledge: () async {
                            if (alert.backendId != null) {
                              try {
                                await ApiService.acknowledgeAlert(
                                    alert.backendId!);
                              } catch (_) {}
                            }
                            final updated = List<AlertEntry>.from(
                              AppState.alertHistory.value,
                            );
                            updated.removeAt(actualIndex);
                            AppState.alertHistory.value = updated;
                          },
                        ).animate().fadeIn(
                              delay: Duration(milliseconds: index * 50),
                            );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertEntry alert;
  final VoidCallback onAcknowledge;

  const _AlertCard({required this.alert, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    final color = _getAlertColor(alert.type);
    final icon = _getAlertIcon(alert.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.message,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.time,
                      style: const TextStyle(
                        color: Colors.black38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _getSeverityLabel(alert.type),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onAcknowledge,
              style: TextButton.styleFrom(
                backgroundColor: color.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(
                "Acknowledge & Dismiss",
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getAlertColor(AlertType type) {
    switch (type) {
      case AlertType.fall:
        return const Color(0xFFFF1744);
      case AlertType.sharpObject:
        return const Color(0xFFFF6B35);
      case AlertType.unknown_face:
        return const Color(0xFFFFB300);
      case AlertType.wandering:
        return const Color(0xFF7B61FF);
      case AlertType.bathroomTimeout:
        return const Color(0xFF00BCD4);
      default:
        return Colors.grey;
    }
  }

  IconData _getAlertIcon(AlertType type) {
    switch (type) {
      case AlertType.fall:
        return Icons.personal_injury_rounded;
      case AlertType.sharpObject:
        return Icons.warning_amber_rounded;
      case AlertType.unknown_face:
        return Icons.face_retouching_natural;
      case AlertType.wandering:
        return Icons.location_off_rounded;
      case AlertType.bathroomTimeout:
        return Icons.timer_off_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  String _getSeverityLabel(AlertType type) {
    switch (type) {
      case AlertType.fall:
        return 'CRITICAL';
      case AlertType.sharpObject:
        return 'HIGH';
      case AlertType.unknown_face:
        return 'MEDIUM';
      case AlertType.wandering:
        return 'MEDIUM';
      case AlertType.bathroomTimeout:
        return 'LOW';
      default:
        return 'INFO';
    }
  }
}
