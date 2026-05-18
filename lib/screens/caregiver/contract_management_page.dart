import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';

class ContractManagementPage extends StatefulWidget {
  const ContractManagementPage({super.key});
  @override
  State<ContractManagementPage> createState() => _ContractManagementPageState();
}

class _ContractManagementPageState extends State<ContractManagementPage> {
  List<Map<String, dynamic>> _pendingContracts = [];
  List<Map<String, dynamic>> _activeContracts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  void _refreshDashboard() {
    // Trigger dashboard refresh when patient changes
    DatabaseService.refreshDashboard();
  }

  Future<void> _loadContracts() async {
    final caregiverId = AppState.userId.value;
    if (caregiverId == null) return;

    setState(() => _loading = true);
    try {
      final pending = await ApiService.getCaregiverContracts(
        caregiverId: caregiverId,
        status: 'PENDING',
      );
      final active = await ApiService.getCaregiverContracts(
        caregiverId: caregiverId,
        status: 'ACTIVE',
      );
      if (mounted) {
        setState(() {
          _pendingContracts = pending.cast<Map<String, dynamic>>();
          _activeContracts = active.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load contracts: $e')),
        );
      }
    }
  }

  Future<void> _acceptContract(
      String contractId, Map<String, dynamic> contract) async {
    final caregiverId = AppState.userId.value;
    if (caregiverId == null) return;

    try {
      await ApiService.acceptContract(
        contractId: contractId,
        caregiverId: caregiverId,
      );

      // Set the patient as active
      final patient = contract['patient'] as Map<String, dynamic>?;
      if (patient != null) {
        AppState.patientId.value = patient['id'].toString();
        AppState.patientName.value = patient['name'] as String? ?? '';
        _refreshDashboard();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contract accepted')),
        );
        _loadContracts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept contract: $e')),
        );
      }
    }
  }

  Future<void> _endContract(String contractId) async {
    final userId = AppState.userId.value;
    if (userId == null) return;

    try {
      await ApiService.endContract(
        contractId: contractId,
        userId: userId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contract ended')),
        );
        _loadContracts();
        // Clear patient if this was the active one
        AppState.patientId.value = null;
        AppState.patientName.value = '';
        _refreshDashboard();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to end contract: $e')),
        );
      }
    }
  }

  Future<void> _declineContract(String contractId) async {
    final caregiverId = AppState.userId.value;
    if (caregiverId == null) return;

    try {
      await ApiService.declineContract(
        contractId: contractId,
        caregiverId: caregiverId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contract declined')),
        );
        _loadContracts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline contract: $e')),
        );
      }
    }
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
              Text('Contracts', style: SovaTheme.textTheme.displayMedium),
              Text(
                  '${_loading ? '...' : '${_pendingContracts.length + _activeContracts.length}'} contracts',
                  style: TextStyle(color: SovaColors.sage, fontSize: 14)),
              const SizedBox(height: 32),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          if (_pendingContracts.isNotEmpty) ...[
                            const Text('Pending Requests',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: SovaColors.charcoal)),
                            const SizedBox(height: 12),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _pendingContracts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => _ContractCard(
                                contract: _pendingContracts[i],
                                onAccept: () => _acceptContract(
                                    _pendingContracts[i]['id'].toString(),
                                    _pendingContracts[i]),
                                onDecline: () => _declineContract(
                                    _pendingContracts[i]['id'].toString()),
                              )
                                  .animate()
                                  .fadeIn(delay: (i * 80).ms)
                                  .slideY(begin: 0.08),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (_activeContracts.isNotEmpty) ...[
                            const Text('Active Contracts',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: SovaColors.charcoal)),
                            const SizedBox(height: 12),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _activeContracts.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => _ActiveContractCard(
                                contract: _activeContracts[i],
                                onEnd: () => _endContract(
                                    _activeContracts[i]['id'].toString()),
                              )
                                  .animate()
                                  .fadeIn(delay: (i * 80).ms)
                                  .slideY(begin: 0.08),
                            ),
                          ],
                          if (_pendingContracts.isEmpty &&
                              _activeContracts.isEmpty)
                            _emptyState(),
                        ],
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
          Icon(Icons.inbox_rounded, size: 64, color: SovaColors.sensorNeutral),
          const SizedBox(height: 16),
          Text('No contracts',
              style: TextStyle(
                  color: SovaColors.sage,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('You will see contract requests and active contracts here',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ActiveContractCard extends StatelessWidget {
  final Map<String, dynamic> contract;
  final VoidCallback onEnd;

  const _ActiveContractCard({
    required this.contract,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final patient = contract['patient'] as Map<String, dynamic>? ?? {};
    final patientName = patient['name'] as String? ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SovaColors.success.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                  color: SovaColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: SovaColors.success, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patientName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: SovaColors.charcoal)),
                    const SizedBox(height: 4),
                    const Text('Active',
                        style:
                            TextStyle(fontSize: 12, color: SovaColors.success)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onEnd,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: SovaColors.danger),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('End Contract',
                style: TextStyle(color: SovaColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _ContractCard extends StatelessWidget {
  final Map<String, dynamic> contract;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _ContractCard({
    required this.contract,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final patient = contract['patient'] as Map<String, dynamic>? ?? {};
    final patientName = patient['name'] as String? ?? 'Unknown';
    final requester = contract['requester'] as Map<String, dynamic>? ?? {};
    final requesterName = requester['name'] as String? ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
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
                  color: SovaColors.navy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_outline,
                    color: SovaColors.navy, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patientName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: SovaColors.charcoal)),
                    const SizedBox(height: 4),
                    Text('Requested by $requesterName',
                        style: TextStyle(fontSize: 12, color: SovaColors.sage)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: SovaColors.danger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Decline',
                      style: TextStyle(color: SovaColors.danger)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SovaColors.success,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Accept',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
