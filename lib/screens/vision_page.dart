import 'dart:async';
import 'dart:typed_data';
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  VisionPage  (Flutter Web)
//
//  Flow:
//    1. Opens the browser camera via getUserMedia → shows live <video> feed
//    2. Every 2 s: draws the video frame onto a <canvas>, exports as JPEG blob
//    3. Calls ApiService.ingestFrame() → POST /api/frames/ingest (Django)
//    4. Reads AppState.detectedFaces → draws AR boxes with CustomPaint
//    5. Reads AppState.alertStatus   → shows alert banner (also on HomePage)
// ─────────────────────────────────────────────────────────────────────────────

class VisionPage extends StatefulWidget {
  const VisionPage({super.key});
  @override
  State<VisionPage> createState() => _VisionPageState();
}

class _VisionPageState extends State<VisionPage> {
  // ── Web camera elements ────────────────────────────────────────────────────
  html.VideoElement? _video;
  html.MediaStream? _stream;
  String _viewId = '';
  bool _cameraReady = false;

  // ── Frame loop ─────────────────────────────────────────────────────────────
  Timer? _frameTimer;
  bool _isSending = false;
  static const Duration _frameInterval = Duration(seconds: 2);

  // ── Actual video dimensions (set once video metadata loads) ────────────────
  double _videoWidth = 1.0;
  double _videoHeight = 1.0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      _viewId = 'vision-camera-${DateTime.now().millisecondsSinceEpoch}';

      _video = html.VideoElement()
        ..autoplay = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)'; // un-mirror the front camera

      // Register with Flutter's platform view registry
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int id) => _video!,
      );

      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) throw Exception('Camera not supported');

      _stream = await js_util.promiseToFuture<html.MediaStream>(
        js_util.callMethod(mediaDevices, 'getUserMedia', [
          js_util.jsify({'video': true, 'audio': false}),
        ]),
      );

      _video!.srcObject = _stream;

      // Wait for video to have real dimensions before capturing frames
      _video!.onLoadedMetadata.listen((_) {
        _videoWidth = _video!.videoWidth.toDouble();
        _videoHeight = _video!.videoHeight.toDouble();
        if (!mounted) return;
        setState(() => _cameraReady = true);
        _startFrameLoop();
      });
    } catch (e) {
      if (mounted) setState(() => _cameraReady = false);
    }
  }

  void _startFrameLoop() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(_frameInterval, (_) => _captureAndSend());
  }

  /// Draws the current video frame onto a hidden <canvas>, exports as JPEG,
  /// then hands the bytes to ApiService which does all HTTP + AppState writing.
  Future<void> _captureAndSend() async {
    if (_isSending || _video == null || !_cameraReady) return;
    if (_videoWidth <= 1 || _videoHeight <= 1) return;

    _isSending = true;
    try {
      // Draw current video frame to an off-screen canvas
      final canvas = html.CanvasElement(
        width: _videoWidth.toInt(),
        height: _videoHeight.toInt(),
      );
      final ctx = canvas.context2D;
      ctx.drawImage(_video!, 0, 0);

      // Export as JPEG blob
      final completer = Completer<html.Blob>();
      js_util.callMethod(canvas, 'toBlob', [
        js_util.allowInterop((html.Blob? blob) {
          if (blob != null) {
            completer.complete(blob);
          } else {
            completer.completeError('toBlob returned null');
          }
        }),
        'image/jpeg',
        0.85, // quality
      ]);

      final blob = await completer.future;

      // Convert Blob → Uint8List
      final reader = html.FileReader();
      final readerCompleter = Completer<Uint8List>();
      reader.onLoadEnd.listen((_) {
        final result = reader.result;
        if (result is Uint8List) {
          readerCompleter.complete(result);
        } else {
          readerCompleter.completeError('FileReader result was not Uint8List');
        }
      });
      reader.readAsArrayBuffer(blob);
      final bytes = await readerCompleter.future;

      final patientId = AppState.patientId.value ?? '1';

      // Hand off to ApiService — it POSTs to Django, parses faces, updates AppState
      await ApiService.ingestFrame(bytes, patientId: patientId);
    } catch (_) {
      // On any error just clear stale boxes
      AppState.detectedFaces.value = [];
    } finally {
      _isSending = false;
    }
  }

  void _stopCamera() {
    _frameTimer?.cancel();
    _stream?.getTracks().forEach((t) => t.stop());
    _stream = null;
    _video?.srcObject = null;
    AppState.detectedFaces.value = [];
  }

  @override
  void dispose() {
    _stopCamera();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. FULL SCREEN CAMERA FEED ────────────────────────────────────
          Positioned.fill(
            child: _cameraReady
                ? HtmlElementView(viewType: _viewId)
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // ── 2. AR BOUNDING BOXES ──────────────────────────────────────────
          // Green = known face,  Red = unknown face
          // Written by ApiService into AppState.detectedFaces
          if (_cameraReady)
            Positioned.fill(
              child: ValueListenableBuilder<List<DetectedFace>>(
                valueListenable: AppState.detectedFaces,
                builder: (context, faces, _) {
                  if (faces.isEmpty) return const SizedBox();
                  return CustomPaint(
                    painter: _FaceBoxPainter(
                      faces: faces,
                      videoWidth: _videoWidth,
                      videoHeight: _videoHeight,
                    ),
                  );
                },
              ),
            ),

          // ── 3. ALERT BANNER ───────────────────────────────────────────────
          // Same AppState.alertStatus notifier that HomePage listens to,
          // so the alert fires on BOTH screens simultaneously.
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

          // ── 4. CLOSE BUTTON ───────────────────────────────────────────────
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

          // ── 5. AI STATUS BADGE ────────────────────────────────────────────
          Positioned(
            bottom: 32,
            right: 24,
            child: ValueListenableBuilder<List<DetectedFace>>(
              valueListenable: AppState.detectedFaces,
              builder: (context, faces, _) => _AiStatusBadge(
                isReady: _cameraReady,
                faceCount: faces.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _FaceBoxPainter
//
//  Draws green (known) or red (unknown) AR boxes + name labels.
//  Coordinates from Django are normalised 0.0–1.0 relative to video size.
//  The painter maps them to the actual screen size of the view.
// ─────────────────────────────────────────────────────────────────────────────
class _FaceBoxPainter extends CustomPainter {
  final List<DetectedFace> faces;
  final double videoWidth;
  final double videoHeight;

  const _FaceBoxPainter({
    required this.faces,
    required this.videoWidth,
    required this.videoHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The video is rendered with objectFit:cover so we need to match that
    // scaling: find how the video fills the screen (cover = crop to fill).
    final double videoAspect = videoWidth / videoHeight;
    final double screenAspect = size.width / size.height;

    double scale, offsetX = 0, offsetY = 0;
    if (videoAspect > screenAspect) {
      // Video is wider — scale to fill height, crop sides
      scale = size.height / videoHeight;
      offsetX = (size.width - videoWidth * scale) / 2;
    } else {
      // Video is taller — scale to fill width, crop top/bottom
      scale = size.width / videoWidth;
      offsetY = (size.height - videoHeight * scale) / 2;
    }

    for (final face in faces) {
      final color = face.isKnown
          ? const Color(0xFF00E676) // bright green
          : const Color(0xFFFF1744); // bright red

      // Map normalised coords → screen pixels
      // X coordinates are mirrored because the video has scaleX(-1) applied
      final double x1 = (1.0 - face.right) * videoWidth * scale + offsetX;
      final double y1 = face.top * videoHeight * scale + offsetY;
      final double x2 = (1.0 - face.left) * videoWidth * scale + offsetX;
      final double y2 = face.bottom * videoHeight * scale + offsetY;
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

      // Box outline
      canvas.drawRect(
        box,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );

      // Corner accents for AR look
      _drawCorners(canvas, box, color);

      // Name label below box
      final label = face.isKnown
          ? (face.name ?? 'Known').toUpperCase()
          : 'UNKNOWN';
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
  bool shouldRepaint(covariant _FaceBoxPainter old) =>
      old.faces != faces ||
      old.videoWidth != videoWidth ||
      old.videoHeight != videoHeight;
}

// ─────────────────────────────────────────────────────────────────────────────
//  _AiStatusBadge
// ─────────────────────────────────────────────────────────────────────────────
class _AiStatusBadge extends StatelessWidget {
  final bool isReady;
  final int faceCount;
  const _AiStatusBadge({required this.isReady, required this.faceCount});

  @override
  Widget build(BuildContext context) {
    final active = faceCount > 0;
    final label = !isReady
        ? 'STARTING CAMERA…'
        : active
        ? '$faceCount FACE${faceCount > 1 ? 'S' : ''} DETECTED'
        : 'AI SCANNING';
    final color = active ? const Color(0xFF00E676) : Colors.white38;

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
