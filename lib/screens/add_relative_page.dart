import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';

// Web-specific imports
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;

class AddRelativePage extends StatefulWidget {
  const AddRelativePage({super.key});

  @override
  State<AddRelativePage> createState() => _AddRelativePageState();
}

class _AddRelativePageState extends State<AddRelativePage>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────
  final _nameController = TextEditingController();

  // Steps: idle → naming → previewing → recording → uploading → done → error
  _Step _step = _Step.idle;
  String _statusMessage = "";
  String _errorMessage = "";
  int _secondsLeft = 13;
  Timer? _recordTimer;

  late AnimationController _pulseController;
  late AnimationController _circleController;

  // Web camera
  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];
  String _viewId = "";
  bool _cameraReady = false;

  static const String _aiUrl = "http://localhost:5000";

  // ── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 13),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _pulseController.dispose();
    _circleController.dispose();
    _stopCamera();
    _nameController.dispose();
    super.dispose();
  }

  // ── Camera helpers ─────────────────────────────────────────────────────
  Future<void> _startCamera() async {
    try {
      _viewId = 'camera-preview-${DateTime.now().millisecondsSinceEpoch}';

      _videoElement = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.borderRadius = '50%';

      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) => _videoElement!,
      );

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) throw Exception("Camera not available");

      _stream = await js_util.promiseToFuture<html.MediaStream>(
        js_util.callMethod(mediaDevices, 'getUserMedia', [
          js_util.jsify({'video': true, 'audio': false}),
        ]),
      );

      _videoElement!.srcObject = _stream;

      setState(() => _cameraReady = true);
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = "Could not open camera: $e";
      });
    }
  }

  void _stopCamera() {
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _videoElement?.srcObject = null;
  }

  // ── Recording ──────────────────────────────────────────────────────────
  void _startRecording() {
    if (_stream == null) return;
    _chunks.clear();

    _recorder = html.MediaRecorder(_stream!, {'mimeType': 'video/webm'});
    _recorder!.addEventListener('dataavailable', (event) {
      final blob = js_util.getProperty(event, 'data') as html.Blob;
      if (blob.size > 0) _chunks.add(blob);
    });

    _recorder!.start(1000); // collect every 1s

    setState(() {
      _step = _Step.recording;
      _secondsLeft = 13;
    });

    _circleController.forward(from: 0);

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _finishRecording();
      }
    });
  }

  Future<void> _finishRecording() async {
    _recorder?.stop();
    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      _step = _Step.uploading;
      _statusMessage = "Analysing your face…";
    });

    await _uploadVideo();
  }

  // ── Upload ─────────────────────────────────────────────────────────────
  Future<void> _uploadVideo() async {
    try {
      final blob = html.Blob(_chunks, 'video/webm');
      final name = _nameController.text.trim().toLowerCase();

      final formData = html.FormData();
      formData.appendBlob('video', blob, 'recording.webm');
      formData.append('person_name', name);

      final xhr = html.HttpRequest();
      final completer = Completer<void>();

      xhr.open('POST', '$_aiUrl/enroll-relative');
      xhr.onLoad.listen((_) {
        if (xhr.status == 200) {
          setState(() => _step = _Step.done);
        } else {
          setState(() {
            _step = _Step.error;
            _errorMessage = "Server error ${xhr.status}: ${xhr.responseText}";
          });
        }
        completer.complete();
      });
      xhr.onError.listen((_) {
        setState(() {
          _step = _Step.error;
          _errorMessage =
              "Upload failed. Is the AI server running on port 5000?";
        });
        completer.complete();
      });

      xhr.send(formData);
      await completer.future;
    } catch (e) {
      setState(() {
        _step = _Step.error;
        _errorMessage = "Upload error: $e";
      });
    } finally {
      _stopCamera();
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SovaColors.bg,
      appBar: AppBar(
        backgroundColor: SovaColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: SovaColors.charcoal,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Add Relative",
          style: SovaTheme.textTheme.labelMedium?.copyWith(
            color: SovaColors.charcoal,
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.idle:
        return _buildIdleStep();
      case _Step.naming:
        return _buildNamingStep();
      case _Step.previewing:
      case _Step.recording:
        // Both states use the same widget so the camera never remounts
        return _buildPreviewStep();
      case _Step.uploading:
        return _buildUploadingStep();
      case _Step.done:
        return _buildDoneStep();
      case _Step.error:
        return _buildErrorStep();
    }
  }

  // ── Step: idle ─────────────────────────────────────────────────────────
  Widget _buildIdleStep() {
    return Padding(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: SovaColors.navy,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.face_retouching_natural,
              color: Colors.white,
              size: 56,
            ),
          ).animate().scale(delay: 100.ms),
          const SizedBox(height: 32),
          Text(
            "Register a Relative",
            style: SovaTheme.textTheme.displayMedium?.copyWith(fontSize: 26),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 16),
          Text(
            "We'll record a 13-second video of your face.\nSlowly rotate your head in a circle so the AI can learn all angles.",
            style: const TextStyle(
              color: SovaColors.sage,
              fontSize: 15,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 48),
          _bigButton(
            label: "Get Started",
            color: SovaColors.charcoal,
            onTap: () => setState(() => _step = _Step.naming),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }

  // ── Step: naming ───────────────────────────────────────────────────────
  Widget _buildNamingStep() {
    return Padding(
      key: const ValueKey('naming'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Who is this person?",
            style: SovaTheme.textTheme.displayMedium?.copyWith(fontSize: 26),
          ).animate().fadeIn(),
          const SizedBox(height: 8),
          const Text(
            "Enter their name so the AI can identify them later.",
            style: TextStyle(color: SovaColors.sage, fontSize: 14),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 100.ms),
          const SizedBox(height: 40),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: "e.g. John, Sister, Dad",
                prefixIcon: Icon(Icons.person_outline),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 32),
          _bigButton(
            label: "Open Camera",
            color: SovaColors.navy,
            onTap: () async {
              final name = _nameController.text.trim();
              if (name.isEmpty) return;
              setState(() => _step = _Step.previewing);
              await _startCamera();
            },
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  // ── Step: previewing + recording (merged so the camera never remounts) ──
  // Both _Step.previewing and _Step.recording render this same widget.
  // Using the same ValueKey('camera') means Flutter never tears down the
  // HtmlElementView — the <video> element stays alive across setState calls,
  // which prevents the feed from freezing when recording starts.
  Widget _buildPreviewStep() {
    final isRecording = _step == _Step.recording;

    return Padding(
      key: const ValueKey('camera'), // same key for both states = no remount
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Top label: animates between preview and rec ─────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isRecording
                ? Column(
                    key: const ValueKey('rec-label'),
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, __) => Text(
                          "● REC",
                          style: TextStyle(
                            color: Color.lerp(
                              SovaColors.danger,
                              Colors.red.shade900,
                              _pulseController.value,
                            ),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Slowly rotate your head in a circle",
                        style: TextStyle(color: SovaColors.sage, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('preview-label'),
                    children: [
                      Text(
                        "Position your face",
                        style: SovaTheme.textTheme.displayMedium?.copyWith(
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Make sure your face is centered, then press Record.\nSlowly rotate your head in a full circle during recording.",
                        style: TextStyle(
                          color: SovaColors.sage,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 32),

          // ── Camera circle — always mounted, never swapped ───────────────
          Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _cameraCircle(showRecordRing: isRecording),
                  // Countdown badge — only visible while recording
                  if (isRecording)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "$_secondsLeft s",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Bottom: animates between button and status text ─────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isRecording
                ? const Text(
                    key: ValueKey('rec-status'),
                    "Recording in progress…",
                    style: TextStyle(color: SovaColors.sage, fontSize: 13),
                  )
                : _cameraReady
                ? _bigButton(
                    label: "Start Recording (13s)",
                    color: SovaColors.danger,
                    onTap: _startRecording,
                  ).animate().fadeIn()
                : const CircularProgressIndicator(color: SovaColors.sage),
          ),
        ],
      ),
    );
  }

  // _buildRecordingStep removed — its logic lives inside _buildPreviewStep above.

  // ── Step: uploading ────────────────────────────────────────────────────
  Widget _buildUploadingStep() {
    return Center(
      key: const ValueKey('uploading'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: SovaColors.navy),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: const TextStyle(color: SovaColors.sage, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── Step: done ─────────────────────────────────────────────────────────
  Widget _buildDoneStep() {
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(
              color: SovaColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 56,
            ),
          ).animate().scale(),
          const SizedBox(height: 32),
          Text(
            "${_nameController.text.trim()} has been registered!",
            style: SovaTheme.textTheme.displayMedium?.copyWith(fontSize: 24),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 12),
          const Text(
            "The AI will now recognise this person.\nYou'll be alerted if an unknown face appears.",
            style: TextStyle(color: SovaColors.sage, fontSize: 14, height: 1.6),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 48),
          _bigButton(
            label: "Add Another",
            color: SovaColors.navy,
            onTap: () {
              _nameController.clear();
              _chunks.clear();
              setState(() {
                _step = _Step.idle;
                _cameraReady = false;
              });
            },
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Back to Home",
              style: TextStyle(color: SovaColors.sage),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step: error ────────────────────────────────────────────────────────
  Widget _buildErrorStep() {
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: SovaColors.danger,
            size: 72,
          ),
          const SizedBox(height: 24),
          Text(
            "Something went wrong",
            style: SovaTheme.textTheme.displayMedium?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            style: const TextStyle(color: SovaColors.sage, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _bigButton(
            label: "Try Again",
            color: SovaColors.charcoal,
            onTap: () {
              _chunks.clear();
              setState(() {
                _step = _Step.idle;
                _cameraReady = false;
                _errorMessage = "";
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────────
  Widget _cameraCircle({required bool showRecordRing}) {
    return AnimatedBuilder(
      animation: _circleController,
      builder: (_, child) {
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Red progress ring while recording
              if (showRecordRing)
                SizedBox(
                  width: 300,
                  height: 300,
                  child: CircularProgressIndicator(
                    value: _circleController.value,
                    strokeWidth: 4,
                    color: SovaColors.danger,
                    backgroundColor: Colors.white24,
                  ),
                ),
              // Camera feed in circle
              ClipOval(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: _cameraReady
                      ? HtmlElementView(viewType: _viewId)
                      : Container(
                          color: SovaColors.charcoal,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: SovaColors.sage,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bigButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { idle, naming, previewing, recording, uploading, done, error }
