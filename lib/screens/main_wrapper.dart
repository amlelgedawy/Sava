import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import 'home_page.dart';
import 'activity_timeline_page.dart';
import 'alerts_page.dart';

class MainWrapper extends StatelessWidget {
  const MainWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(),
      ActivityTimelinePage(),
      AlertsPage(),
    ];

    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: AppState.currentNavIndex,
        builder: (context, index, child) {
          return Stack(
            children: [
              IndexedStack(index: index, children: pages),
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildBottomNav(context, index),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context, int currentIndex) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      height: 75,
      decoration: BoxDecoration(
        color: SovaColors.charcoal.withOpacity(0.98),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.grid_view_rounded, "Home", currentIndex),
            _navItem(1, Icons.assignment_outlined, "Logs", currentIndex),
            _navItemWithBadge(
              2,
              Icons.notifications_rounded,
              "Alerts",
              currentIndex,
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, duration: 800.ms, curve: Curves.easeOutCubic);
  }

  Widget _navItem(int index, IconData icon, String label, int current) {
    bool isActive = index == current;
    return GestureDetector(
      onTap: () => AppState.currentNavIndex.value = index,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? SovaColors.sage.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isActive ? SovaColors.sage : Colors.white54,
              size: 24,
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ).animate().fadeIn(),
          ],
        ),
      ),
    );
  }

  Widget _navItemWithBadge(
    int index,
    IconData icon,
    String label,
    int current,
  ) {
    bool isActive = index == current;
    return GestureDetector(
      onTap: () => AppState.currentNavIndex.value = index,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? SovaColors.sage.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            ValueListenableBuilder<List<AlertEntry>>(
              valueListenable: AppState.alertHistory,
              builder: (context, alerts, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      color: isActive ? SovaColors.sage : Colors.white54,
                      size: 24,
                    ),
                    if (alerts.isNotEmpty && !isActive)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF1744),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              alerts.length > 9 ? '9+' : '${alerts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ).animate().fadeIn(),
          ],
        ),
      ),
    );
  }
}
