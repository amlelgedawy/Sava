import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../app_state.dart';
import '../../theme.dart';
import 'relative_home_page.dart';
import '../caregiver/medicine_schedule_page.dart';
import 'assign_caregiver_page.dart';
import 'manage_relatives_page.dart';
import '../alerts_page.dart';
import '../activity_timeline_page.dart';

class RelativeWrapper extends StatefulWidget {
  const RelativeWrapper({super.key});
  @override
  State<RelativeWrapper> createState() => _RelativeWrapperState();
}

class _RelativeWrapperState extends State<RelativeWrapper> {
  int _index = 0;

  // 0=Home, 1=Caregiver, 2=Family, 3=Schedule, 4=Alerts, 5=Timeline(hidden)
  static final List<Widget> _pages = [
    const RelativeHomePage(),
    const AssignCaregiverPage(),
    const ManageRelativesPage(),
    const MedicineSchedulePage(),
    const AlertsPage(),
    const ActivityTimelinePage(),
  ];

  @override
  void initState() {
    super.initState();
    AppState.currentNavIndex.value = 0;
    AppState.currentNavIndex.addListener(_onNavChange);
  }

  @override
  void dispose() {
    AppState.currentNavIndex.removeListener(_onNavChange);
    super.dispose();
  }

  void _onNavChange() {
    final idx = AppState.currentNavIndex.value;
    if (_index != idx && idx < _pages.length) {
      setState(() => _index = idx);
    }
  }

  void _setIndex(int idx) {
    setState(() => _index = idx);
    AppState.currentNavIndex.value = idx;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        child: Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: _index, children: _pages),
              Align(
                alignment: Alignment.bottomCenter,
                child: _bottomNav(),
              ),
            ],
          ),
        ));
  }

  Widget _bottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      height: 75,
      decoration: BoxDecoration(
        color: SovaColors.charcoal.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(0, Icons.grid_view_rounded, 'Home'),
            _navItem(1, Icons.person_outline_rounded, 'Caregiver'),
            _navItem(2, Icons.group_outlined, 'Family'),
            _navItem(3, Icons.calendar_today_outlined, 'Schedule'),
            _navItem(4, Icons.notifications_outlined, 'Alerts'),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, duration: 800.ms, curve: Curves.easeOutCubic);
  }

  Widget _navItem(int idx, IconData icon, String label) {
    final active = idx == _index;
    return GestureDetector(
      onTap: () => _setIndex(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? SovaColors.coral.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(children: [
          Icon(icon,
              color: active ? SovaColors.coral : Colors.white54, size: 22),
          if (active)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ).animate().fadeIn(),
        ]),
      ),
    );
  }
}
