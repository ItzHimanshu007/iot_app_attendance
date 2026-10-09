import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Liveness actions the server can ask for (wire names match the backend).
enum LivenessStep {
  blink('blink', 'Blink your eyes'),
  smile('smile', 'Smile'),
  turnHead('turn_head', 'Turn your head to one side, then look back');

  const LivenessStep(this.wire, this.instruction);

  final String wire;
  final String instruction;

  static LivenessStep? fromWire(String value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// Tracks a random sequence of liveness steps across camera frames.
///
/// A printed photo cannot blink or smile on demand, and the steps are chosen
/// by the server, so a pre-recorded video is unlikely to match. If ML Kit's
/// tracking id changes mid-way (a different face appeared), progress resets.
class LivenessTracker {
  LivenessTracker(this.steps);

  final List<LivenessStep> steps;
  final List<String> completed = [];

  int _index = 0;
  int? _trackingId;
  bool _sawOpenEyes = false;
  bool _sawClosedEyes = false;
  bool _turned = false;

  bool get isDone => _index >= steps.length;
  LivenessStep? get current => isDone ? null : steps[_index];
  int get progress => _index;

  void reset() {
    _index = 0;
    completed.clear();
    _trackingId = null;
    _resetStep();
  }

  void _resetStep() {
    _sawOpenEyes = false;
    _sawClosedEyes = false;
    _turned = false;
  }

  /// Feed one frame's face. Returns true when a step was just completed.
  bool update(Face face) {
    if (isDone) return false;
    final id = face.trackingId;
    if (id != null) {
      if (_trackingId != null && _trackingId != id) reset();
      _trackingId = id;
    }

    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final smile = face.smilingProbability ?? 0;
    final yaw = (face.headEulerAngleY ?? 0).abs();

    var passed = false;
    switch (steps[_index]) {
      case LivenessStep.blink:
        if (left != null && right != null) {
          if (left > 0.6 && right > 0.6) {
            if (_sawClosedEyes) {
              passed = true;
            } else {
              _sawOpenEyes = true;
            }
          } else if (left < 0.2 && right < 0.2 && _sawOpenEyes) {
            _sawClosedEyes = true;
          }
        }
      case LivenessStep.smile:
        passed = smile > 0.8;
      case LivenessStep.turnHead:
        if (yaw > 22) {
          _turned = true;
        } else if (_turned && yaw < 10) {
          passed = true;
        }
    }

    if (passed) {
      completed.add(steps[_index].wire);
      _index++;
      _resetStep();
    }
    return passed;
  }

  /// A good frame for the face signature: frontal, eyes open, neutral-ish.
  static bool isGoodCaptureFrame(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    final eyes = [face.leftEyeOpenProbability ?? 1, face.rightEyeOpenProbability ?? 1];
    return yaw < 12 && pitch < 15 && eyes.every((e) => e > 0.5);
  }
}
