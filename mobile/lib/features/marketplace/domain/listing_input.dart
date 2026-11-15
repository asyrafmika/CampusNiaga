import 'dart:typed_data';

import '../../../core/domain/listing_enums.dart';
import '../../../core/utils/money.dart';

/// The fields of the listing form, after the user has typed them.
class ListingInput {
  const ListingInput({
    required this.title,
    required this.description,
    required this.category,
    required this.priceSen,
    required this.condition,
    required this.quantity,
    required this.pickupArea,
  });

  final String title;
  final String description;
  final String category;
  final int priceSen;
  final ListingCondition condition;
  final int quantity;
  final String pickupArea;
}

/// A photo picked on the phone, already resized, waiting to be uploaded.
class NewPhoto {
  const NewPhoto({required this.bytes, required this.extension});

  final Uint8List bytes;

  /// `jpg`, `jpeg`, `png` or `webp`.
  final String extension;

  static const Set<String> allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  /// The file extension of [fileName] if it's an allowed image type.
  static String? extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return allowedExtensions.contains(ext) ? ext : null;
  }

  String get contentType => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Form checks. They mirror `upsert_listing`, which checks everything again;
/// these exist so the user sees the problem before sending.
abstract final class ListingRules {
  static const int maxPhotos = 5;
  static const int maxQuantity = 999;
  static const int maxPriceSen = 10000000;

  static String? title(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 3) return 'Use at least 3 characters.';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  static String? description(String? value) =>
      (value ?? '').trim().length > 1000
      ? 'Keep it under 1,000 characters.'
      : null;

  static String? price(String? value) {
    final sen = parseRmToSen(value ?? '');
    if (sen == null) return 'Enter a price, e.g. 25 or 12.50.';
    if (sen > maxPriceSen) return 'The maximum is RM 100,000.';
    return null;
  }

  static String? quantity(String? value) {
    final qty = int.tryParse((value ?? '').trim());
    if (qty == null || qty < 1 || qty > maxQuantity) {
      return 'Enter 1 to $maxQuantity.';
    }
    return null;
  }

  static String? pickupArea(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 2) return 'Where on campus can buyers collect it?';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  /// Why the listing can't be published yet, or `null`.
  static String? publishProblem(int photoCount) =>
      photoCount == 0 ? 'Add at least one photo to publish.' : null;
}
