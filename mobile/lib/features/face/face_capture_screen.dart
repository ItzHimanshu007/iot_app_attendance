import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_exception.dart';
import '../../core/config.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import 'face_embedder.dart';
import 'face_image.dart';
import 'liveness.dart';

enum FaceCaptureMode { enroll, verify }

/// What the camera step produces: face signatures (never images) plus the
/// liveness steps that were completed, in order.
class FaceCaptureResult {
  const FaceCaptureResult({required this.embeddings, required this.completedSteps});

  final List<List<double>> embeddings;
  final List<String> completedSteps;
}

/// Live camera → liveness steps → capture → on-device face signature.
///
/// There is deliberately no gallery/file picker anywhere in this app. The
/// captured JPEG lives in the app's temporary folder for well under a second
/// and is deleted right after the signature is computed.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({
    super.key,
    required this.mode,
    required this.steps,
    this.samples = 1,
    this.deadline,
    @visibleForTesting this.previewOnly = false,
  });

  final FaceCaptureMode mode;
  final List<String> steps;
  final int samples;
  final DateTime? deadline;

  /// Renders the UI without opening the camera (screenshots/tests only).
  final bool previewOnly;

  static Future<FaceCaptureResult?> open(
    BuildContext context, {
    required FaceCaptureMode mode,
    required List<String> steps,
    int samples = 1,
    DateTime? deadline,
  }) {
    return Navigator.of(context).push<FaceCaptureResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FaceCaptureScreen(mode: mode, steps: steps, samples: samples, deadline: deadline),
      ),
    );
  }

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

enum _Phase { starting, liveness, steady, capturing, failed }

enum _Ring { neutral, ok, good, warn }

class _RetryCapture implements Exception {
  const _RetryCapture(this.message);
  final String message;
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> with WidgetsBindingObserver {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final _streamDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );
  final _photoDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.15),
  );

  late final LivenessTracker _liveness;
  late final DateTime _deadline;
  CameraController? _controller;
  CameraDescription? _camera;
  FaceEmbedder? _embedder;
  Timer? _ticker;

  _Phase _phase = _Phase.starting;
  String _prompt = 'Starting camera…';
  String? _error;
  bool _busyFrame = false;
  bool _finished = false;
  int _steadyFrames = 0;
  int? _livenessFaceId;
  _Ring _ring = _Ring.neutral;
  final List<List<double>> _embeddings = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _liveness = LivenessTracker(
      widget.steps.map(LivenessStep.fromWire).whereType<LivenessStep>().toList(),
    );
    _deadline = widget.deadline ?? DateTime.now().add(AppConfig.livenessTimeout);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished || _phase == _Phase.failed) return;
      if (DateTime.now().isAfter(_deadline)) {
        _fail('Time is up. Please start again.');
      } else {
        setState(() {});
      }
    });
    if (widget.previewOnly) {
      _phase = _Phase.liveness;
      _prompt = _liveness.current?.instruction ?? 'Look straight at the camera';
      _ring = _Ring.ok;
      return;
    }
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controller?.dispose();
    _streamDetector.close();
    _photoDetector.close();
    _embedder?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_finished && _phase != _Phase.failed) {
      _fail('The camera was interrupted. Please start again.');
    }
  }

  // ── Setup ───────────────────────────────────────────────────────────────────

  Future<void> _start() async {
    try {
      if (!(await Permission.camera.request()).isGranted) {
        throw Exception('Camera permission is required to verify your face.');
      }
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front);
      if (front.isEmpty) throw Exception('No front camera found on this phone.');
      _camera = front.first;

      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _embedder = await FaceEmbedder.load();

      if (!mounted || _phase == _Phase.failed) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _phase = _liveness.isDone ? _Phase.steady : _Phase.liveness;
        _prompt = _liveness.current?.instruction ?? 'Look straight at the camera';
      });
      await controller.startImageStream(_onFrame);
    } catch (e) {
      _fail(errorMessage(e));
    }
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    if (_busyFrame || _finished || _phase == _Phase.capturing || _phase == _Phase.failed) return;
    _busyFrame = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _streamDetector.processImage(input);
      if (!mounted) return;
      _handleFaces(faces, math.min(image.width, image.height).toDouble());
    } catch (_) {
      // a dropped frame is harmless
    } finally {
      _busyFrame = false;
    }
  }

  void _handleFaces(List<Face> faces, double shortSide) {
    if (faces.isEmpty) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt('Place your face inside the oval');
    }
    if (faces.length > 1) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt('Only your face should be visible');
    }
    final face = faces.first;
    if (face.boundingBox.width < shortSide * 0.28) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt('Move a little closer');
    }

    if (_phase == _Phase.liveness) {
      _ring = _Ring.ok;
      if (_liveness.update(face)) HapticFeedback.lightImpact();
      _livenessFaceId = face.trackingId ?? _livenessFaceId;
      if (_liveness.isDone) {
        _phase = _Phase.steady;
        return _setPrompt('Great! Now look straight at the camera');
      }
      return _setPrompt(_liveness.current!.instruction);
    }

    // Steady phase: the same tracked face must still be in front of the camera.
    if (_livenessFaceId != null && face.trackingId != null && face.trackingId != _livenessFaceId) {
      _liveness.reset();
      _livenessFaceId = null;
      _phase = _liveness.isDone ? _Phase.steady : _Phase.liveness;
      return _setPrompt('Face changed — please repeat the steps');
    }
    if (LivenessTracker.isGoodCaptureFrame(face)) {
      _ring = _Ring.good;
      _steadyFrames++;
      _setPrompt('Hold still…');
      if (_steadyFrames >= 3) _capture();
    } else {
      _steadyFrames = 0;
      _ring = _Ring.neutral;
      _setPrompt('Look straight at the camera with your eyes open');
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;
    var rotation = _orientations[controller.value.deviceOrientation];
    if (rotation == null) return null;
    rotation = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + rotation) % 360
        : (camera.sensorOrientation - rotation + 360) % 360;
    final inputRotation = InputImageRotationValue.fromRawValue(rotation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (inputRotation == null || format != InputImageFormat.nv21 || image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: inputRotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ── Capture ─────────────────────────────────────────────────────────────────

  Future<void> _capture() async {
    final controller = _controller;
    final embedder = _embedder;
    if (controller == null || embedder == null || _phase == _Phase.capturing) return;
    setState(() {
      _phase = _Phase.capturing;
      _prompt = 'Capturing…';
    });

    XFile? shot;
    try {
      await controller.stopImageStream();
      shot = await controller.takePicture();
      final faces = await _photoDetector.processImage(InputImage.fromFilePath(shot.path));
      if (faces.length != 1) {
        throw const _RetryCapture('Keep only your face in view and hold still.');
      }
      final box = faces.first.boundingBox;
      final request = FaceCropRequest(
        path: shot.path,
        left: box.left,
        top: box.top,
        width: box.width,
        height: box.height,
        size: embedder.inputSize,
      );
      final pixels = await Isolate.run(() => preprocessFace(request));
      if (pixels == null) {
        throw const _RetryCapture('Could not read your face. Try again in better light.');
      }
      _embeddings.add(embedder.embed(pixels));
    } on _RetryCapture catch (e) {
      _prompt = e.message;
    } catch (e) {
      return _fail('Capture failed: ${errorMessage(e)}');
    } finally {
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
    }

    if (!mounted) return;
    if (_embeddings.length >= widget.samples) {
      _finished = true;
      Navigator.of(context).pop(
        FaceCaptureResult(
          embeddings: List.of(_embeddings),
          completedSteps: List.of(_liveness.completed),
        ),
      );
      return;
    }

    // More samples needed (enrollment) or the shot was unusable — keep going.
    setState(() {
      _phase = _Phase.steady;
      _steadyFrames = 0;
      if (_embeddings.isNotEmpty && widget.samples > 1) {
        _prompt =
            'Sample ${_embeddings.length + 1} of ${widget.samples} — keep looking at the camera';
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted && !_finished && _phase != _Phase.failed) {
      await controller.startImageStream(_onFrame);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setPrompt(String text) {
    if (!mounted || text == _prompt) return;
    setState(() => _prompt = text);
  }

  void _fail(String message) {
    if (!mounted || _finished) return;
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      controller.stopImageStream().catchError((_) {});
    }
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  Color get _ringColor => switch (_ring) {
    _Ring.good => const Color(0xFF22C55E),
    _Ring.warn => AppColors.gold,
    _Ring.ok => const Color(0xFF93C5FD),
    _Ring.neutral => Colors.white70,
  };

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final remaining = _deadline.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final failed = _phase == _Phase.failed;
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null && controller.value.isInitialized)
                  Center(child: CameraPreview(controller))
                else if (widget.previewOnly)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Icon(Icons.face_rounded, size: 160, color: Color(0x33FFFFFF)),
                    ),
                  )
                else if (!failed)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                IgnorePointer(
                  child: CustomPaint(painter: _OvalMaskPainter(ringColor: _ringColor)),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Cancel',
                            color: Colors.white,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.mode == FaceCaptureMode.enroll
                                  ? 'Face enrollment'
                                  : 'Face verification',
                              style: AppText.h3.copyWith(color: Colors.white),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: remaining <= 15
                                  ? AppColors.error.withValues(alpha: 0.85)
                                  : Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, size: 15, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  '${remaining}s',
                                  style: AppText.caption.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildPanel(context),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final failed = _phase == _Phase.failed;
    final total = _liveness.steps.length + (widget.samples > 1 ? 1 : 0);
    final doneSteps =
        _liveness.progress + (widget.samples > 1 && _embeddings.length >= widget.samples ? 1 : 0);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!failed && total > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: i == doneSteps ? 26 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i < doneSteps
                            ? const Color(0xFF22C55E)
                            : i == doneSteps
                            ? Colors.white
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (failed) const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5), size: 34),
            Text(
              failed ? (_error ?? 'Something went wrong') : _prompt,
              textAlign: TextAlign.center,
              style: AppText.h2.copyWith(
                color: failed ? const Color(0xFFFCA5A5) : Colors.white,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _liveness.steps.length; i++)
                  _StepChip(
                    label: _liveness.steps[i].label,
                    done: i < _liveness.progress,
                    active: i == _liveness.progress && _phase == _Phase.liveness,
                  ),
                if (widget.samples > 1)
                  _StepChip(
                    label: 'Photos ${_embeddings.length}/${widget.samples}',
                    done: _embeddings.length >= widget.samples,
                    active: _phase == _Phase.steady || _phase == _Phase.capturing,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Processed on this phone. Your photo is never stored or uploaded.',
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (failed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.text,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF22C55E)
        : active
        ? Colors.white
        : Colors.white38;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: done || active ? 0.9 : 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.circle_outlined, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppText.heading,
              fontSize: 12.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Darkens everything except an oval guide; the ring colour reflects face quality.
class _OvalMaskPainter extends CustomPainter {
  const _OvalMaskPainter({required this.ringColor});

  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.47),
      width: size.width * 0.70,
      height: size.height * 0.60,
    );
    final mask = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(oval),
    );
    canvas.drawPath(mask, Paint()..color = const Color(0xFF020617).withValues(alpha: 0.62));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = ringColor,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalMaskPainter oldDelegate) => oldDelegate.ringColor != ringColor;
}
