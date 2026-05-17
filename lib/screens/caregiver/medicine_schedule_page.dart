import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models/patient_models.dart';
import '../../models/user_models.dart';
import '../../services/api_service.dart';

class MedicineSchedulePage extends StatefulWidget {
  const MedicineSchedulePage({super.key});
  @override
  State<MedicineSchedulePage> createState() => _MedicineSchedulePageState();
}

class _MedicineSchedulePageState extends State<MedicineSchedulePage> {
  bool _isPrimaryRelative = false;

  bool get _isReadOnly {
    // Caregivers can always edit
    if (AppState.userRole.value == UserRole.caregiver) return false;
    // Primary relatives can edit
    if (AppState.userRole.value == UserRole.relative && _isPrimaryRelative)
      return false;
    // Others are read-only
    return true;
  }

  @override
  void initState() {
    super.initState();
    _checkIfPrimaryRelative();
  }

  Future<void> _checkIfPrimaryRelative() async {
    if (AppState.userRole.value != UserRole.relative) return;

    final patientId = AppState.patientId.value;
    final myId = AppState.userId.value;
    if (patientId == null || myId == null) return;

    try {
      final relatives = await ApiService.getRelativesForPatient(patientId);
      for (final rel in relatives) {
        final relUser = rel['relative'] as Map<String, dynamic>? ?? rel;
        final relId = relUser['id']?.toString();
        final roleType = (rel['role_type'] as String? ?? '').toUpperCase();
        if (relId == myId && roleType == 'PRIMARY') {
          setState(() => _isPrimaryRelative = true);
          return;
        }
      }
    } catch (_) {
      // Ignore errors, default to read-only
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    TimeOfDay selected = TimeOfDay.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
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
              const Text('Add Medication',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: SovaColors.charcoal)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                    color: SovaColors.bg,
                    borderRadius: BorderRadius.circular(20)),
                child: TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Medication name & dosage',
                    prefixIcon:
                        Icon(Icons.medication_outlined, color: SovaColors.sage),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final t =
                      await showTimePicker(context: ctx, initialTime: selected);
                  if (t != null) setModal(() => selected = t);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: SovaColors.bg,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(Icons.access_time, color: SovaColors.sage),
                    const SizedBox(width: 12),
                    Text(selected.format(ctx),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: SovaColors.charcoal)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: SovaColors.sage),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final h = selected.hour;
                  final m = selected.minute;
                  final period = h >= 12 ? 'PM' : 'AM';
                  final hh = h > 12
                      ? h - 12
                      : h == 0
                          ? 12
                          : h;
                  final timeStr =
                      '${hh.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
                  AppState.allMedications.value = [
                    ...AppState.allMedications.value,
                    Medication(name: nameCtrl.text.trim(), time: timeStr),
                  ];
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                      color: SovaColors.navy,
                      borderRadius: BorderRadius.circular(28)),
                  child: const Center(
                    child: Text('Add',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteMed(int index) {
    final updated = List<Medication>.from(AppState.allMedications.value);
    updated.removeAt(index);
    AppState.allMedications.value = updated;
  }

  void _toggleTaken(int index) {
    final updated = List<Medication>.from(AppState.allMedications.value);
    final med = updated[index];
    updated[index] =
        Medication(name: med.name, time: med.time, isTaken: !med.isTaken);
    AppState.allMedications.value = updated;
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
              Row(children: [
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
                      Text(
                        _isReadOnly ? 'RELATIVE' : 'CAREGIVER',
                        style: SovaTheme.textTheme.labelMedium,
                      ),
                      Text('Medicine Schedule',
                          style: SovaTheme.textTheme.displayMedium),
                    ],
                  ),
                ),
                if (_isReadOnly)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: SovaColors.sage.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: SovaColors.sage.withValues(alpha: 0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.visibility_outlined,
                          size: 14, color: SovaColors.sage),
                      SizedBox(width: 6),
                      Text('View Only',
                          style: TextStyle(
                              color: SovaColors.sage,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
                  )
                else
                  GestureDetector(
                    onTap: _showAddDialog,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: SovaColors.navy,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: AppState.patientName,
                builder: (_, name, __) => Text(
                  'Patient: $name',
                  style: const TextStyle(color: SovaColors.sage, fontSize: 14),
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ValueListenableBuilder<List<Medication>>(
                  valueListenable: AppState.allMedications,
                  builder: (_, meds, __) {
                    if (meds.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.medication_outlined,
                                size: 64, color: SovaColors.sensorNeutral),
                            const SizedBox(height: 16),
                            const Text('No medications added',
                                style: TextStyle(
                                    color: SovaColors.sage,
                                    fontWeight: FontWeight.w600)),
                            if (!_isReadOnly) ...[
                              const SizedBox(height: 8),
                              const Text('Tap + to add a medication',
                                  style: TextStyle(
                                      color: SovaColors.sage, fontSize: 13)),
                            ],
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: meds.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _MedCard(
                        med: meds[i],
                        readOnly: _isReadOnly,
                        onToggle: () => _toggleTaken(i),
                        onDelete: () => _deleteMed(i),
                      ).animate().fadeIn(delay: (i * 60).ms).slideY(begin: 0.1),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedCard extends StatelessWidget {
  final Medication med;
  final bool readOnly;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _MedCard({
    required this.med,
    required this.readOnly,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: med.isTaken
            ? SovaColors.success.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: med.isTaken
              ? SovaColors.success.withValues(alpha: 0.4)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(children: [
        // Checkbox — only interactive for caregiver
        GestureDetector(
          onTap: readOnly ? null : onToggle,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: med.isTaken ? SovaColors.success : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    med.isTaken ? SovaColors.success : SovaColors.sensorNeutral,
                width: 2,
              ),
            ),
            child: med.isTaken
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                med.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: SovaColors.charcoal,
                  decoration: med.isTaken ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.access_time, size: 13, color: SovaColors.sage),
                const SizedBox(width: 4),
                Text(med.time,
                    style:
                        const TextStyle(color: SovaColors.sage, fontSize: 13)),
              ]),
            ],
          ),
        ),
        // Delete — only for caregiver
        if (!readOnly)
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: SovaColors.danger, size: 20),
            onPressed: onDelete,
          ),
      ]),
    );
  }
}
