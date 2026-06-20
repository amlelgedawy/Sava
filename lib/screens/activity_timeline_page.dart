import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models/patient_models.dart';
import '../services/database_service.dart';

class ActivityTimelinePage extends StatefulWidget {
  const ActivityTimelinePage({super.key});
  @override
  State<ActivityTimelinePage> createState() => _ActivityTimelinePageState();
}

class _ActivityTimelinePageState extends State<ActivityTimelinePage> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    await DatabaseService.fetchActivityHistory();
    if (mounted) setState(() => _loading = false);
  }

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
                actions: [
                  if (logs.isNotEmpty)
                    TextButton(
                      onPressed: () => DatabaseService.clearActivityLog(),
                      child: const Text(
                        "Clear All",
                        style: TextStyle(color: Colors.black38, fontSize: 13),
                      ),
                    ),
                  _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: _fetch,
                          icon: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: SovaColors.charcoal,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.refresh_rounded,
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
