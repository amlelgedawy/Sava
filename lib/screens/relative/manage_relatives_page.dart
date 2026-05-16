import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';

class ManageRelativesPage extends StatefulWidget {
  const ManageRelativesPage({super.key});
  @override
  State<ManageRelativesPage> createState() => _ManageRelativesPageState();
}

class _ManageRelativesPageState extends State<ManageRelativesPage> {
  List<Map<String, dynamic>> _relatives = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final patientId = AppState.patientId.value;
    if (patientId == null) return;
    setState(() => _loading = true);
    try {
      final list = await ApiService.getRelativesForPatient(patientId);
      if (mounted) {
        setState(() {
          _relatives = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isPrimary => true;

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
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
                const Text('Add Secondary Relative',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: SovaColors.charcoal)),
                const SizedBox(height: 6),
                const Text(
                  'They will receive login credentials by email.',
                  style: TextStyle(color: SovaColors.sage, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _sheetField(nameCtrl, 'Full Name', Icons.person_outline),
                const SizedBox(height: 12),
                _sheetField(emailCtrl, 'Email', Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 12),
                _sheetField(passCtrl, 'Temporary Password', Icons.lock_outline,
                    obscure: true),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!,
                        style: const TextStyle(
                            color: SovaColors.danger, fontSize: 13)),
                  ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                    if (nameCtrl.text.isEmpty ||
                        emailCtrl.text.isEmpty ||
                        passCtrl.text.isEmpty) {
                      setModal(() => error = 'Please fill all fields');
                      return;
                    }
                    final patientId = AppState.patientId.value;
                    final requesterId = AppState.userId.value;
                    if (patientId == null || requesterId == null) return;
                    try {
                      await ApiService.addRelative(
                        patientId: patientId,
                        requesterId: requesterId,
                        username: nameCtrl.text.trim(),
                        roleType: 'SECONDARY',
                      );
                    } catch (_) {}
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                        color: SovaColors.coral,
                        borderRadius: BorderRadius.circular(28)),
                    child: const Center(
                      child: Text('Add Relative',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeType(Map<String, dynamic> rel, String newType) {
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final myId = AppState.userId.value;

    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RELATIVE', style: SovaTheme.textTheme.labelMedium),
                      Text('Family', style: SovaTheme.textTheme.displayMedium),
                      if (AppState.patientName.value.isNotEmpty)
                        Text('Patient: ${AppState.patientName.value}',
                            style: TextStyle(
                                color: SovaColors.sage, fontSize: 14)),
                    ],
                  ),
                ),
                if (_isPrimary)
                  GestureDetector(
                    onTap: _showAddDialog,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: SovaColors.coral,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.person_add_outlined,
                          color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 28),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _relatives.isEmpty
                        ? _emptyState()
                        : ListView.separated(
                            itemCount: _relatives.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final rel = _relatives[i];
                              final relUser =
                                  rel['relative'] as Map<String, dynamic>? ??
                                      rel;
                              final relId = relUser['id']?.toString();
                              final isMe = relId == myId;
                              return _RelativeCard(
                                relative: rel,
                                isMe: isMe,
                                canManage: _isPrimary && !isMe,
                                onPromote: () => _changeType(rel, 'PRIMARY'),
                                onDemote: () => _changeType(rel, 'SECONDARY'),
                              )
                                  .animate()
                                  .fadeIn(delay: (i * 80).ms)
                                  .slideY(begin: 0.1);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.group_outlined, size: 64, color: SovaColors.sensorNeutral),
          const SizedBox(height: 16),
          Text('No relatives added yet',
              style: TextStyle(
                  color: SovaColors.sage, fontWeight: FontWeight.w600)),
          if (_isPrimary)
            Text('Tap + to add a secondary relative',
                style: TextStyle(color: SovaColors.sage, fontSize: 13)),
        ]),
      );

  Widget _sheetField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? type,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: SovaColors.bg, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        obscureText: obscure,
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

class _RelativeCard extends StatelessWidget {
  final Map<String, dynamic> relative;
  final bool isMe;
  final bool canManage;
  final VoidCallback onPromote;
  final VoidCallback onDemote;

  const _RelativeCard({
    required this.relative,
    required this.isMe,
    required this.canManage,
    required this.onPromote,
    required this.onDemote,
  });

  @override
  Widget build(BuildContext context) {
    final relUser = relative['relative'] as Map<String, dynamic>? ?? relative;
    final roleType = (relative['role_type'] as String? ?? '').toUpperCase();
    final isPrimary = roleType == 'PRIMARY';
    final name = relUser['name'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:
            isPrimary ? SovaColors.coral.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPrimary
              ? SovaColors.coral.withValues(alpha: 0.3)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: isPrimary
                ? SovaColors.coral.withValues(alpha: 0.15)
                : SovaColors.sensorNeutral,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person,
              color: isPrimary ? SovaColors.coral : SovaColors.sage, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: SovaColors.charcoal)),
              if (isMe)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: SovaColors.navy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('You',
                      style: TextStyle(
                          fontSize: 11,
                          color: SovaColors.navy,
                          fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(
              isPrimary ? 'Primary Relative' : 'Secondary Relative',
              style: TextStyle(
                  color: isPrimary ? SovaColors.coral : SovaColors.sage,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        if (canManage)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: SovaColors.sage),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) {
              if (v == 'promote') onPromote();
              if (v == 'demote') onDemote();
            },
            itemBuilder: (_) => [
              if (!isPrimary)
                const PopupMenuItem(
                  value: 'promote',
                  child: Row(children: [
                    Icon(Icons.arrow_upward, size: 18, color: SovaColors.navy),
                    SizedBox(width: 8),
                    Text('Make Primary'),
                  ]),
                ),
              if (isPrimary)
                const PopupMenuItem(
                  value: 'demote',
                  child: Row(children: [
                    Icon(Icons.arrow_downward,
                        size: 18, color: SovaColors.sage),
                    SizedBox(width: 8),
                    Text('Make Secondary'),
                  ]),
                ),
            ],
          ),
      ]),
    );
  }
}
