import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models/user_models.dart';
import '../../services/mock_service.dart';

class AssignCaregiverPage extends StatefulWidget {
  const AssignCaregiverPage({super.key});
  @override
  State<AssignCaregiverPage> createState() => _AssignCaregiverPageState();
}

class _AssignCaregiverPageState extends State<AssignCaregiverPage> {
  Patient? _patient;
  CaregiverUser? _currentCaregiver;
  List<CaregiverUser> _available = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final user = AppState.currentUser.value;
    if (user is! RelativeUser || user.patientId == null) return;
    final patient = MockService.instance.getPatient(user.patientId!);
    if (patient == null) return;
    CaregiverUser? cg;
    if (patient.assignedCaregiverId != null) {
      cg = MockService.instance.getCaregiverById(patient.assignedCaregiverId!);
    }
    setState(() {
      _patient = patient;
      _currentCaregiver = cg;
      _available = MockService.instance.getAvailableCaregivers();
    });
  }

  bool get _isPrimary {
    final user = AppState.currentUser.value;
    return user is RelativeUser && user.relativeType == RelativeType.primary;
  }

  void _assign(String caregiverId) {
    if (_patient == null) return;
    final ok = MockService.instance
        .assignCaregiverToPatient(_patient!.id, caregiverId);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver assigned successfully')),
      );
      _load();
    }
  }

  void _showEndContractDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('End Contract',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to end the contract with ${_currentCaregiver?.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: SovaColors.sage)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_patient != null) {
                MockService.instance.removeCaregiverFromPatient(_patient!.id);
                _load();
              }
            },
            child: const Text('End Contract',
                style: TextStyle(color: SovaColors.danger)),
          ),
        ],
      ),
    );
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
              Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Text('Caregiver', style: SovaTheme.textTheme.displayMedium),
              if (_patient != null)
                Text('Patient: ${_patient!.name}',
                    style: TextStyle(color: SovaColors.sage, fontSize: 14)),
              const SizedBox(height: 32),

              // ── Current Caregiver ──────────────────────────────────────
              if (_currentCaregiver != null) ...[
                _sectionLabel('Current Caregiver'),
                const SizedBox(height: 12),
                _CurrentCaregiverCard(
                  caregiver: _currentCaregiver!,
                  isPrimary: _isPrimary,
                  onEndContract: _showEndContractDialog,
                ).animate().fadeIn(),
              ],

              // ── Available Caregivers ───────────────────────────────────
              if (_currentCaregiver == null) ...[
                _sectionLabel('Available Caregivers'),
                const SizedBox(height: 4),
                Text(
                  _isPrimary
                      ? 'Select a verified caregiver to assign to your patient.'
                      : 'Only the primary relative can assign a caregiver.',
                  style: TextStyle(color: SovaColors.sage, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_available.isEmpty)
                  _emptyState('No available caregivers at the moment')
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _available.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _CaregiverCard(
                      caregiver: _available[i],
                      canAssign: _isPrimary,
                      onAssign: () => _assign(_available[i].id),
                    )
                        .animate()
                        .fadeIn(delay: (i * 80).ms)
                        .slideY(begin: 0.1),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(label,
      style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: SovaColors.charcoal));

  Widget _emptyState(String msg) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.info_outline, color: SovaColors.sage),
          const SizedBox(width: 12),
          Text(msg, style: TextStyle(color: SovaColors.sage)),
        ]),
      );
}

class _CurrentCaregiverCard extends StatelessWidget {
  final CaregiverUser caregiver;
  final bool isPrimary;
  final VoidCallback onEndContract;
  const _CurrentCaregiverCard(
      {required this.caregiver,
      required this.isPrimary,
      required this.onEndContract});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SovaColors.navy,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.person, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caregiver.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                  Text('${caregiver.yearsExperience} yrs experience',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: SovaColors.success.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Active',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _infoChip(
                Icons.attach_money, 'EGP ${caregiver.salary.toStringAsFixed(0)}/mo'),
            const SizedBox(width: 10),
            _infoChip(Icons.verified_outlined, 'Verified'),
          ]),
          if (isPrimary) ...[
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onEndContract,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Center(
                  child: Text('End Contract',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _CaregiverCard extends StatelessWidget {
  final CaregiverUser caregiver;
  final bool canAssign;
  final VoidCallback onAssign;
  const _CaregiverCard(
      {required this.caregiver,
      required this.canAssign,
      required this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: SovaColors.navy.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: SovaColors.navy),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(caregiver.name,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: SovaColors.charcoal)),
            const SizedBox(height: 4),
            Text(
              '${caregiver.yearsExperience} yrs exp  •  EGP ${caregiver.salary.toStringAsFixed(0)}/mo',
              style:
                  const TextStyle(color: SovaColors.sage, fontSize: 12),
            ),
            Text(
              '${caregiver.assignedPatientIds.length}/4 patients',
              style: const TextStyle(color: SovaColors.sage, fontSize: 12),
            ),
          ]),
        ),
        if (canAssign)
          GestureDetector(
            onTap: onAssign,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: SovaColors.navy,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Assign',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ),
      ]),
    );
  }
}
