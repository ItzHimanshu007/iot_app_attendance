import 'dart:math' as math;
import 'dart:typed_data';

/// One camera preview frame in NV21 layout: a full-resolution Y (luma) plane
/// followed by interleaved V/U (chroma) at half resolution. Rows are packed.
///
/// [rotation] is how far the raw sensor image must be turned clockwise to be
/// upright (0, 90, 180 or 270), the same value ML Kit is given. ML Kit returns
/// face boxes in upright coordinates; this class maps them back to raw pixels,
/// so the face is cut straight out of the frame already in memory. There is no
/// photo, file or second detection.
class Nv21Frame {
  Nv21Frame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rotation,
  }) : assert(rotation % 90 == 0),
       assert(bytes.length >= width * height * 3 ~/ 2);

  final Uint8List bytes;
  final int width;
  final int height;
  final int rotation;

  int get uprightWidth => rotation % 180 == 0 ? width : height;
  int get uprightHeight => rotation % 180 == 0 ? height : width;

  /// Raw sensor position of an upright position (continuous pixel coordinates).
  (double, double) toRaw(double ux, double uy) => switch (rotation % 360) {
    90 => (uy, height - ux),
    180 => (width - ux, height - uy),
    270 => (width - uy, ux),
    _ => (ux, uy),
  };

  /// Bilinear luma at a raw position.
  double lumaAt(double rx, double ry) {
    final px = (rx - 0.5).clamp(0.0, width - 1.0);
    final py = (ry - 0.5).clamp(0.0, height - 1.0);
    final x0 = px.floor();
    final y0 = py.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final fx = px - x0;
    final fy = py - y0;
    final r0 = y0 * width;
    final r1 = y1 * width;
    final top = bytes[r0 + x0] + (bytes[r0 + x1] - bytes[r0 + x0]) * fx;
    final bottom = bytes[r1 + x0] + (bytes[r1 + x1] - bytes[r1 + x0]) * fx;
    return top + (bottom - top) * fy;
  }

  /// Average luma (0–255) of an upright box, sampled on a 16 × 16 grid.
  double meanLuma(double left, double top, double boxWidth, double boxHeight) {
    var sum = 0.0;
    for (var j = 0; j < 16; j++) {
      for (var i = 0; i < 16; i++) {
        final (rx, ry) = toRaw(left + (i + 0.5) * boxWidth / 16, top + (j + 0.5) * boxHeight / 16);
        sum += lumaAt(rx, ry);
      }
    }
    return sum / 256;
  }

  /// Packs Android YUV_420_888 planes (any row/pixel stride) into NV21.
  /// Used when a phone's camera ignores the NV21 request and sends 3 planes.
  static Uint8List yuv420ToNv21({
    required int width,
    required int height,
    required Uint8List y,
    required int yRowStride,
    required Uint8List u,
    required Uint8List v,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    final out = Uint8List(width * height * 3 ~/ 2);
    for (var row = 0; row < height; row++) {
      out.setRange(row * width, row * width + width, y, row * yRowStride);
    }
    var o = width * height;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        final i = row * uvRowStride + col * uvPixelStride;
        out[o++] = v[i];
        out[o++] = u[i];
      }
    }
    return out;
  }
}

/// A face cut out of a frame, ready for MobileFaceNet.
class FaceCrop {
  const FaceCrop(this.pixels, this.meanLuma);

  /// size × size × 3 RGB floats in [-1, 1].
  final Float32List pixels;

  /// Average brightness (0–255) of the crop before normalisation.
  final double meanLuma;
}

/// Crops the face (square, +20 % margin around ML Kit's upright box) straight
/// from the NV21 frame, area-averages it down to [size] × [size], converts
/// YUV → RGB, evens out the brightness and normalises to [-1, 1].
///
/// Brightness normalisation scales the crop so its average luma is 128 (gain
/// limited to 0.6–3×). In tests on real faces it kept different people apart
/// in dim light and did not change results in good light.
///
/// Returns null when the box is too small or its centre is outside the frame.
FaceCrop? cropFace(
  Nv21Frame frame,
  double left,
  double top,
  double width,
  double height,
  int size,
) {
  final side = math.max(width, height) * 1.2;
  final cx = left + width / 2;
  final cy = top + height / 2;
  if (side < 40 || cx < 0 || cy < 0 || cx > frame.uprightWidth || cy > frame.uprightHeight) {
    return null;
  }
  final step = side / size;
  final n = step.ceil().clamp(1, 4); // sub-samples per axis
  final x0 = cx - side / 2;
  final y0 = cy - side / 2;
  final w = frame.width;
  final h = frame.height;
  final chroma = w * h;
  final bytes = frame.bytes;

  final ys = Float32List(size * size);
  final us = Float32List(size * size);
  final vs = Float32List(size * size);
  var lumaSum = 0.0;
  for (var oy = 0; oy < size; oy++) {
    for (var ox = 0; ox < size; ox++) {
      var y = 0.0, u = 0.0, v = 0.0;
      for (var sy = 0; sy < n; sy++) {
        for (var sx = 0; sx < n; sx++) {
          final (rx, ry) = frame.toRaw(
            x0 + (ox + (sx + 0.5) / n) * step,
            y0 + (oy + (sy + 0.5) / n) * step,
          );
          y += frame.lumaAt(rx, ry);
          final cxI = (rx.clamp(0, w - 1).toInt()) >> 1;
          final cyI = (ry.clamp(0, h - 1).toInt()) >> 1;
          final c = chroma + cyI * w + cxI * 2;
          v += bytes[c];
          u += bytes[c + 1];
        }
      }
      final k = oy * size + ox;
      ys[k] = y / (n * n);
      us[k] = u / (n * n) - 128;
      vs[k] = v / (n * n) - 128;
      lumaSum += ys[k];
    }
  }

  final meanLuma = lumaSum / (size * size);
  final gain = (128 / math.max(meanLuma, 1)).clamp(0.6, 3.0);
  final out = Float32List(size * size * 3);
  var i = 0;
  for (var k = 0; k < size * size; k++) {
    // BT.601 full range (what Android cameras deliver).
    final r = ys[k] + 1.402 * vs[k];
    final g = ys[k] - 0.344136 * us[k] - 0.714136 * vs[k];
    final b = ys[k] + 1.772 * us[k];
    out[i++] = ((r.clamp(0, 255) * gain).clamp(0, 255) - 127.5) / 128;
    out[i++] = ((g.clamp(0, 255) * gain).clamp(0, 255) - 127.5) / 128;
    out[i++] = ((b.clamp(0, 255) * gain).clamp(0, 255) - 127.5) / 128;
  }
  return FaceCrop(out, meanLuma);
}
