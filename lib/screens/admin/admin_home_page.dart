import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});
  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _totalUsers = 0;
  int _caregiverCount = 0;
  int _relativeCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await ApiService.adminListUsers();
      if (!mounted) return;
      setState(() {
        _totalUsers = all.length;
        _caregiverCount = all
            .where((u) =>
                (u['role'] as String? ?? '').toUpperCase() == 'CAREGIVER')
            .length;
        _relativeCount = all
            .where(
                (u) => (u['role'] as String? ?? '').toUpperCase() == 'RELATIVE')
            .length;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SovaColors.softGlass,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: SovaColors.charcoal, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ADMIN', style: SovaTheme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        Text('Dashboard',
                            style: SovaTheme.textTheme.displayMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome, ${AppState.caregiverName.value}',
                style: TextStyle(color: SovaColors.sage, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Row(children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.people_outline,
                    label: 'Total Users',
                    value: '$_totalUsers',
                    color: SovaColors.navy,
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.medical_services_outlined,
                    label: 'Caregivers',
                    value: '$_caregiverCount',
                    color: SovaColors.coral,
                  ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.family_restroom,
                    label: 'Relatives',
                    value: '$_relativeCount',
                    color: SovaColors.success,
                  ).animate().fadeIn(delay: 260.ms).slideY(begin: 0.1),
                ),
              ]),
              const SizedBox(height: 32),
              Text('Quick Actions',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: SovaColors.charcoal)),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.manage_accounts_outlined,
                title: 'Manage Users',
                subtitle: '$_totalUsers registered users',
                color: SovaColors.navy,
                onTap: () {},
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 32),
              Text('System Info',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: SovaColors.charcoal)),
              const SizedBox(height: 16),
              _InfoRow(label: 'Total Caregivers', value: '$_caregiverCount'),
              _InfoRow(label: 'Total Relatives', value: '$_relativeCount'),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: SovaColors.charcoal)),
              Text(subtitle,
                  style: const TextStyle(color: SovaColors.sage, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: SovaColors.sage),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Text(label,
            style: const TextStyle(color: SovaColors.sage, fontSize: 14)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: SovaColors.charcoal)),
      ]),
    );
  }
}
