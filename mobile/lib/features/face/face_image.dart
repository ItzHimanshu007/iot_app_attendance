import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Input for [preprocessFace]; plain data so it can cross an isolate boundary.
class FaceCropRequest {
  const FaceCropRequest({
    required this.path,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.size,
  });

  final String path;
  final double left;
  final double top;
  final double width;
  final double height;
  final int size;
}

/// Decode the captured JPEG, crop the face (square, +20 % margin), resize to
/// [FaceCropRequest.size] and normalise to [-1, 1] as MobileFaceNet expects.
///
/// Returns null when the face box does not fit the decoded image.
/// Runs in a background isolate (pure Dart).
Float32List? preprocessFace(FaceCropRequest req) {
  final decoded = img.decodeImage(File(req.path).readAsBytesSync());
  if (decoded == null) return null;
  // ML Kit reports the box in upright (EXIF-applied) coordinates.
  final image = img.bakeOrientation(decoded);

  final side = math.max(req.width, req.height) * 1.2;
  final cx = req.left + req.width / 2;
  final cy = req.top + req.height / 2;
  final x = (cx - side / 2).round().clamp(0, image.width - 1);
  final y = (cy - side / 2).round().clamp(0, image.height - 1);
  final w = math.min(side.round(), image.width - x);
  final h = math.min(side.round(), image.height - y);
  if (w < 40 || h < 40 || req.left > image.width || req.top > image.height) return null;

  final crop = img.copyCrop(image, x: x, y: y, width: w, height: h);
  final face = img.copyResize(
    crop,
    width: req.size,
    height: req.size,
    interpolation: img.Interpolation.linear,
  );

  final out = Float32List(req.size * req.size * 3);
  var i = 0;
  for (var py = 0; py < req.size; py++) {
    for (var px = 0; px < req.size; px++) {
      final p = face.getPixel(px, py);
      out[i++] = (p.r - 127.5) / 128.0;
      out[i++] = (p.g - 127.5) / 128.0;
      out[i++] = (p.b - 127.5) / 128.0;
    }
  }
  return out;
}
