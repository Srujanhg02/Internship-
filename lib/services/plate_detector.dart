import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Detection result from the YOLO plate detector
class PlateDetection {
  /// Bounding box in **pixel** coordinates (within the source image)
  final Rect box;

  /// Confidence score [0..1]
  final double confidence;

  const PlateDetection({required this.box, required this.confidence});

  @override
  String toString() =>
      'PlateDetection(box=$box, conf=${confidence.toStringAsFixed(2)})';
}

/// Runs YOLOv8n ONNX model to locate license plates in an image.
class PlateDetector {
  static PlateDetector? _instance;
  static PlateDetector get instance => _instance ??= PlateDetector._();
  PlateDetector._();

  OrtSession? _session;
  static const _modelAsset = 'assets/models/plate_detector.onnx';
  static const _inputSize = 320;
  static const _confidenceThreshold = 0.25;

  /// Load the ONNX model from assets (call once at startup)
  Future<void> load() async {
    if (_session != null) return;
    try {
      final ort = OnnxRuntime();
      _session = await ort.createSessionFromAsset(_modelAsset);
      debugPrint('[PlateDetector] ONNX model loaded ✅');
    } catch (e) {
      debugPrint('[PlateDetector] Failed to load model: $e');
    }
  }

  /// Detect plates in [imagePath]. Returns the highest-confidence detection,
  /// or `null` if no plate was found above the confidence threshold.
  Future<PlateDetection?> detect(String imagePath) async {
    if (_session == null) await load();
    if (_session == null) return null;

    try {
      // ── Load & resize image to 320×320 ─────────────────────────────────
      final imgBytes = await File(imagePath).readAsBytes();
      final original = img.decodeImage(imgBytes);
      if (original == null) return null;

      final origW = original.width.toDouble();
      final origH = original.height.toDouble();

      final resized = img.copyResize(
        original,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      // ── Build float32 input in CHW format [1, 3, 320, 320] ─────────────
      final inputData = Float32List(_inputSize * _inputSize * 3);
      int ri = 0,
          gi = _inputSize * _inputSize,
          bi = _inputSize * _inputSize * 2;
      for (int y = 0; y < _inputSize; y++) {
        for (int x = 0; x < _inputSize; x++) {
          final pixel = resized.getPixel(x, y);
          inputData[ri++] = pixel.r / 255.0;
          inputData[gi++] = pixel.g / 255.0;
          inputData[bi++] = pixel.b / 255.0;
        }
      }

      // ── Run ONNX inference ──────────────────────────────────────────────
      final inputTensor = await OrtValue.fromList(inputData.toList(), [
        1,
        3,
        _inputSize,
        _inputSize,
      ]);

      final outputs = await _session!.run({'images': inputTensor});
      await inputTensor.dispose();

      // ── Decode YOLOv8 output tensor [1, 84, 2100] ──────────────────────
      // Layout: [cx, cy, w, h, class0_conf, ..., class79_conf] × 2100 boxes
      final rawOutput = outputs['output0'];
      if (rawOutput == null) {
        debugPrint(
          '[PlateDetector] No output0 in model outputs: ${outputs.keys}',
        );
        return null;
      }

      final List<dynamic> flatRaw = await rawOutput.asList();
      await rawOutput.dispose();

      // Flatten to a flat float list (may be nested)
      final flat = _flattenToFloats(flatRaw);

      const numBoxes = 2100;
      const numClasses = 80;

      PlateDetection? best;

      for (int i = 0; i < numBoxes; i++) {
        final cx = flat[0 * numBoxes + i];
        final cy = flat[1 * numBoxes + i];
        final w = flat[2 * numBoxes + i];
        final h = flat[3 * numBoxes + i];

        // Max class confidence across all 80 COCO classes
        double maxConf = 0;
        for (int c = 0; c < numClasses; c++) {
          final s = flat[(4 + c) * numBoxes + i];
          if (s > maxConf) maxConf = s;
        }

        if (maxConf < _confidenceThreshold) continue;

        // Convert from 320×320 space to original image pixel space
        final scaleX = origW / _inputSize;
        final scaleY = origH / _inputSize;

        final x1 = ((cx - w / 2) * scaleX).clamp(0.0, origW);
        final y1 = ((cy - h / 2) * scaleY).clamp(0.0, origH);
        final x2 = ((cx + w / 2) * scaleX).clamp(0.0, origW);
        final y2 = ((cy + h / 2) * scaleY).clamp(0.0, origH);

        // Filter implausible boxes
        final boxW = x2 - x1;
        final boxH = y2 - y1;
        final area = (boxW * boxH) / (origW * origH);
        if (area < 0.005 || area > 0.75) continue;
        if (boxW < 20 || boxH < 8) continue;

        // Aspect ratio filter: plates are wide rectangles (1.5:1 to 7:1)
        final aspectRatio = boxW / boxH;
        if (aspectRatio < 1.5 || aspectRatio > 7.0) continue;

        final detection = PlateDetection(
          box: Rect.fromLTRB(x1, y1, x2, y2),
          confidence: maxConf,
        );
        if (best == null || maxConf > best.confidence) {
          best = detection;
        }
      }

      if (best != null) {
        debugPrint(
          '[PlateDetector] Best: ${best.box} conf=${best.confidence.toStringAsFixed(2)}',
        );
      } else {
        debugPrint(
          '[PlateDetector] No plate above threshold $_confidenceThreshold',
        );
      }
      return best;
    } catch (e, st) {
      debugPrint('[PlateDetector] Error: $e\n$st');
      return null;
    }
  }

  /// Crop the image to the detected plate bounding box with [padding] fraction.
  Future<String?> cropPlate(
    String imagePath,
    PlateDetection detection, {
    double padding = 0.25,
  }) async {
    try {
      final imgBytes = await File(imagePath).readAsBytes();
      final original = img.decodeImage(imgBytes);
      if (original == null) return null;

      final box = detection.box;
      final padX = box.width * padding;
      final padY = box.height * padding;

      final x = math.max(0, (box.left - padX).round());
      final y = math.max(0, (box.top - padY).round());
      final w = math.min(original.width - x, (box.width + padX * 2).round());
      final h = math.min(original.height - y, (box.height + padY * 2).round());

      final cropped = img.copyCrop(original, x: x, y: y, width: w, height: h);

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/plate_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(cropped, quality: 92));
      debugPrint('[PlateDetector] Cropped to: $outPath (${w}x$h px)');
      return outPath;
    } catch (e) {
      debugPrint('[PlateDetector] Crop error: $e');
      return null;
    }
  }

  /// Flatten a potentially nested list of numbers to a flat `List<double>`.
  List<double> _flattenToFloats(List<dynamic> nested) {
    final result = <double>[];
    for (final item in nested) {
      if (item is List) {
        result.addAll(_flattenToFloats(item.cast<dynamic>()));
      } else if (item is num) {
        result.add(item.toDouble());
      }
    }
    return result;
  }

  void dispose() {
    _session?.close();
    _session = null;
    _instance = null;
  }
}
