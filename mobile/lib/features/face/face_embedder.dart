import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/config.dart';

/// MobileFaceNet (TFLite) — turns a 112×112 face crop into an L2-normalised
/// signature (192 floats). Runs fully on the phone; the image never leaves it.
class FaceEmbedder {
  FaceEmbedder._(this._interpreter, this.inputSize, this.outputSize);

  final Interpreter _interpreter;
  final int inputSize;
  final int outputSize;

  static Future<FaceEmbedder> load() async {
    final interpreter = await Interpreter.fromAsset(
      AppConfig.faceModelAsset,
      options: InterpreterOptions()..threads = 2,
    );
    final input = interpreter.getInputTensor(0).shape; // [1, 112, 112, 3]
    final output = interpreter.getOutputTensor(0).shape; // [1, 192]
    return FaceEmbedder._(interpreter, input[1], output.last);
  }

  /// [pixels] = inputSize × inputSize × 3 floats already normalised to [-1, 1].
  List<double> embed(Float32List pixels) {
    final output = Float32List(outputSize);
    _interpreter.run(pixels.buffer, output.buffer);
    var norm = 0.0;
    for (final v in output) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm < 1e-6) throw StateError('Empty face signature');
    return [for (final v in output) v / norm];
  }

  void close() => _interpreter.close();
}
