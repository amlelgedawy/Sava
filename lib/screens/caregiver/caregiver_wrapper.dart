import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import 'caregiver_home_page.dart';
import '../activity_timeline_page.dart';
import 'patient_list_page.dart';
import 'medicine_schedule_page.dart';
import 'contract_management_page.dart';

class CaregiverWrapper extends StatefulWidget {
  const CaregiverWrapper({super.key});
  @override
  State<CaregiverWrapper> createState() => _CaregiverWrapperState();
}

class _CaregiverWrapperState extends State<CaregiverWrapper> {
  int _index = 0;

  static final List<Widget> _pages = [
    const CaregiverHomePage(),
    const ContractManagementPage(),
    const PatientListPage(),
    const ActivityTimelinePage(),
    const MedicineSchedulePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),
          Align(
            alignment: Alignment.bottomCenter,
            child: _bottomNav(),
          ),
        ],
      ),
    );
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
            _navItem(1, Icons.description_outlined, 'Contracts'),
            _navItem(2, Icons.people_outline_rounded, 'Patients'),
            _navItem(3, Icons.assignment_outlined, 'Logs'),
            _navItem(4, Icons.calendar_today_outlined, 'Schedule'),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, duration: 800.ms, curve: Curves.easeOutCubic);
  }

  Widget _navItem(int idx, IconData icon, String label) {
    final active = idx == _index;
    return GestureDetector(
      onTap: () => setState(() => _index = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? SovaColors.sage.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(children: [
          Icon(icon,
              color: active ? SovaColors.sage : Colors.white54, size: 22),
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
