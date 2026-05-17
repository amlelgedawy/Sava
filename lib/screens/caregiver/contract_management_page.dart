import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class ContractManagementPage extends StatefulWidget {
  const ContractManagementPage({super.key});
  @override
  State<ContractManagementPage> createState() => _ContractManagementPageState();
}

class _ContractManagementPageState extends State<ContractManagementPage> {
  List<Map<String, dynamic>> _contracts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  Future<void> _loadContracts() async {
    final caregiverId = AppState.userId.value;
    if (caregiverId == null) return;

    setState(() => _loading = true);
    try {
      final contracts = await ApiService.getCaregiverContracts(
        caregiverId: caregiverId,
        status: 'PENDING',
      );
      if (mounted) {
        setState(() {
          _contracts = contracts.cast<Map<String, dynamic>>();
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
                        Text('CAREGIVER',
                            style: SovaTheme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        Text('Contract Requests',
                            style: SovaTheme.textTheme.displayMedium),
                        Text(
                            '${_loading ? '...' : _contracts.length} pending requests',
                            style: TextStyle(
                                color: SovaColors.sage, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _contracts.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            itemCount: _contracts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) => _ContractCard(
                              contract: _contracts[i],
                              onAccept: () => _acceptContract(
                                  _contracts[i]['id'].toString(),
                                  _contracts[i]),
                              onDecline: () => _declineContract(
                                  _contracts[i]['id'].toString()),
                            )
                                .animate()
                                .fadeIn(delay: (i * 80).ms)
                                .slideY(begin: 0.08),
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
          Text('No pending contracts',
              style: TextStyle(
                  color: SovaColors.sage,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('You will see contract requests here',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
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
