import 'dart:typed_data';

import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/business/application/data/business_application_repository.dart';
import 'package:mobile/features/business/application/data/document_picker.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';

const ApplicationContent completeContent = ApplicationContent(
  businessName: 'Ali Bakes',
  category: 'Others',
  description: 'Homemade brownies and cookies, baked fresh every week.',
  contactDetails: '012-3456789',
  collectionDetails: 'Desasiswa Tekun lobby, 6-8pm',
);

BusinessApplication anApplication({
  ApplicationStatus status = ApplicationStatus.draft,
  ApplicationContent content = completeContent,
  List<String> documents = const [],
  String? remarks,
}) => BusinessApplication(
  id: 'a1',
  content: content,
  documentPaths: documents,
  status: status,
  remarks: remarks,
  createdAt: DateTime.utc(2026, 11, 16),
  submittedAt: status == ApplicationStatus.draft
      ? null
      : DateTime.utc(2026, 11, 16, 9),
  decidedAt:
      status == ApplicationStatus.approved ||
          status == ApplicationStatus.rejected
      ? DateTime.utc(2026, 11, 17)
      : null,
);

/// An in-memory application that follows the database's rules closely
/// enough for screen tests; records every call.
class FakeBusinessApplicationRepository
    implements BusinessApplicationRepository {
  FakeBusinessApplicationRepository({
    this.application,
    this.entries = const [],
    this.business,
  });

  BusinessApplication? application;
  List<ApplicationHistoryEntry> entries;
  MyBusiness? business;
  final List<String> calls = [];
  AppFailure? failWith;

  void _check() {
    if (failWith case final failure?) throw failure;
  }

  BusinessApplication _copy({
    ApplicationContent? content,
    List<String>? documents,
    ApplicationStatus? status,
  }) {
    final a = application!;
    return BusinessApplication(
      id: a.id,
      content: content ?? a.content,
      documentPaths: documents ?? a.documentPaths,
      status: status ?? a.status,
      remarks: a.remarks,
      createdAt: a.createdAt,
      submittedAt: a.submittedAt,
      decidedAt: a.decidedAt,
    );
  }

  @override
  Future<BusinessApplication?> current() async => application;

  @override
  Future<List<ApplicationHistoryEntry>> history(String applicationId) async =>
      entries;

  @override
  Future<String> createDraft(ApplicationContent content) async {
    calls.add('create ${content.trimmed().businessName}');
    _check();
    if (application case final a? when !ApplicationRules.isFinal(a.status)) {
      throw const AppFailure(
        AppFailureReason.alreadyExists,
        'You already have an application in progress.',
      );
    }
    application = BusinessApplication(
      id: 'a2',
      content: content.trimmed(),
      documentPaths: const [],
      status: ApplicationStatus.draft,
      createdAt: DateTime.utc(2026, 11, 18),
    );
    return 'a2';
  }

  @override
  Future<void> saveContent(String id, ApplicationContent content) async {
    calls.add('save $id ${content.trimmed().businessName}');
    _check();
    application = _copy(content: content.trimmed());
  }

  @override
  Future<void> setDocuments(String id, List<String> paths) async {
    calls.add('documents $id ${paths.length}');
    _check();
    application = _copy(documents: paths);
  }

  @override
  Future<String> uploadDocument(
    String applicationId,
    NewDocument document,
  ) async {
    calls.add('upload ${document.name}');
    _check();
    return 'u1/$applicationId/1_${ApplicationRules.safeFileName(document.name)}';
  }

  @override
  Future<void> deleteDocument(String path) async => calls.add('delete $path');

  @override
  Future<void> submit(String id, {String? responseNote}) async {
    calls.add('submit $id${responseNote == null ? '' : ' $responseNote'}');
    _check();
    application = _copy(status: ApplicationStatus.submitted);
  }

  @override
  Future<MyBusiness?> myBusiness() async => business;
}

/// Hands back [next] instead of opening the phone's file picker.
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker([this.next]);

  NewDocument? next;

  @override
  Future<NewDocument?> pick() async => next;
}

NewDocument aDocument([String name = 'Food certificate.pdf']) =>
    NewDocument(name: name, bytes: Uint8List.fromList([1, 2, 3]));
