import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Detection {
  final String label;
  final double confidence;
  const Detection(this.label, this.confidence);
}

class DetectorResult {
  /// Maior confiança entre as classes de falha (0..1).
  final double failureScore;
  final String? failureLabel;
  final List<Detection> perClass;
  const DetectorResult(this.failureScore, this.failureLabel, this.perClass);
}

/// Detetor de falhas baseado num modelo YOLO (v5 ou v8) exportado para TFLite.
/// O modelo corre no telemóvel; nenhuma imagem sai do dispositivo.
///
/// Ficheiros esperados (ver assets/ai/LEIA-ME.md e tools/train_model.py):
///   assets/ai/failure.tflite  — o modelo
///   assets/ai/labels.txt      — uma classe por linha, pela ordem do treino
class YoloFailureDetector {
  static const modelAsset = 'assets/ai/failure.tflite';
  static const labelsAsset = 'assets/ai/labels.txt';

  /// Classes que o modelo pode detetar mas que NÃO são falhas
  /// (alguns datasets marcam também a peça e o extrusor).
  static const _notFailures = {
    'extruder', 'nozzle', 'hotend', 'part', 'print', 'printing', 'object', 'bed', 'normal', 'ok'
  };

  Interpreter? _interp;
  IsolateInterpreter? _iso;
  List<String> labels = [];
  int _inW = 320, _inH = 320;
  String? loadError;

  bool get ready => _iso != null;

  Future<bool> load() async {
    try {
      _interp = await Interpreter.fromAsset(modelAsset,
          options: InterpreterOptions()..threads = 2);
      labels = (await rootBundle.loadString(labelsAsset))
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final shape = _interp!.getInputTensor(0).shape; // [1, h, w, 3]
      _inH = shape[1];
      _inW = shape[2];
      _iso = await IsolateInterpreter.create(address: _interp!.address);
      return true;
    } catch (e) {
      loadError = '$e';
      return false;
    }
  }

  Future<DetectorResult?> analyze(Uint8List jpeg) async {
    if (!ready) return null;
    final input = await compute(_preprocess, _PreArgs(jpeg, _inW, _inH));
    if (input == null) return null;

    final outShape = _interp!.getOutputTensor(0).shape; // [1, C, N] ou [1, N, C]
    final output = List.generate(
        1, (_) => List.generate(outShape[1], (_) => List<double>.filled(outShape[2], 0)));
    await _iso!.run(input.buffer.asUint8List(), output);

    // Layout: YOLOv8 exporta [1, 4+nc, N]; YOLOv5 exporta [1, N, 5+nc].
    final transposed = outShape[1] < outShape[2];
    final c = transposed ? outShape[1] : outShape[2];
    final n = transposed ? outShape[2] : outShape[1];
    final nc = labels.isNotEmpty ? labels.length : c - 4;
    final hasObj = c == nc + 5; // YOLOv5 tem "objectness"
    final first = hasObj ? 5 : 4;
    double v(int box, int ch) => transposed ? output[0][ch][box] : output[0][box][ch];

    final best = List<double>.filled(nc, 0);
    for (var i = 0; i < n; i++) {
      final obj = hasObj ? v(i, 4) : 1.0;
      for (var k = 0; k < nc && first + k < c; k++) {
        final s = v(i, first + k) * obj;
        if (s > best[k]) best[k] = s;
      }
    }

    var score = 0.0;
    String? label;
    final per = <Detection>[];
    for (var k = 0; k < nc; k++) {
      final name = k < labels.length ? labels[k] : 'classe $k';
      per.add(Detection(name, best[k]));
      if (_notFailures.contains(name.toLowerCase())) continue;
      if (best[k] > score) {
        score = best[k];
        label = name;
      }
    }
    return DetectorResult(score, label, per);
  }

  void dispose() {
    _iso?.close();
    _interp?.close();
  }
}

class _PreArgs {
  final Uint8List jpeg;
  final int w, h;
  _PreArgs(this.jpeg, this.w, this.h);
}

/// Corre num isolate: decode JPEG → letterbox para w×h → Float32 RGB 0..1.
Float32List? _preprocess(_PreArgs a) {
  final src = img.decodeJpg(a.jpeg);
  if (src == null) return null;
  final scale = min(a.w / src.width, a.h / src.height);
  final rw = (src.width * scale).round(), rh = (src.height * scale).round();
  final resized = img.copyResize(src, width: rw, height: rh);
  final canvas = img.Image(width: a.w, height: a.h);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114)); // cinzento padrão YOLO
  img.compositeImage(canvas, resized,
      dstX: (a.w - rw) ~/ 2, dstY: (a.h - rh) ~/ 2);
  final out = Float32List(a.w * a.h * 3);
  var i = 0;
  for (var y = 0; y < a.h; y++) {
    for (var x = 0; x < a.w; x++) {
      final p = canvas.getPixel(x, y);
      out[i++] = p.r / 255.0;
      out[i++] = p.g / 255.0;
      out[i++] = p.b / 255.0;
    }
  }
  return out;
}
