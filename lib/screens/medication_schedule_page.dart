import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models/patient_models.dart';
import '../services/database_service.dart';

class MedicationSchedulePage extends StatelessWidget {
  const MedicationSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      body: ValueListenableBuilder<List<Medication>>(
        valueListenable: AppState.allMedications,
        builder: (context, meds, _) {
          return CustomScrollView(
            slivers: [
              // --- FIXED SLIVER APP BAR ---
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: SovaColors.bg,
                elevation: 0,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text(
                    "Medication Schedule",
                    style: TextStyle(
                      color: SovaColors.charcoal,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  titlePadding: EdgeInsets.only(left: 24, bottom: 16),
                  centerTitle: false,
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 150),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final med = meds[index];
                    return _buildMedCard(med, index);
                  }, childCount: meds.length),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMedCard(Medication med, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: med.isTaken
              ? SovaColors.success.withOpacity(0.2)
              : SovaColors.coral.withOpacity(0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: med.isTaken
                  ? SovaColors.success.withOpacity(0.1)
                  : SovaColors.coral.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.medication_liquid_rounded,
              color: med.isTaken ? SovaColors.success : SovaColors.coral,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  med.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                Text(
                  med.time,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // THE ACTION BUTTON
          GestureDetector(
            onTap: med.isTaken ? null : () => DatabaseService.markAsTaken(med),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: med.isTaken
                    ? SovaColors.success.withOpacity(0.1)
                    : SovaColors.coral,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  if (med.isTaken)
                    const Icon(
                      Icons.verified_rounded,
                      color: SovaColors.success,
                      size: 16,
                    ),
                  if (med.isTaken) const SizedBox(width: 6),
                  Text(
                    med.isTaken ? "Taken" : "Give Now",
                    style: TextStyle(
                      color: med.isTaken ? SovaColors.success : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.05);
  }
}
