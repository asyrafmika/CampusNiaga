import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/domain/app_failure.dart';
import '../domain/listing_input.dart';

enum PhotoSource { camera, gallery }

/// Picks a photo and shrinks it on the phone (longest side 1280 px, 80%
/// quality) before it is uploaded. Behind a provider so tests can replace it.
class PhotoPicker {
  PhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  static const int maxBytes = 5 * 1024 * 1024;

  final ImagePicker _picker;

  /// `null` when the user backs out without choosing.
  Future<NewPhoto?> pick(PhotoSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
    );
    if (file == null) return null;

    final extension =
        NewPhoto.extensionOf(file.name) ??
        switch (file.mimeType) {
          'image/jpeg' => 'jpg',
          'image/png' => 'png',
          'image/webp' => 'webp',
          _ => null,
        };
    if (extension == null) {
      throw const AppFailure(
        AppFailureReason.invalidInput,
        'Use a JPEG, PNG or WebP photo.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) {
      throw const AppFailure(
        AppFailureReason.invalidInput,
        'That photo is too large. Use one under 5 MB.',
      );
    }
    return NewPhoto(bytes: bytes, extension: extension);
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => PhotoPicker());
