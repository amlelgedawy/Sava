import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import '../../main.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../services/api_service.dart';
import '../../services/database_service.dart';

class CreatePatientPage extends StatefulWidget {
  const CreatePatientPage({super.key});
  @override
  State<CreatePatientPage> createState() => _CreatePatientPageState();
}

class _CreatePatientPageState extends State<CreatePatientPage> {
  final _pageController = PageController();
  int _step = 0;
  bool _loading = false;

  // Step 0 – Patient Info
  final _nameCtrl = TextEditingController();
  DateTime? _dob;
  String _gender = 'MALE';
  final _medCtrl = TextEditingController();
  String? _error0;

  // Step 1 – Patient Face Video
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _videoRecorded = false;
  bool _recording = false;
  int _countdown = 13;
  String _aiUrl = "https://face-recognition-production-e71d.up.railway.app";
  XFile? _recordedVideo;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _medCtrl.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !_validateStep0()) return;
    if (_step == 1) {
      _submit();
      return;
    }
    setState(() => _step++);
    _pageController.animateToPage(_step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _back() {
    if (_step == 0) {
      Navigator.pop(context);
      return;
    }
    if (_step == 1) {
      _stopCamera();
    }
    setState(() => _step--);
    _pageController.animateToPage(_step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  bool _validateStep0() {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error0 = 'Patient name is required');
      return false;
    }
    if (_dob == null) {
      setState(() => _error0 = 'Date of birth is required');
      return false;
    }
    setState(() => _error0 = null);
    return true;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 70),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _startCamera() async {
    if (cameras.isEmpty) return;
    try {
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (_) {
      setState(() => _cameraReady = false);
    }
  }

  void _stopCamera() {
    _cameraController?.dispose();
    _cameraController = null;
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _recording = true;
        _countdown = 13;
      });
      for (int i = 13; i >= 0; i--) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() => _countdown = i);
      }
      _recordedVideo = await _cameraController!.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _videoRecorded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recording = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final relativeId = AppState.userId.value;
      if (relativeId == null) throw 'No user ID';

      final dobStr =
          '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}';

      final patient = await ApiService.createPatient(
        relativeId: relativeId,
        name: _nameCtrl.text.trim(),
        dateOfBirth: dobStr,
        gender: _gender,
        currentMedication:
            _medCtrl.text.trim().isNotEmpty ? _medCtrl.text.trim() : null,
      );

      final patientId = patient['id'].toString();
      final patientName = patient['name'] as String? ?? '';
      AppState.patientId.value = patientId;
      AppState.patientName.value = patientName;

      // Upload patient face video to AI server (non-blocking)
      if (_recordedVideo != null) {
        try {
          final bytes = await _recordedVideo!.readAsBytes();
          final name = _nameCtrl.text.trim().toLowerCase();
          final req = http.MultipartRequest(
              'POST', Uri.parse('$_aiUrl/enroll-patient'));
          req.files.add(http.MultipartFile.fromBytes('video', bytes,
              filename: 'recording.mp4'));
          req.fields['person_name'] = name;
          req.fields['patient_id'] = patientId;
          await req.send().timeout(const Duration(seconds: 10));
        } catch (_) {
          // Video upload failed, but continue
        }
      }

      DatabaseService.refreshDashboard();
      DatabaseService.fetchActivityHistory();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error0 = e.toString();
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = false;
      _step = 2;
    });
    _pageController.animateToPage(2,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _step < 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: SovaColors.charcoal, size: 20),
                onPressed: _back,
              )
            : null,
      ),
      body: Column(
        children: [
          if (_step < 2) _stepBar(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0(),
                _buildStep1(),
                _buildDone(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: List.generate(2, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              decoration: BoxDecoration(
                color: done
                    ? SovaColors.success
                    : active
                        ? SovaColors.coral
                        : SovaColors.sensorNeutral,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Step 0: Patient Info ─────────────────────────────────────────────────

  Widget _buildStep0() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEW PATIENT', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('Patient Information', style: SovaTheme.textTheme.displayMedium),
          Text('Step 1 of 2',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 32),
          _field(_nameCtrl, 'Patient Full Name', Icons.person_outline),
          const SizedBox(height: 16),
          // DOB picker
          GestureDetector(
            onTap: _pickDob,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(28)),
              child: Row(children: [
                Icon(Icons.calendar_today_outlined, color: SovaColors.sage),
                const SizedBox(width: 12),
                Text(
                  _dob != null
                      ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                      : 'Date of Birth',
                  style: TextStyle(
                    color: _dob != null ? SovaColors.charcoal : SovaColors.sage,
                    fontSize: 16,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          // Gender selector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: Row(children: [
              Icon(Icons.wc_outlined, color: SovaColors.sage),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _gender,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'MALE', child: Text('Male')),
                      DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _gender = v);
                    },
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _field(_medCtrl, 'Current Medication (optional)',
              Icons.medication_outlined),
          if (_error0 != null) _errorText(_error0!),
          const SizedBox(height: 32),
          _primaryBtn('Continue', _next),
        ],
      ),
    );
  }

  // ── Step 1: Patient Face Video ───────────────────────────────────────────

  Widget _buildStep1() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cameraController == null) _startCamera();
    });

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEW PATIENT', style: SovaTheme.textTheme.labelMedium),
          const SizedBox(height: 8),
          Text("Patient's Face Video",
              style: SovaTheme.textTheme.displayMedium),
          Text('Step 2 of 2',
              style: TextStyle(color: SovaColors.sage, fontSize: 14)),
          const SizedBox(height: 12),
          Text(
            'Record a 10–15 second video of the patient\'s face for identification.',
            style: TextStyle(color: SovaColors.sage, height: 1.5),
          ),
          const Spacer(),
          Center(
            child: SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: _cameraReady && _cameraController != null
                        ? CameraPreview(_cameraController!)
                        : const Center(
                            child: CircularProgressIndicator(
                                color: SovaColors.coral),
                          ),
                  ),
                  if (_recording)
                    Text(
                      '$_countdown',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(blurRadius: 12, color: Colors.black54)
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!_videoRecorded)
            _primaryBtn('Start Recording (13s)', _startRecording,
                color: SovaColors.coral)
          else
            _primaryBtn(
                'Re-record', () => setState(() => _videoRecorded = false),
                color: SovaColors.navy),
          const Spacer(),
          _primaryBtn(
            _loading ? 'Creating Patient...' : 'Create Patient',
            _loading ? null : _next,
            color: SovaColors.coral,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loading ? null : _next,
              child: Text('Skip video for now',
                  style: TextStyle(color: SovaColors.sage, fontSize: 13)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Step 2: Done ─────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: SovaColors.success.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: SovaColors.success, size: 56),
            ).animate().scale(delay: 200.ms),
            const SizedBox(height: 32),
            Text('Patient Created!',
                style: SovaTheme.textTheme.displayMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'You can now monitor ${AppState.patientName.value} and assign a caregiver.',
              style: TextStyle(color: SovaColors.sage, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            _primaryBtn('Done', () {
              Navigator.pop(context, true);
            }, color: SovaColors.coral),
          ],
        ).animate().fadeIn(delay: 100.ms),
      ),
    );
  }

  // ── Shared Widgets ───────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? type,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(28)),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: SovaColors.sage),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(msg, style: const TextStyle(color: SovaColors.danger)),
      );

  Widget _primaryBtn(String label, VoidCallback? onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: color ?? SovaColors.charcoal,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: _loading && label.contains('...')
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
        ),
      ),
    );
  }
}
