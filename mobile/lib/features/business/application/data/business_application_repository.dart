import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/domain/app_failure.dart';
import '../../../../core/supabase/supabase_guard.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../domain/business_application.dart';
import 'application_mappers.dart';

/// The student's business application (M2). The applicant writes the draft's
/// content directly (Row Level Security and column privileges allow only
/// that); every status change goes through `submit_business_application`.
class BusinessApplicationRepository {
  BusinessApplicationRepository(this._client);

  static const String _bucket = 'application-documents';
  static const String _columns =
      'id, business_name, category, description, contact_details, '
      'collection_details, document_paths, status, remarks, submitted_at, '
      'decided_at, created_at';

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AppFailure(AppFailureReason.forbidden, 'Sign in again.');
    }
    return id;
  }

  /// The student's most recent application, or `null` if they never applied.
  Future<BusinessApplication?> current() => guardSupabase(() async {
    final Map<String, dynamic>? row = await _client
        .from('business_applications')
        .select(_columns)
        .eq('applicant_id', _uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : applicationFromRow(row);
  });

  /// Every status change, oldest first.
  Future<List<ApplicationHistoryEntry>> history(String applicationId) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> rows = await _client
            .from('application_status_history')
            .select('from_status, to_status, actor_role, note, created_at')
            .eq('application_id', applicationId)
            .order('id');
        return rows.map(historyFromRow).toList();
      });

  /// Starts a draft and returns its id.
  Future<String> createDraft(ApplicationContent content) =>
      guardSupabase(() async {
        try {
          final Map<String, dynamic> row = await _client
              .from('business_applications')
              .insert(contentToRow(content))
              .select('id')
              .single();
          return row['id'] as String;
        } on PostgrestException catch (e) {
          // The one-unfinished-application index.
          if (e.code == '23505') {
            throw const AppFailure(
              AppFailureReason.alreadyExists,
              'You already have an application in progress.',
            );
          }
          rethrow;
        }
      });

  /// Saves the draft's fields. Refused once the application is with a
  /// reviewer or decided.
  Future<void> saveContent(String id, ApplicationContent content) =>
      _update(id, contentToRow(content));

  Future<void> setDocuments(String id, List<String> paths) =>
      _update(id, {'document_paths': paths});

  Future<void> _update(String id, Map<String, Object> values) =>
      guardSupabase(() async {
        final List<Map<String, dynamic>> rows = await _client
            .from('business_applications')
            .update(values)
            .eq('id', id)
            .select('id');
        // Row Level Security skips rows the user may not change, silently.
        if (rows.isEmpty) {
          throw const AppFailure(
            AppFailureReason.invalidTransition,
            'This application can’t be changed now.',
          );
        }
      });

  /// Uploads a document into the application's folder and returns its path.
  Future<String> uploadDocument(String applicationId, NewDocument document) =>
      guardSupabase(() async {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final path =
            '$_uid/$applicationId/${stamp}_'
            '${ApplicationRules.safeFileName(document.name)}';
        try {
          await _client.storage
              .from(_bucket)
              .uploadBinary(
                path,
                document.bytes,
                fileOptions: FileOptions(contentType: document.contentType),
              );
        } on StorageException catch (e) {
          throw switch (e.statusCode) {
            '413' => const AppFailure(
              AppFailureReason.invalidInput,
              'That file is too large. Use one under 5 MB.',
            ),
            '415' || '422' => const AppFailure(
              AppFailureReason.invalidInput,
              'Use a PDF, JPEG or PNG file.',
            ),
            // Refused by the storage policy: limit reached or not editable.
            '400' || '403' => const AppFailure(
              AppFailureReason.forbidden,
              'You can’t add more documents to this application.',
            ),
            _ => AppFailure.unknownFailure,
          };
        }
        return path;
      });

  /// Deletes an uploaded file. Best effort: a leftover file is harmless once
  /// the application no longer points at it.
  Future<void> deleteDocument(String path) async {
    try {
      await _client.storage.from(_bucket).remove([path]);
    } on Object catch (_) {}
  }

  /// Sends the application to the reviewers (or back to them after changes).
  Future<void> submit(String id, {String? responseNote}) =>
      guardSupabase(() async {
        final note = responseNote?.trim() ?? '';
        await _client.rpc<Object?>(
          'submit_business_application',
          params: {
            'application_id': id,
            'response_note': note.isEmpty ? null : note,
          },
        );
      });

  /// The student's business, or `null` before approval.
  Future<MyBusiness?> myBusiness() async {
    try {
      return await guardSupabase(() async {
        final Object? json = await _client.rpc<Object?>('get_my_business');
        return businessFromJson(json);
      });
    } on AppFailure catch (e) {
      if (e.reason == AppFailureReason.forbidden) return null;
      rethrow;
    }
  }
}

final businessApplicationRepositoryProvider =
    Provider<BusinessApplicationRepository>(
      (ref) => BusinessApplicationRepository(ref.watch(supabaseClientProvider)),
    );
