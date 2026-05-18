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
//    3. Sends frame to BOTH:
//       - Port 5001 → YOLO object detection → draws RED AR boxes
//       - Port 5000 → Face recognition → draws GREEN (known) or RED (unknown) AR boxes
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
      ApiService.detectObjects(bytes);
      ApiService.analyzeFace(bytes);
    } catch (_) {
      AppState.detectedObjects.value = [];
      AppState.detectedFaces.value = [];
    } finally {
      _isSending = false;
    }
  }

  void _stopCamera() {
    _frameTimer?.cancel();
    _controller?.dispose();
    AppState.detectedObjects.value = [];
    AppState.detectedFaces.value = [];
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

          // ── 4. ALERT BANNER ───────────────────────────────────────────────
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

          // ── 5. CLOSE BUTTON ───────────────────────────────────────────────
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

          // ── 6. AI STATUS BADGE ────────────────────────────────────────────
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
  bool shouldRepaint(covariant _ObjectBoxPainter old) =>
      old.objects != objects;
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
