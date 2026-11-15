import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_application_repository.dart';
import '../domain/business_application.dart';

/// The student's latest application; `null` if they never applied.
final myApplicationProvider = FutureProvider.autoDispose<BusinessApplication?>(
  (ref) => ref.watch(businessApplicationRepositoryProvider).current(),
);

final applicationHistoryProvider = FutureProvider.autoDispose
    .family<List<ApplicationHistoryEntry>, String>(
      (ref, id) => ref.watch(businessApplicationRepositoryProvider).history(id),
    );

/// The student's business once approved; `null` before that.
final myBusinessProvider = FutureProvider.autoDispose<MyBusiness?>(
  (ref) => ref.watch(businessApplicationRepositoryProvider).myBusiness(),
);

/// Every change the applicant makes. Each method calls the database, then
/// refreshes what the screens show. Failures are thrown as `AppFailure`.
class ApplicationActions {
  ApplicationActions(this._ref);

  final Ref _ref;

  BusinessApplicationRepository get _repository =>
      _ref.read(businessApplicationRepositoryProvider);

  /// Creates the draft ([applicationId] null) or saves its fields. Returns
  /// the application's id.
  Future<String> save({
    required ApplicationContent content,
    String? applicationId,
  }) async {
    final String id;
    if (applicationId == null) {
      id = await _repository.createDraft(content);
    } else {
      id = applicationId;
      await _repository.saveContent(id, content);
    }
    _ref.invalidate(myApplicationProvider);
    return id;
  }

  /// Uploads [document] and attaches it to the application.
  Future<void> addDocument(
    BusinessApplication application,
    NewDocument document,
  ) async {
    final path = await _repository.uploadDocument(application.id, document);
    try {
      await _repository.setDocuments(application.id, [
        ...application.documentPaths,
        path,
      ]);
    } on Object {
      await _repository.deleteDocument(path);
      rethrow;
    } finally {
      _ref.invalidate(myApplicationProvider);
    }
  }

  /// Detaches a document, then deletes the file.
  Future<void> removeDocument(
    BusinessApplication application,
    String path,
  ) async {
    await _repository.setDocuments(application.id, [
      for (final p in application.documentPaths)
        if (p != path) p,
    ]);
    await _repository.deleteDocument(path);
    _ref.invalidate(myApplicationProvider);
  }

  /// Sends the application to the reviewers, with an optional reply when
  /// resubmitting after a request for changes.
  Future<void> submit(String applicationId, {String? responseNote}) async {
    await _repository.submit(applicationId, responseNote: responseNote);
    _ref
      ..invalidate(myApplicationProvider)
      ..invalidate(applicationHistoryProvider(applicationId));
  }

  /// Reloads the application, its history and the business, e.g. after a
  /// reviewer may have decided. (Not the user's access: reloading it would
  /// send the router back through the splash screen.)
  void refresh(String? applicationId) {
    _ref
      ..invalidate(myApplicationProvider)
      ..invalidate(myBusinessProvider);
    if (applicationId != null) {
      _ref.invalidate(applicationHistoryProvider(applicationId));
    }
  }
}

final applicationActionsProvider = Provider<ApplicationActions>(
  ApplicationActions.new,
);
