import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Liveness actions the server can ask for (wire names match the backend).
enum LivenessStep {
  blink('blink', 'Blink', 'Blink your eyes slowly'),
  smile('smile', 'Smile', 'Give a big smile'),
  turnHead('turn_head', 'Turn head', 'Turn your head to one side, then look back');

  const LivenessStep(this.wire, this.label, this.instruction);

  final String wire;
  final String label;
  final String instruction;

  static LivenessStep? fromWire(String value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

/// Decides whether consecutive detections are the same person in front of the camera.
///
/// ML Kit gives a face a new tracking id when it loses it for a moment, which
/// happens on slow phones while the head is turned. A new id still counts as the
/// same face if it shows up within [maxGap] at about the same place and size.
/// Anything else (a long gap, a jump across the frame) counts as a different face.
/// The capture screen also compares face signatures, so a quick photo swap is caught there.
class FaceContinuity {
  static const maxGap = Duration(milliseconds: 1200);

  int? _id;
  Rect? _box;
  DateTime? _seen;

  void reset() {
    _id = null;
    _box = null;
    _seen = null;
  }

  /// Follows [face]; returns false when it is a different face from the one being followed.
  bool accept(Face face, DateTime now) {
    final id = face.trackingId;
    final box = face.boundingBox;
    final lastBox = _box;
    final lastSeen = _seen;
    var same = true;
    if (lastBox != null && lastSeen != null && id != null && _id != null && id != _id) {
      final gapOk = now.difference(lastSeen) <= maxGap;
      final moved = (box.center - lastBox.center).distance;
      final scale = box.width / lastBox.width;
      same = gapOk && moved < lastBox.width * 0.5 && scale > 0.6 && scale < 1.6;
    }
    _id = id ?? _id;
    _box = box;
    _seen = now;
    return same;
  }
}

/// Tracks a random sequence of liveness steps across camera frames.
///
/// A printed photo cannot blink or smile on demand, and the steps are chosen
/// by the server, so a pre-recorded video is unlikely to match. If a different
/// face appears mid-way (see [FaceContinuity]), progress resets.
///
/// Thresholds are set for cheap front cameras, which give noisier eye and
/// smile probabilities and fewer frames per second than flagship phones.
class LivenessTracker {
  LivenessTracker(this.steps);

  final List<LivenessStep> steps;
  final List<String> completed = [];
  final FaceContinuity _continuity = FaceContinuity();

  int _index = 0;
  bool _sawOpenEyes = false;
  bool _sawClosedEyes = false;
  bool _turned = false;

  bool get isDone => _index >= steps.length;
  LivenessStep? get current => isDone ? null : steps[_index];
  int get progress => _index;

  void reset() {
    _index = 0;
    completed.clear();
    _continuity.reset();
    _resetStep();
  }

  void _restart() {
    _index = 0;
    completed.clear();
    _resetStep();
  }

  void _resetStep() {
    _sawOpenEyes = false;
    _sawClosedEyes = false;
    _turned = false;
  }

  /// Checks that [face] is still the person who did the steps. If not, all
  /// progress is cleared and false is returned.
  bool sameFace(Face face, [DateTime? now]) {
    if (_continuity.accept(face, now ?? DateTime.now())) return true;
    _restart();
    return false;
  }

  /// Feed one frame's face. Returns true when a step was just completed.
  bool update(Face face, [DateTime? now]) {
    if (!sameFace(face, now) || isDone) return false;

    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final smile = face.smilingProbability ?? 0;
    final yaw = (face.headEulerAngleY ?? 0).abs();

    var passed = false;
    switch (steps[_index]) {
      case LivenessStep.blink:
        if (left != null && right != null) {
          final eyes = (left + right) / 2;
          if (eyes > 0.55) {
            if (_sawClosedEyes) {
              passed = true;
            } else {
              _sawOpenEyes = true;
            }
          } else if (eyes < 0.3 && _sawOpenEyes) {
            _sawClosedEyes = true;
          }
        }
      case LivenessStep.smile:
        passed = smile > 0.7;
      case LivenessStep.turnHead:
        if (yaw > 20) {
          _turned = true;
        } else if (_turned && yaw < 12) {
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

  /// A good frame for the face signature: roughly frontal, eyes open.
  static bool isGoodCaptureFrame(Face face) {
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    final eyes = [face.leftEyeOpenProbability ?? 1, face.rightEyeOpenProbability ?? 1];
    return yaw < 15 && pitch < 20 && eyes.every((e) => e > 0.4);
  }
}
