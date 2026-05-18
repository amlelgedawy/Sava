import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class AssignCaregiverPage extends StatefulWidget {
  const AssignCaregiverPage({super.key});
  @override
  State<AssignCaregiverPage> createState() => _AssignCaregiverPageState();
}

class _AssignCaregiverPageState extends State<AssignCaregiverPage> {
  Map<String, dynamic>? _currentCaregiver;
  String? _activeContractId;
  List<Map<String, dynamic>> _availableCaregivers = [];
  Set<String> _pendingCaregiverIds = {};
  bool _loading = true;
  bool _sendingOffer = false;
  bool _isPrimary = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final patientId = AppState.patientId.value;
      final myId = AppState.userId.value;

      // Check if current user is primary relative
      if (patientId != null && myId != null) {
        final relatives = await ApiService.getRelativesForPatient(patientId);
        _isPrimary = false;
        for (final rel in relatives) {
          final relUser = rel['relative'] as Map<String, dynamic>? ?? rel;
          final relId = relUser['id']?.toString();
          final roleType = (rel['role_type'] as String? ?? '').toUpperCase();
          if (relId == myId && roleType == 'PRIMARY') {
            _isPrimary = true;
            break;
          }
        }

        // Load current caregiver for patient
        final caregiver = await ApiService.getPatientCaregiver(patientId);
        _currentCaregiver = caregiver;

        // Find active contract ID for end-contract
        if (caregiver != null) {
          // We need the contract ID — fetch via caregiver's contracts
          try {
            final caregiverId = caregiver['id'].toString();
            final contracts = await ApiService.getCaregiverContracts(
              caregiverId: caregiverId,
              status: 'ACTIVE',
            );
            for (final c in contracts) {
              if ((c['patient_id']?.toString() ??
                      c['patient']?['id']?.toString()) ==
                  patientId) {
                _activeContractId = c['id'].toString();
                break;
              }
            }
          } catch (_) {}
        }
      }

      // Only load available caregivers if no current one
      if (_currentCaregiver == null) {
        final caregivers = await ApiService.getAvailableCaregivers();
        _availableCaregivers = caregivers.cast<Map<String, dynamic>>();

        // Check which caregivers have pending offers for this patient
        final patientId = AppState.patientId.value;
        if (patientId != null) {
          final pendingSet = <String>{};
          for (final cg in _availableCaregivers) {
            final cgId = cg['id']?.toString();
            if (cgId != null) {
              try {
                final contracts = await ApiService.getCaregiverContracts(
                  caregiverId: cgId,
                  status: 'PENDING',
                );
                for (final c in contracts) {
                  final contractPatientId = (c['patient_id']?.toString() ??
                      c['patient']?['id']?.toString());
                  if (contractPatientId == patientId) {
                    pendingSet.add(cgId);
                    break;
                  }
                }
              } catch (_) {}
            }
          }
          if (mounted) setState(() => _pendingCaregiverIds = pendingSet);
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign(String caregiverId) async {
    if (_sendingOffer) return; // Prevent duplicate taps
    final patientId = AppState.patientId.value;
    final requesterId = AppState.userId.value;
    if (patientId == null || requesterId == null) return;

    setState(() => _sendingOffer = true);
    try {
      await ApiService.sendCaregiverOffer(
        patientId: patientId,
        requesterId: requesterId,
        caregiverId: caregiverId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offer sent to caregiver')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingOffer = false);
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
          'Are you sure you want to end the contract with ${_currentCaregiver?['name']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: SovaColors.sage)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_activeContractId != null) {
                try {
                  await ApiService.endContract(
                    contractId: _activeContractId!,
                    userId: AppState.userId.value ?? '',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contract ended')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              }
              _load();
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
                        Text('RELATIVE',
                            style: SovaTheme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        Text('Caregiver',
                            style: SovaTheme.textTheme.displayMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (AppState.patientName.value.isNotEmpty)
                Text('Patient: ${AppState.patientName.value}',
                    style: TextStyle(color: SovaColors.sage, fontSize: 14)),
              const SizedBox(height: 32),

              // ── Current Caregiver ──────────────────────────────────────
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (!_loading && _currentCaregiver != null) ...[
                _sectionLabel('Current Caregiver'),
                const SizedBox(height: 12),
                _CurrentCaregiverCard(
                  caregiverName: _currentCaregiver!['name'] as String? ?? '',
                  isPrimary: _isPrimary,
                  onEndContract: _showEndContractDialog,
                ).animate().fadeIn(),
              ],

              // ── Available Caregivers ───────────────────────────────────
              if (!_loading && _currentCaregiver == null) ...[
                _sectionLabel('Available Caregivers'),
                const SizedBox(height: 4),
                Text(
                  _isPrimary
                      ? 'Select a verified caregiver to assign to your patient.'
                      : 'Only the primary relative can assign a caregiver.',
                  style: TextStyle(color: SovaColors.sage, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (_availableCaregivers.isEmpty)
                  _emptyState('No available caregivers at the moment')
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _availableCaregivers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final cg = _availableCaregivers[i];
                      final cgId = cg['id']?.toString() ?? '';
                      final isPending = _pendingCaregiverIds.contains(cgId);
                      return _CaregiverCard(
                        caregiver: cg,
                        canAssign: _isPrimary && !isPending,
                        isPending: isPending,
                        isSending: _sendingOffer,
                        onAssign: () => _assign(cgId),
                      ).animate().fadeIn(delay: (i * 80).ms).slideY(begin: 0.1);
                    },
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
  final String caregiverName;
  final bool isPrimary;
  final VoidCallback onEndContract;
  const _CurrentCaregiverCard(
      {required this.caregiverName,
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
              child: const Icon(Icons.person, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caregiverName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17)),
                  Text('Active Caregiver',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Center(
                  child: Text('End Contract',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
  final Map<String, dynamic> caregiver;
  final bool canAssign;
  final bool isPending;
  final bool isSending;
  final VoidCallback onAssign;
  const _CaregiverCard(
      {required this.caregiver,
      required this.canAssign,
      this.isPending = false,
      this.isSending = false,
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(caregiver['name'] as String? ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: SovaColors.charcoal)),
            const SizedBox(height: 4),
            Text(
              caregiver['email'] as String? ?? '',
              style: const TextStyle(color: SovaColors.sage, fontSize: 12),
            ),
          ]),
        ),
        if (isPending)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: SovaColors.navy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: SovaColors.navy.withValues(alpha: 0.3))),
            child: const Text('Pending Approval',
                style: TextStyle(
                    color: SovaColors.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          )
        else if (canAssign)
          GestureDetector(
            onTap: isSending ? null : onAssign,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: isSending
                      ? SovaColors.navy.withValues(alpha: 0.5)
                      : SovaColors.navy,
                  borderRadius: BorderRadius.circular(20)),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Assign',
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
