import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VisionPage  (Flutter Web)
//
//  Flow:
//    1. Opens the browser camera via getUserMedia → shows live <video> feed
//    2. Every 2s: captures frame as JPEG
//    3. Sends frame to THREE pipelines in parallel:
//       - Port 5002 → YOLO dangerous object detection → RED AR boxes
//       - Port 5000 → Face recognition → GREEN (known) / RED (unknown) AR boxes
//       - Port 5003 → Activity recognition (YOLO person + pose + SkateFormer
//                     + wandering + dangerous object detection)
//    4. Reads AppState.alertStatus → shows alert banner
// ─────────────────────────────────────────────────────────────────────────────

class VisionPage extends StatefulWidget {
  const VisionPage({super.key});
  @override
  State<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends State<VisionPage> {
  CameraController? _controller;
  bool _cameraReady = false;

  Timer? _frameTimer;
  bool _isSending = false;
  static const Duration _frameInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    if (cameras.isEmpty) return;
    try {
      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _startFrameLoop();
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _startFrameLoop() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(_frameInterval, (_) => _captureAndSend());
  }

  Future<void> _captureAndSend() async {
    if (_isSending || _controller == null || !_cameraReady) return;
    _isSending = true;
    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      // Fire all three pipelines in parallel — they run on different ports.
      ApiService.detectObjects(bytes);
      ApiService.analyzeFace(bytes);
      ApiService.processActivityFrame(bytes);
    } catch (_) {
      AppState.detectedObjects.value = [];
      AppState.detectedFaces.value = [];
      AppState.activityResult.value = ActivityResult.empty;
    } finally {
      _isSending = false;
    }
  }

  void _stopCamera() {
    _frameTimer?.cancel();
    _controller?.dispose();
    AppState.detectedObjects.value = [];
    AppState.detectedFaces.value = [];
    AppState.activityResult.value = ActivityResult.empty;
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. FULL SCREEN CAMERA FEED ────────────────────────────────────
          Positioned.fill(
            child: _cameraReady && _controller != null
                ? CameraPreview(_controller!)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // ── 2. OBJECT DETECTION AR BOXES (RED) ───────────────────────────
          if (_cameraReady)
            Positioned.fill(
              child: ValueListenableBuilder<List<DetectedObject>>(
                valueListenable: AppState.detectedObjects,
                builder: (context, objects, _) {
                  if (objects.isEmpty) return const SizedBox();
                  return CustomPaint(
                    painter: _ObjectBoxPainter(objects: objects),
                  );
                },
              ),
            ),

          // ── 3. FACE RECOGNITION AR BOXES (GREEN/RED) ─────────────────────
          if (_cameraReady)
            Positioned.fill(
              child: ValueListenableBuilder<List<DetectedFace>>(
                valueListenable: AppState.detectedFaces,
                builder: (context, faces, _) {
                  if (faces.isEmpty) return const SizedBox();
                  return CustomPaint(
                    painter: _FaceBoxPainter(faces: faces),
                  );
                },
              ),
            ),

          // ── 3b. PERSON BOUNDING BOXES (CYAN) from activity server ────────
          if (_cameraReady)
            Positioned.fill(
              child: ValueListenableBuilder<ActivityResult>(
                valueListenable: AppState.activityResult,
                builder: (context, result, _) {
                  if (result.personBoxes.isEmpty) return const SizedBox();
                  return CustomPaint(
                    painter: _PersonBoxPainter(boxes: result.personBoxes),
                  );
                },
              ),
            ),

          // ── 4. PATIENT + ACTIVITY INFO OVERLAY ───────────────────────────
          if (_cameraReady)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: _InfoOverlay(),
            ),

          // ── 5. ALERT BANNER ───────────────────────────────────────────────
          ValueListenableBuilder<AlertType>(
            valueListenable: AppState.alertStatus,
            builder: (context, alert, _) {
              if (alert == AlertType.none) return const SizedBox();
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: alert == AlertType.fall
                          ? SovaColors.danger
                          : SovaColors.coral,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            AppState.alertMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // ── 6. CLOSE BUTTON ───────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 7. AI STATUS BADGE ────────────────────────────────────────────
          Positioned(
            bottom: 32,
            right: 24,
            child: ValueListenableBuilder<List<DetectedObject>>(
              valueListenable: AppState.detectedObjects,
              builder: (context, objects, _) =>
                  ValueListenableBuilder<List<DetectedFace>>(
                valueListenable: AppState.detectedFaces,
                builder: (context, faces, _) => _AiStatusBadge(
                  isReady: _cameraReady,
                  objectCount: objects.length,
                  faceCount: faces.length,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _ObjectBoxPainter — RED boxes for dangerous objects
// ─────────────────────────────────────────────────────────────────────────────
class _ObjectBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;

  const _ObjectBoxPainter({required this.objects});

  @override
  void paint(Canvas canvas, Size size) {
    const color = Color(0xFFFF1744);

    for (final obj in objects) {
      final double x1 = obj.left * size.width;
      final double y1 = obj.top * size.height;
      final double x2 = obj.right * size.width;
      final double y2 = obj.bottom * size.height;
      final Rect box = Rect.fromLTRB(x1, y1, x2, y2);

      // Glow
      canvas.drawRect(
        box,
        Paint()
          ..color = color.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // Box
      canvas.drawRect(
        box,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      _drawCorners(canvas, box, color);

      final label =
          '${obj.label.toUpperCase()} ${(obj.confidence * 100).toStringAsFixed(0)}%';
      _drawLabel(canvas, label, color, Offset(x1, y1 - 24));
    }
  }

  void _drawCorners(Canvas canvas, Rect box, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    const double L = 16.0;
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(L, 0), p);
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(0, L), p);
    canvas.drawLine(box.topRight, box.topRight + const Offset(-L, 0), p);
    canvas.drawLine(box.topRight, box.topRight + const Offset(0, L), p);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(L, 0), p);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(0, -L), p);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(-L, 0), p);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(0, -L), p);
  }

  void _drawLabel(Canvas canvas, String text, Color color, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withOpacity(0.6),
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _ObjectBoxPainter old) => old.objects != objects;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _FaceBoxPainter — GREEN for known faces, RED for unknown faces
// ─────────────────────────────────────────────────────────────────────────────
class _FaceBoxPainter extends CustomPainter {
  final List<DetectedFace> faces;

  const _FaceBoxPainter({required this.faces});

  @override
  void paint(Canvas canvas, Size size) {
    for (final face in faces) {
      final color =
          face.isKnown ? const Color(0xFF00E676) : const Color(0xFFFF1744);

      final double x1 = face.left * size.width;
      final double y1 = face.top * size.height;
      final double x2 = face.right * size.width;
      final double y2 = face.bottom * size.height;
      final Rect box = Rect.fromLTRB(x1, y1, x2, y2);

      // Glow
      canvas.drawRect(
        box,
        Paint()
          ..color = color.withOpacity(0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Box
      canvas.drawRect(
        box,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      _drawCorners(canvas, box, color);

      final label =
          face.isKnown ? (face.name ?? 'Known').toUpperCase() : 'UNKNOWN';
      _drawLabel(canvas, label, color, Offset(x1, y2 + 6));
    }
  }

  void _drawCorners(Canvas canvas, Rect box, Color color) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;
    const double L = 14.0;
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(L, 0), p);
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(0, L), p);
    canvas.drawLine(box.topRight, box.topRight + const Offset(-L, 0), p);
    canvas.drawLine(box.topRight, box.topRight + const Offset(0, L), p);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(L, 0), p);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(0, -L), p);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(-L, 0), p);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(0, -L), p);
  }

  void _drawLabel(Canvas canvas, String text, Color color, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withOpacity(0.55),
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter old) => old.faces != faces;
}

//  _PersonBoxPainter — CYAN boxes for YOLO person detections (activity server)
class _PersonBoxPainter extends CustomPainter {
  final List<DetectedObject> boxes;

  const _PersonBoxPainter({required this.boxes});

  @override
  void paint(Canvas canvas, Size size) {
    const Color color = Color(0xFF00E5FF); // cyan
    for (final box in boxes) {
      final double x1 = box.left * size.width;
      final double y1 = box.top * size.height;
      final double x2 = box.right * size.width;
      final double y2 = box.bottom * size.height;
      final Rect rect = Rect.fromLTRB(x1, y1, x2, y2);

      // Dashed-style border via two paints
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: 'PERSON ${(box.confidence * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelBg = Rect.fromLTWH(
          x1,
          (y1 - tp.height - 4).clamp(0, size.height),
          tp.width + 12,
          tp.height + 4);
      canvas.drawRect(labelBg, Paint()..color = color.withOpacity(0.85));
      tp.paint(canvas, Offset(labelBg.left + 6, labelBg.top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PersonBoxPainter old) => old.boxes != boxes;
}

//  _AiStatusBadge

class _AiStatusBadge extends StatelessWidget {
  final bool isReady;
  final int objectCount;
  final int faceCount;

  const _AiStatusBadge({
    required this.isReady,
    required this.objectCount,
    required this.faceCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasDetection = objectCount > 0 || faceCount > 0;
    String label;
    Color color;

    if (!isReady) {
      label = 'STARTING CAMERA…';
      color = Colors.white38;
    } else if (objectCount > 0) {
      label = '$objectCount OBJECT${objectCount > 1 ? 'S' : ''} DETECTED';
      color = const Color(0xFFFF1744);
    } else if (faceCount > 0) {
      label = '$faceCount FACE${faceCount > 1 ? 'S' : ''} DETECTED';
      color = const Color(0xFF00E676);
    } else {
      label = 'AI SCANNING';
      color = Colors.white38;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_red_eye_outlined, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _InfoOverlay — patient identity + live activity recognition output
// ─────────────────────────────────────────────────────────────────────────────
class _InfoOverlay extends StatelessWidget {
  const _InfoOverlay();

  Color _colorForActivity(String? activity) {
    switch (activity) {
      case 'FALL':
      case 'CHEST_PAIN':
        return const Color(0xFFFF5252); // red — alert
      case 'WALK':
        return const Color(0xFF00E676); // green
      case 'SIT':
        return const Color(0xFFFFAB40); // orange
      case 'STAND':
        return const Color(0xFF40C4FF); // light blue
      case 'EAT':
      case 'DRINK':
        return const Color(0xFFFFD740); // yellow
      case 'SLEEP':
        return const Color(0xFF80DEEA); // cyan
      case 'USE_PHONE':
        return const Color(0xFFE040FB); // purple
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppState.patientName,
      builder: (_, name, __) => ValueListenableBuilder<ActivityResult>(
        valueListenable: AppState.activityResult,
        builder: (_, result, __) {
          final hasActivity =
              result.activity != null || result.bufferProgress > 0;
          if (name.isEmpty && !hasActivity) return const SizedBox.shrink();
          final actColor = _colorForActivity(result.activity);
          final isBuffering = result.bufferProgress < result.bufferTarget;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.person_pin,
                        color: Color(0xFF00E676), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Patient: $name',
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ]),
                if (hasActivity) ...[
                  if (name.isNotEmpty) const SizedBox(height: 4),
                  if (isBuffering)
                    Row(children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Collecting frames ${result.bufferProgress}/${result.bufferTarget}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ])
                  else
                    Row(children: [
                      Icon(Icons.directions_run, color: actColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        result.activity == null
                            ? 'UNCERTAIN  (${(result.confidence * 100).toStringAsFixed(1)}%)'
                            : '${result.activity}  (${(result.confidence * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(
                          color: actColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ]),
                  if (result.fallAlert)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: const [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFF5252), size: 14),
                        SizedBox(width: 6),
                        Text(
                          'FALL DETECTED',
                          style: TextStyle(
                            color: Color(0xFFFF5252),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]),
                    ),
                  if (result.wandering)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: const [
                        Icon(Icons.timeline,
                            color: Color(0xFFFFAB40), size: 14),
                        SizedBox(width: 6),
                        Text(
                          'WANDERING DETECTED',
                          style: TextStyle(
                            color: Color(0xFFFFAB40),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
