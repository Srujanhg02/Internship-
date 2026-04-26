import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'plate_detector.dart';

class OcrService {
  /// Recognizes vehicle number from image at [imagePath].
  ///
  /// Pipeline:
  ///  1. YOLO plate detector → finds bounding box
  ///  2. Crop plate region with padding
  ///  3. ML Kit V2 OCR on cropped plate (or full image if no plate found)
  ///  4. Multi-pass regex/scoring extraction
  static Future<String> recognizeVehicleNo(String imagePath) async {
    String? cropPath;
    String? processedPath;

    // Step 1: Try to detect and crop the plate region
    cropPath = await _detectAndCrop(imagePath);

    String pathToUse;
    bool isCropped = false;

    if (cropPath != null) {
      // Step 2: Preprocess the cropped plate for better OCR
      processedPath = await _preprocessPlate(cropPath);
      pathToUse = processedPath ?? cropPath;
      isCropped = true;
    } else {
      // Fallback: use the full image (strict extraction will filter non-plate text)
      debugPrint('[OcrService] No plate detected — falling back to full image');
      pathToUse = imagePath;
    }

    final textRecognizer = TextRecognizer();
    try {
      final inputImage = InputImage.fromFilePath(pathToUse);
      final recognizedText = await textRecognizer.processImage(inputImage);

      // Debug logging
      debugPrint(
        '═══ OCR on ${isCropped ? "CROPPED PLATE" : "FULL IMAGE"} ═══',
      );
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          debugPrint(
            '  [${line.confidence?.toStringAsFixed(1) ?? "?"}%] "${line.text}"',
          );
        }
      }
      debugPrint('═══════════════════════════════════════');

      return _extractVehicleNo(recognizedText);
    } finally {
      textRecognizer.close();
      // Clean up temp files
      for (final p in [cropPath, processedPath]) {
        if (p != null) {
          try {
            await File(p).delete();
          } catch (_) {}
        }
      }
    }
  }

  /// Run YOLO plate detection and crop the plate region.
  /// Returns the crop file path, or null if no plate detected.
  static Future<String?> _detectAndCrop(String imagePath) async {
    try {
      final detector = PlateDetector.instance;
      final detection = await detector.detect(imagePath);
      if (detection == null) return null;
      return await detector.cropPlate(imagePath, detection);
    } catch (e) {
      debugPrint('[OcrService] Plate detection failed: $e');
      return null;
    }
  }

  /// Preprocess the cropped plate: grayscale + contrast boost for cleaner OCR.
  static Future<String?> _preprocessPlate(String cropPath) async {
    try {
      final bytes = await File(cropPath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // Convert to grayscale
      image = img.grayscale(image);

      // Boost contrast
      image = img.adjustColor(image, contrast: 1.5);

      // Scale up small plates for better OCR (target ~400px wide)
      if (image.width < 400) {
        final scale = (400 / image.width).clamp(1.0, 3.0);
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/plate_proc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(image, quality: 95));
      debugPrint('[OcrService] Preprocessed plate: $outPath');
      return outPath;
    } catch (e) {
      debugPrint('[OcrService] Preprocess error: $e');
      return null;
    }
  }

  /// Extract vehicle number from recognized text
  static String _extractVehicleNo(RecognizedText recognizedText) {
    // Collect all lines with their text
    final allLines = <_OcrLine>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allLines.add(
          _OcrLine(text: line.text.trim(), confidence: line.confidence ?? 0),
        );
      }
    }

    if (allLines.isEmpty) return '';

    // Pass 1: Try strict Indian plate regex on each line
    for (final line in allLines) {
      final match = _matchStrictPlate(line.text);
      if (match.isNotEmpty) return _normalizePlate(match);
    }

    // Pass 2: Try relaxed regex on each line
    for (final line in allLines) {
      final match = _matchRelaxedPlate(line.text);
      if (match.isNotEmpty) return _normalizePlate(match);
    }

    // Pass 3: Join nearby lines and try (sometimes plate wraps to 2 lines)
    for (int i = 0; i < allLines.length - 1; i++) {
      final joined = '${allLines[i].text} ${allLines[i + 1].text}';
      final match = _matchStrictPlate(joined);
      if (match.isNotEmpty) return _normalizePlate(match);
    }

    // Pass 4: Find the most plate-like text among all lines
    final candidate = _findBestCandidate(allLines);
    if (candidate.isNotEmpty) return candidate;

    // If no valid plate format is found, DO NOT guess. 
    // Return empty so the camera keeps scanning for a real plate.
    return '';
  }

  /// Strict Indian plate: XX 00 XX 0000
  static String _matchStrictPlate(String text) {
    final upper = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final regex = RegExp(
      r'[A-Z]{2}[\s\-.]?\d{1,2}[\s\-.]?[A-Z]{1,3}[\s\-.]?\d{4}',
    );
    final match = regex.firstMatch(upper);
    return match?.group(0) ?? '';
  }

  /// Relaxed: broader patterns including 3-digit endings
  static String _matchRelaxedPlate(String text) {
    final upper = text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final patterns = [
      RegExp(r'[A-Z]{2}[\s\-.]?\d{1,2}[\s\-.]?[A-Z]{1,3}[\s\-.]?\d{3,4}'),
      RegExp(r'[A-Z]{2}\d{1,2}[A-Z]{1,3}\d{3,4}'),
    ];

    String best = '';
    for (final regex in patterns) {
      final match = regex.firstMatch(upper);
      if (match != null && match.group(0)!.length > best.length) {
        best = match.group(0)!;
      }
    }
    return best;
  }

  /// Find the most plate-like text based on scoring
  static String _findBestCandidate(List<_OcrLine> lines) {
    String best = '';
    double bestScore = 0;

    for (final line in lines) {
      final text = line.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (text.length < 6 || text.length > 14) continue;

      final letterCount = RegExp(r'[A-Z]').allMatches(text).length;
      final digitCount = RegExp(r'\d').allMatches(text).length;

      if (letterCount < 2 || digitCount < 2) continue;

      double score = 0;
      // Starts with 2 letters (state code) is a strong signal
      if (RegExp(r'^[A-Z]{2}').hasMatch(text)) score += 15;
      // Has 3-4 trailing digits
      if (RegExp(r'\d{3,4}$').hasMatch(text)) score += 10;
      // Has a good mix of letters and digits
      score += (letterCount + digitCount).toDouble();
      // Right length range
      if (text.length >= 8 && text.length <= 12) score += 5;
      // Higher OCR confidence
      score += (line.confidence / 100) * 5;

      if (score > bestScore) {
        bestScore = score;
        best = line.text.trim().toUpperCase();
      }
    }

    return bestScore >= 25 ? best : '';
  }

  /// Normalize: clean up the plate string
  static String _normalizePlate(String plate) {
    return plate
        .toUpperCase()
        .replaceAll('.', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _OcrLine {
  final String text;
  final double confidence;
  _OcrLine({required this.text, required this.confidence});
}
