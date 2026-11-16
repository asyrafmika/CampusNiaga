import 'dart:typed_data';

import '../../../../core/domain/business_enums.dart';

/// The student's business application (`business_applications`).
class BusinessApplication {
  const BusinessApplication({
    required this.id,
    required this.content,
    required this.documentPaths,
    required this.status,
    required this.createdAt,
    this.remarks,
    this.submittedAt,
    this.decidedAt,
  });

  final String id;
  final ApplicationContent content;
  final List<String> documentPaths;
  final ApplicationStatus status;

  /// The reviewer's latest note.
  final String? remarks;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final DateTime? decidedAt;

  bool get canEdit => ApplicationRules.canEdit(status);
}

/// The fields the applicant fills in. Drafts may leave any of them empty;
/// [ApplicationRules] says what a submission needs.
class ApplicationContent {
  const ApplicationContent({
    required this.businessName,
    required this.category,
    required this.description,
    required this.contactDetails,
    required this.collectionDetails,
  });

  static const ApplicationContent empty = ApplicationContent(
    businessName: '',
    category: '',
    description: '',
    contactDetails: '',
    collectionDetails: '',
  );

  final String businessName;

  /// One of the listing categories, or empty while drafting.
  final String category;
  final String description;
  final String contactDetails;
  final String collectionDetails;

  /// The same text with surrounding spaces removed, as it is saved.
  ApplicationContent trimmed() => ApplicationContent(
    businessName: businessName.trim(),
    category: category.trim(),
    description: description.trim(),
    contactDetails: contactDetails.trim(),
    collectionDetails: collectionDetails.trim(),
  );
}

/// One step in the application's timeline (`application_status_history`).
class ApplicationHistoryEntry {
  const ApplicationHistoryEntry({
    required this.from,
    required this.to,
    required this.actor,
    required this.createdAt,
    this.note,
  });

  final ApplicationStatus from;
  final ApplicationStatus to;
  final ApplicationActor actor;
  final String? note;
  final DateTime createdAt;
}

/// The student's business, once approved (`get_my_business()`).
class MyBusiness {
  const MyBusiness({
    required this.id,
    required this.name,
    required this.description,
    required this.pickupDetails,
    required this.status,
    this.logoPath,
  });

  final String id;
  final String name;
  final String description;
  final String pickupDetails;
  final BusinessStatus status;

  /// In `business-logos` (Phase 4).
  final String? logoPath;
}

/// A document picked on the phone, waiting to be uploaded.
class NewDocument {
  const NewDocument({required this.name, required this.bytes});

  /// The file name as picked, e.g. `Food handling certificate.pdf`.
  final String name;
  final Uint8List bytes;

  /// `pdf`, `jpg`, `jpeg` or `png`; `null` for any other type.
  String? get extension => ApplicationRules.documentExtension(name);

  String get contentType => switch (extension) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    _ => 'image/jpeg',
  };
}

/// The application rules, mirroring `submit_business_application` and the
/// state machine in docs/data-dictionary.md. The database checks everything
/// again; these let the app show problems before sending.
abstract final class ApplicationRules {
  static const int maxDocuments = 5;
  static const int maxDocumentBytes = 5 * 1024 * 1024;
  static const Set<String> documentExtensions = {'pdf', 'jpg', 'jpeg', 'png'};

  /// The applicant may change the content only while drafting or after the
  /// reviewer asked for changes.
  static bool canEdit(ApplicationStatus status) =>
      status == ApplicationStatus.draft ||
      status == ApplicationStatus.infoRequested;

  /// Waiting for, or with, a reviewer.
  static bool isWithReviewer(ApplicationStatus status) =>
      status == ApplicationStatus.submitted ||
      status == ApplicationStatus.underReview;

  /// A final decision; a rejected applicant may start again.
  static bool isFinal(ApplicationStatus status) =>
      status == ApplicationStatus.approved ||
      status == ApplicationStatus.rejected;

  static String? businessName(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 3) return 'Use at least 3 characters.';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  static String? category(String? value) =>
      (value ?? '').trim().isEmpty ? 'Choose a category.' : null;

  static String? description(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 20) return 'Describe what you sell in at least 20 characters.';
    if (length > 1000) return 'Keep it under 1,000 characters.';
    return null;
  }

  static String? contactDetails(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 5) return 'How can buyers reach you? (at least 5 characters)';
    if (length > 200) return 'Keep it under 200 characters.';
    return null;
  }

  static String? collectionDetails(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 5) return 'Where and when do buyers collect?';
    if (length > 200) return 'Keep it under 200 characters.';
    return null;
  }

  static String? responseNote(String? value) =>
      (value ?? '').trim().length > 500
      ? 'Keep it under 500 characters.'
      : null;

  /// Saving a draft only enforces the length limits, so a half-finished
  /// draft can be kept.
  static String? draftLength(String? value, int max) =>
      (value ?? '').trim().length > max
      ? 'Keep it under $max characters.'
      : null;

  /// The first problem that stops [content] being submitted, or `null`.
  static String? submitProblem(ApplicationContent content) =>
      businessName(content.businessName) ??
      category(content.category) ??
      description(content.description) ??
      contactDetails(content.contactDetails) ??
      collectionDetails(content.collectionDetails);

  /// The lowercase extension of [fileName] if it's an allowed document type.
  static String? documentExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return documentExtensions.contains(ext) ? ext : null;
  }

  /// The name to show for a stored document path. Uploads are stored as
  /// `{applicant}/{application}/{timestamp}_{name}`.
  static String documentName(String path) {
    final file = path.split('/').last;
    final match = RegExp(r'^\d+_(.+)$').firstMatch(file);
    return match?.group(1) ?? file;
  }

  /// A file name that is safe in a Storage path: letters, digits, dot, dash
  /// and underscore, at most 60 characters, keeping the extension.
  static String safeFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot < 0 ? fileName : fileName.substring(0, dot);
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    var clean = base
        .replaceAll(RegExp('[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
    if (clean.isEmpty) clean = 'document';
    if (clean.length > 60) clean = clean.substring(0, 60);
    return ext.isEmpty ? clean : '$clean.$ext';
  }
}
