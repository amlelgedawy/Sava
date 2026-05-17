import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class CvReviewPage extends StatefulWidget {
  const CvReviewPage({super.key});
  @override
  State<CvReviewPage> createState() => _CvReviewPageState();
}

class _CvReviewPageState extends State<CvReviewPage> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await ApiService.adminListCaregivers();
      if (mounted)
        setState(() {
          _pending = all
              .cast<Map<String, dynamic>>()
              .where((c) =>
                  c['salary_per_hour'] == null || c['salary_per_hour'] == 0)
              .toList();
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showReviewDialog(Map<String, dynamic> cg) {
    final salaryCtrl = TextEditingController();
    final expCtrl = TextEditingController();
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: SovaColors.sensorNeutral,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Verify: ${cg['name']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: SovaColors.charcoal)),
                const SizedBox(height: 20),
                _sheetField(
                    salaryCtrl, 'Monthly Salary (EGP)', Icons.attach_money,
                    type: TextInputType.number),
                const SizedBox(height: 12),
                _sheetField(expCtrl, 'Years of Experience', Icons.work_outline,
                    type: TextInputType.number),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(
                            color: SovaColors.danger, fontSize: 13)),
                  ),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final salary = double.tryParse(salaryCtrl.text);
                        final exp = int.tryParse(expCtrl.text);
                        if (salary == null || exp == null) {
                          setModal(() => error = 'Please fill both fields');
                          return;
                        }
                        final adminId = AppState.userId.value ?? '';
                        try {
                          await ApiService.adminSetSalary(
                            adminId: adminId,
                            caregiverId: cg['id'].toString(),
                            salaryPerHour: salary,
                          );
                        } catch (_) {}
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    '${cg['name']} verified successfully')),
                          );
                      },
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                            color: SovaColors.success,
                            borderRadius: BorderRadius.circular(28)),
                        child: const Center(
                          child: Text('Verify & Approve',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final adminId = AppState.userId.value ?? '';
                        try {
                          await ApiService.adminRejectCaregiver(
                            adminId: adminId,
                            caregiverId: cg['id'].toString(),
                          );
                        } catch (_) {}
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('${cg['name']} application rejected')),
                          );
                        }
                      },
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                            color: SovaColors.danger,
                            borderRadius: BorderRadius.circular(28)),
                        child: const Center(
                          child: Text('Reject',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
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
                        Text('ADMIN', style: SovaTheme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        Text('CV Review',
                            style: SovaTheme.textTheme.displayMedium),
                        Text(
                          '${_loading ? '...' : _pending.length} pending verification',
                          style:
                              TextStyle(color: SovaColors.sage, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _pending.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            itemCount: _pending.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) => _CvCard(
                              caregiver: _pending[i],
                              onReview: () => _showReviewDialog(_pending[i]),
                            )
                                .animate()
                                .fadeIn(delay: (i * 80).ms)
                                .slideY(begin: 0.1),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: SovaColors.success),
            const SizedBox(height: 16),
            Text('All CVs reviewed!',
                style: TextStyle(
                    color: SovaColors.sage,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const SizedBox(height: 8),
            Text('No pending verifications',
                style: TextStyle(color: SovaColors.sage, fontSize: 13)),
          ],
        ),
      );

  Widget _sheetField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: SovaColors.bg, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: SovaColors.sage),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

class _CvCard extends StatelessWidget {
  final Map<String, dynamic> caregiver;
  final VoidCallback onReview;
  const _CvCard({required this.caregiver, required this.onReview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: SovaColors.navy.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.person, color: SovaColors.navy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(caregiver['name'] as String? ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: SovaColors.charcoal)),
                    Text(caregiver['email'] as String? ?? '',
                        style: const TextStyle(
                            color: SovaColors.sage, fontSize: 12)),
                  ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: SovaColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Pending',
                  style: TextStyle(
                      color: SovaColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 16),
          if (caregiver['age'] != null)
            _detail('Age', '${caregiver['age']} years'),
          if (caregiver['national_id'] != null)
            _detail('National ID', caregiver['national_id'].toString()),
          if (caregiver['cv_path'] != null)
            _detail('CV', caregiver['cv_path'].toString()),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onReview,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                  color: SovaColors.navy,
                  borderRadius: BorderRadius.circular(24)),
              child: const Center(
                child: Text('Review & Set Salary',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(color: SovaColors.sage, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: SovaColors.charcoal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}
