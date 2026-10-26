import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/isbn.dart';

/// Result of reading a printed ISBN from a photo.
class OcrResult {
  const OcrResult({required this.isbns, required this.text});

  /// Checksum-valid ISBN-13s found, in reading order.
  final List<String> isbns;

  /// All recognised text (shown when nothing was found, to help retry).
  final String text;
}

/// Takes a photo with the camera and finds ISBNs in it, on the device.
/// Returns null if the user cancelled the camera.
Future<OcrResult?> captureAndReadIsbn() async {
  final photo = await ImagePicker().pickImage(
    source: ImageSource.camera,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 90,
  );
  if (photo == null) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(
      InputImage.fromFilePath(photo.path),
    );
    return OcrResult(isbns: extractIsbns(result.text), text: result.text);
  } finally {
    await recognizer.close();
  }
}
