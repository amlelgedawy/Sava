import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models/patient_models.dart';
import '../services/database_service.dart';

class ActivityTimelinePage extends StatelessWidget {
  const ActivityTimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: ValueListenableBuilder<List<ActivityLog>>(
        valueListenable: AppState.allActivityLogs,
        builder: (context, logs, _) {
          final displayLogs = logs.reversed.toList();
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 100,
                pinned: true,
                backgroundColor: SovaColors.bg,
                elevation: 0,
                title: const Text(
                  "Activity Log",
                  style: TextStyle(
                    color: SovaColors.charcoal,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                // ✅ + button writes to AppState via service, not directly
                actions: [
                  IconButton(
                    onPressed: () {
                      // ✅ Correct: AppState.addActivity writes to AppState
                      // which triggers DatabaseService internally
                      AppState.addActivity("Eating", Icons.restaurant_rounded);
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: SovaColors.charcoal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 150),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final log = displayLogs[index];
                    final Color actColor = DatabaseService.getActivityColor(
                      log.title,
                    );
                    final bool isLatest = index == 0;
                    return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: isLatest
                                  ? actColor.withOpacity(0.8)
                                  : actColor.withOpacity(0.15),
                              width: isLatest ? 2.5 : 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: actColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  log.icon,
                                  color: actColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      log.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      log.isFinished
                                          ? "Finished at ${log.finishTime}"
                                          : "Undergoing",
                                      style: TextStyle(
                                        color: log.isFinished
                                            ? Colors.grey
                                            : SovaColors.danger,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(delay: (index * 50).ms)
                        .slideX(begin: 0.05);
                  }, childCount: displayLogs.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
