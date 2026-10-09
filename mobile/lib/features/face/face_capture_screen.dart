import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';

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

/// Live camera → liveness steps → face signature, all on the phone.
///
/// The face is cut out of the live preview frame that is already in memory and
/// turned into a 192-number signature. No photo is taken, nothing is written
/// to storage, and there is no gallery or file picker anywhere in the app.
///
/// Built for cheap phones: it works on 480p preview frames, turns the screen
/// into a fill light when the face is dark, tolerates ML Kit briefly losing the
/// face, and says why if the camera never delivers usable frames.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({
    super.key,
    required this.mode,
    required this.steps,
    this.samples = 1,
    this.deadline,
    @visibleForTesting this.previewOnly = false,
    @visibleForTesting this.previewFillLight = false,
  });

  final FaceCaptureMode mode;
  final List<String> steps;
  final int samples;
  final DateTime? deadline;

  /// Renders the UI without opening the camera (screenshots/tests only).
  final bool previewOnly;

  /// With [previewOnly]: show the low-light (white fill light) look.
  final bool previewFillLight;

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

  /// Face darker than this (average luma, 0–255) → white screen as a fill light.
  static const _fillLightLuma = 70.0;

  /// Face crops darker than this are not used.
  static const _tooDarkLuma = 35.0;

  /// The face captured at the end must match the face that did the liveness
  /// steps at least this well. The same person seconds apart scores far higher;
  /// two different people almost never reach it. This catches a photo swap.
  static const _sameFaceSimilarity = 0.4;

  static const _darkPrompt = 'Too dark. Face a light or move to a brighter place';

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  late final LivenessTracker _liveness;
  late final DateTime _deadline;
  CameraController? _controller;
  CameraDescription? _camera;
  FaceEmbedder? _embedder;
  Timer? _ticker;
  Timer? _watchdog;

  _Phase _phase = _Phase.starting;
  String _prompt = 'Starting camera…';
  String? _error;
  bool _busyFrame = false;
  bool _finished = false;
  int _steadyFrames = 0;
  DateTime? _nextSampleAt;
  _Ring _ring = _Ring.neutral;
  bool _fillLight = false;
  bool _brightnessChanged = false;
  int _darkFrames = 0;
  List<double>? _anchor;
  final List<List<double>> _embeddings = [];

  // Diagnostics for the watchdog.
  int _framesSeen = 0;
  int _framesDone = 0;
  String? _unsupportedFormat;
  Object? _lastFrameError;

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
      _fillLight = widget.previewFillLight;
      _prompt = widget.previewFillLight
          ? _darkPrompt
          : (_liveness.current?.instruction ?? 'Look straight at the camera');
      _ring = widget.previewFillLight ? _Ring.warn : _Ring.ok;
      return;
    }
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _watchdog?.cancel();
    _controller?.dispose();
    _detector.close();
    _embedder?.close();
    if (_brightnessChanged) {
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    }
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

      // 480p preview: enough detail for a 112 px face signature and light
      // enough for slow phones to analyse several frames per second.
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
      _watchdog = Timer(const Duration(seconds: 8), _checkFramesArrive);
    } catch (e) {
      _fail(errorMessage(e));
    }
  }

  /// Fails with a clear reason instead of waiting forever on a phone whose
  /// camera or face detector does not work with this app.
  void _checkFramesArrive() {
    if (_framesDone > 0 || _finished || _phase == _Phase.failed) return;
    final String reason;
    if (_framesSeen == 0) {
      reason =
          'The camera is not sending pictures. Close other apps using the camera and try again.';
    } else if (_unsupportedFormat != null) {
      reason =
          'This phone\'s camera format ($_unsupportedFormat) is not supported. '
          'Please tell the administrator.';
    } else {
      final detail = _lastFrameError == null ? '' : ' (${errorMessage(_lastFrameError!)})';
      reason = 'Face detection is not working on this phone$detail. Restart the app and try again.';
    }
    _fail(reason);
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    _framesSeen++;
    if (_busyFrame || _finished || _phase == _Phase.capturing || _phase == _Phase.failed) return;
    _busyFrame = true;
    try {
      final frame = _toFrame(image);
      if (frame == null) return;
      final faces = await _detector.processImage(_toInputImage(frame));
      _framesDone++;
      if (!mounted || _finished || _phase == _Phase.failed) return;
      _handleFaces(frame, faces);
    } catch (e) {
      _lastFrameError = e; // a dropped frame is harmless; the watchdog reports persistent errors
    } finally {
      _busyFrame = false;
    }
  }

  void _handleFaces(Nv21Frame frame, List<Face> faces) {
    final now = DateTime.now();
    if (faces.isEmpty) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      // In the dark ML Kit often finds no face at all: check the light in the oval.
      final w = frame.uprightWidth.toDouble();
      final h = frame.uprightHeight.toDouble();
      final luma = frame.meanLuma(w * 0.25, h * 0.2, w * 0.5, h * 0.5);
      _trackLight(luma);
      return _setPrompt(luma < _tooDarkLuma ? _darkPrompt : 'Place your face inside the oval');
    }
    if (faces.length > 1) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt('Only your face should be visible');
    }
    final face = faces.first;
    final box = face.boundingBox;
    if (box.width < math.min(frame.width, frame.height) * 0.28) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt('Move a little closer');
    }
    final luma = frame.meanLuma(box.left, box.top, box.width, box.height);
    _trackLight(luma);

    if (!_liveness.sameFace(face, now)) return _restartSteps();

    if (_phase == _Phase.liveness) {
      _ring = _Ring.ok;
      // Remember who is doing the steps, to compare with the final capture.
      if (_anchor == null && luma >= _tooDarkLuma && LivenessTracker.isGoodCaptureFrame(face)) {
        _anchor = _signature(frame, box)?.$1;
      }
      if (_liveness.update(face, now)) HapticFeedback.lightImpact();
      if (_liveness.isDone) {
        _phase = _Phase.steady;
        return _setPrompt('Great! Now look straight at the camera');
      }
      return _setPrompt(luma < _tooDarkLuma ? _darkPrompt : _liveness.current!.instruction);
    }

    // Steady phase: frontal, eyes open, enough light, held for a few frames.
    if (!LivenessTracker.isGoodCaptureFrame(face)) {
      _steadyFrames = 0;
      _ring = _Ring.neutral;
      return _setPrompt('Look straight at the camera with your eyes open');
    }
    if (luma < _tooDarkLuma) {
      _steadyFrames = 0;
      _ring = _Ring.warn;
      return _setPrompt(_darkPrompt);
    }
    _ring = _Ring.good;
    if (_nextSampleAt != null && now.isBefore(_nextSampleAt!)) return;
    _steadyFrames++;
    _setPrompt('Hold still…');
    if (_steadyFrames >= 3) _capture(frame, box);
  }

  /// A different face appeared: everything done so far is discarded.
  void _restartSteps() {
    _anchor = null;
    _embeddings.clear();
    _steadyFrames = 0;
    _ring = _Ring.warn;
    _phase = _liveness.isDone ? _Phase.steady : _Phase.liveness;
    _setPrompt('Face changed. Please repeat the steps');
  }

  int? _rotation() {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;
    final device = _orientations[controller.value.deviceOrientation];
    if (device == null) return null;
    return camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + device) % 360
        : (camera.sensorOrientation - device + 360) % 360;
  }

  /// The frame as packed NV21, whatever layout this phone's camera delivers.
  Nv21Frame? _toFrame(CameraImage image) {
    final rotation = _rotation();
    if (rotation == null) return null;
    final w = image.width;
    final h = image.height;
    final planes = image.planes;
    Uint8List? bytes;
    if (planes.length == 1 && image.format.group == ImageFormatGroup.nv21) {
      final p = planes.first;
      final stride = p.bytesPerRow;
      if (stride == w && p.bytes.length >= w * h * 3 ~/ 2) {
        bytes = p.bytes;
      } else if (stride > w && p.bytes.length >= stride * (h * 3 ~/ 2 - 1) + w) {
        bytes = Uint8List(w * h * 3 ~/ 2);
        for (var row = 0; row < h * 3 ~/ 2; row++) {
          bytes.setRange(row * w, row * w + w, p.bytes, row * stride);
        }
      }
    } else if (planes.length == 3) {
      bytes = Nv21Frame.yuv420ToNv21(
        width: w,
        height: h,
        y: planes[0].bytes,
        yRowStride: planes[0].bytesPerRow,
        u: planes[1].bytes,
        v: planes[2].bytes,
        uvRowStride: planes[1].bytesPerRow,
        uvPixelStride: planes[1].bytesPerPixel ?? 1,
      );
    }
    if (bytes == null) {
      _unsupportedFormat = '${image.format.group.name}, ${planes.length} plane(s)';
      return null;
    }
    return Nv21Frame(bytes: bytes, width: w, height: h, rotation: rotation);
  }

  InputImage _toInputImage(Nv21Frame frame) => InputImage.fromBytes(
    bytes: frame.bytes,
    metadata: InputImageMetadata(
      size: Size(frame.width.toDouble(), frame.height.toDouble()),
      rotation:
          InputImageRotationValue.fromRawValue(frame.rotation) ?? InputImageRotation.rotation0deg,
      format: InputImageFormat.nv21,
      bytesPerRow: frame.width,
    ),
  );

  // ── Capture ─────────────────────────────────────────────────────────────────

  /// Face signature and crop brightness from the frame in memory.
  (List<double>, double)? _signature(Nv21Frame frame, Rect box) {
    final embedder = _embedder;
    if (embedder == null) return null;
    final crop = cropFace(frame, box.left, box.top, box.width, box.height, embedder.inputSize);
    if (crop == null) return null;
    return (embedder.embed(crop.pixels), crop.meanLuma);
  }

  void _capture(Nv21Frame frame, Rect box) {
    _phase = _Phase.capturing;
    try {
      final result = _signature(frame, box);
      if (result == null) throw const _RetryCapture('Move your face to the centre of the oval');
      final (signature, luma) = result;
      if (luma < _tooDarkLuma) {
        _enableFillLight();
        throw const _RetryCapture(_darkPrompt);
      }
      final anchor = _anchor;
      if (anchor != null && _similarity(anchor, signature) < _sameFaceSimilarity) {
        _liveness.reset();
        return _restartSteps();
      }
      _anchor ??= signature;
      _embeddings.add(signature);
    } on _RetryCapture catch (e) {
      _phase = _Phase.steady;
      _steadyFrames = 0;
      return _setPrompt(e.message);
    } catch (e) {
      return _fail('Could not read your face: ${errorMessage(e)}');
    }

    if (_embeddings.length >= widget.samples) {
      _finished = true;
      _controller?.stopImageStream().catchError((_) {});
      Navigator.of(context).pop(
        FaceCaptureResult(
          embeddings: List.of(_embeddings),
          completedSteps: List.of(_liveness.completed),
        ),
      );
      return;
    }

    // Enrollment: take the next sample a moment later.
    setState(() {
      _phase = _Phase.steady;
      _steadyFrames = 0;
      _nextSampleAt = DateTime.now().add(const Duration(milliseconds: 700));
      _prompt = 'Sample ${_embeddings.length + 1} of ${widget.samples}. Keep looking at the camera';
    });
  }

  static double _similarity(List<double> a, List<double> b) {
    var dot = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot; // both are L2-normalised
  }

  // ── Light ───────────────────────────────────────────────────────────────────

  void _trackLight(double luma) {
    if (_fillLight) return;
    _darkFrames = luma < _fillLightLuma ? _darkFrames + 1 : 0;
    if (_darkFrames >= 3) _enableFillLight();
  }

  /// White screen at full brightness lights the face from the front. It stays
  /// on once enabled so the screen does not flicker.
  void _enableFillLight() {
    if (_fillLight || !mounted) return;
    setState(() => _fillLight = true);
    _brightnessChanged = true;
    ScreenBrightness.instance.setApplicationScreenBrightness(1.0).catchError((_) {});
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setPrompt(String text) {
    if (!mounted) return;
    if (text == _prompt) {
      setState(() {}); // ring colour may have changed
      return;
    }
    setState(() => _prompt = text);
  }

  void _fail(String message) {
    if (!mounted || _finished) return;
    _watchdog?.cancel();
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

  _Look get _look => _fillLight ? _Look.light : _Look.dark;

  Color get _ringColor => switch (_ring) {
    _Ring.good => const Color(0xFF22C55E),
    _Ring.warn => AppColors.gold,
    _Ring.ok => _fillLight ? AppColors.primary : const Color(0xFF93C5FD),
    _Ring.neutral => _fillLight ? AppColors.textTertiary : Colors.white70,
  };

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final remaining = _deadline.difference(DateTime.now()).inSeconds.clamp(0, 999);
    final failed = _phase == _Phase.failed;
    final look = _look;
    return Scaffold(
      backgroundColor: look.background,
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
                  child: CustomPaint(
                    painter: _OvalMaskPainter(ringColor: _ringColor, maskColor: look.mask),
                  ),
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
                            color: look.text,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.mode == FaceCaptureMode.enroll
                                  ? 'Face enrollment'
                                  : 'Face verification',
                              style: AppText.h3.copyWith(color: look.text),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: remaining <= 15
                                  ? AppColors.error.withValues(alpha: 0.85)
                                  : look.text.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 15,
                                  color: remaining <= 15 ? Colors.white : look.text,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${remaining}s',
                                  style: AppText.caption.copyWith(
                                    color: remaining <= 15 ? Colors.white : look.text,
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
    final look = _look;
    final total = _liveness.steps.length + (widget.samples > 1 ? 1 : 0);
    final doneSteps =
        _liveness.progress + (widget.samples > 1 && _embeddings.length >= widget.samples ? 1 : 0);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: look.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: _fillLight ? const Border(top: BorderSide(color: AppColors.border)) : null,
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
                            ? look.text
                            : look.faint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (failed) Icon(Icons.error_outline_rounded, color: look.error, size: 34),
            Text(
              failed ? (_error ?? 'Something went wrong') : _prompt,
              textAlign: TextAlign.center,
              style: AppText.h2.copyWith(color: failed ? look.error : look.text, fontSize: 19),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _liveness.steps.length; i++)
                  _StepChip(
                    look: look,
                    label: _liveness.steps[i].label,
                    done: i < _liveness.progress,
                    active: i == _liveness.progress && _phase == _Phase.liveness,
                  ),
                if (widget.samples > 1)
                  _StepChip(
                    look: look,
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
                Icon(Icons.lock_outline_rounded, size: 14, color: look.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _fillLight
                        ? 'Screen light is on to light up your face. Nothing is stored or uploaded.'
                        : 'Processed on this phone. No photo is taken, stored or uploaded.',
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(color: look.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (failed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: _fillLight
                      ? null
                      : FilledButton.styleFrom(
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
  const _StepChip({
    required this.look,
    required this.label,
    required this.done,
    required this.active,
  });

  final _Look look;
  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? const Color(0xFF22C55E)
        : active
        ? look.text
        : look.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? look.text.withValues(alpha: 0.08) : Colors.transparent,
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
  const _OvalMaskPainter({required this.ringColor, required this.maskColor});

  final Color ringColor;
  final Color maskColor;

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
    canvas.drawPath(mask, Paint()..color = maskColor);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = ringColor,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalMaskPainter oldDelegate) =>
      oldDelegate.ringColor != ringColor || oldDelegate.maskColor != maskColor;
}

/// Colours of the camera screen: dark normally, white when the screen is used
/// as a fill light in a dim room.
class _Look {
  const _Look({
    required this.background,
    required this.mask,
    required this.panel,
    required this.text,
    required this.muted,
    required this.faint,
    required this.error,
  });

  static const dark = _Look(
    background: Color(0xFF020617),
    mask: Color(0x9E020617),
    panel: Color(0xFF0F172A),
    text: Colors.white,
    muted: Colors.white54,
    faint: Colors.white24,
    error: Color(0xFFFCA5A5),
  );

  static const light = _Look(
    background: Colors.white,
    mask: Color(0xF7FFFFFF),
    panel: Colors.white,
    text: AppColors.text,
    muted: AppColors.textSecondary,
    faint: AppColors.border,
    error: AppColors.error,
  );

  final Color background;
  final Color mask;
  final Color panel;
  final Color text;
  final Color muted;
  final Color faint;
  final Color error;
}
