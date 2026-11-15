import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/app_failure.dart';
import '../domain/business_application.dart';

/// Picks a PDF, JPEG or PNG from the phone and checks its size before it is
/// uploaded. Behind a provider so tests can replace it.
class DocumentPicker {
  static const AppFailure _tooLarge = AppFailure(
    AppFailureReason.invalidInput,
    'That file is too large. Use one under 5 MB.',
  );

  /// `null` when the user backs out without choosing.
  Future<NewDocument?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ApplicationRules.documentExtensions.toList(),
    );
    if (file == null) return null;

    if (ApplicationRules.documentExtension(file.name) == null) {
      throw const AppFailure(
        AppFailureReason.invalidInput,
        'Use a PDF, JPEG or PNG file.',
      );
    }
    // Check the size before reading a large file into memory.
    final size = await file.length();
    if (size != null && size > ApplicationRules.maxDocumentBytes) {
      throw _tooLarge;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > ApplicationRules.maxDocumentBytes) throw _tooLarge;
    return NewDocument(name: file.name, bytes: bytes);
  }
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => DocumentPicker(),
);
