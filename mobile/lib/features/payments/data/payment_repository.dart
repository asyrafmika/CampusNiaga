import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/domain/app_failure.dart';
import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../marketplace/data/listing_repository.dart';
import '../../marketplace/domain/listing_input.dart';
import '../domain/payment_models.dart';
import 'payment_mappers.dart';

/// Transfer payments (ADR 0005): the seller's payment details, the payment
/// page, proof and the seller's decision. Writes go through database
/// functions; images live in two private buckets.
class PaymentRepository {
  PaymentRepository(this._client);

  static const String qrBucket = 'payment-qr';
  static const String proofBucket = 'payment-proofs';

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AppFailure(AppFailureReason.forbidden, 'Sign in again.');
    }
    return id;
  }

  /// The signed-in student's details (and their business's). Row Level
  /// Security lets only the owner read them.
  Future<SavedPaymentDetails> mine() => guardSupabase(() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('payment_details')
        .select(
          'business_id, bank_name, account_name, account_number, qr_path',
        );
    return savedDetailsFromRows(rows);
  });

  /// Saves the details; uploads [newQr] first when given. With no account
  /// number and no QR code, the details are removed.
  Future<void> saveDetails({
    required bool forBusiness,
    required String bankName,
    required String accountName,
    required String accountNumber,
    String? keptQrPath,
    NewPhoto? newQr,
    String? previousQrPath,
  }) => guardSupabase(() async {
    var qrPath = keptQrPath;
    if (newQr != null) {
      qrPath =
          '$_uid/qr_${DateTime.now().millisecondsSinceEpoch}.${newQr.extension}';
      await _client.storage
          .from(qrBucket)
          .uploadBinary(
            qrPath,
            newQr.bytes,
            fileOptions: FileOptions(contentType: newQr.contentType),
          );
    }
    String? text(String value) => value.trim().isEmpty ? null : value.trim();
    await _client.rpc<Object?>(
      'set_payment_details',
      params: {
        'for_business': forBusiness,
        'bank_name': text(bankName),
        'account_name': text(accountName),
        'account_number': text(accountNumber),
        'qr_path': qrPath,
      },
    );
    // Best effort: the old QR image is no longer used.
    if (previousQrPath != null && previousQrPath != qrPath) {
      try {
        await _client.storage.from(qrBucket).remove([previousQrPath]);
      } on Object catch (_) {}
    }
  });

  /// Whether a buyer can choose transfer for [listingId].
  Future<bool> acceptsTransfer(String listingId) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'seller_accepts_transfer',
      params: {'listing_id': listingId},
    );
    return result == true;
  });

  Future<PaymentView> payment(String paymentId) => guardSupabase(() async {
    final Object? json = await _client.rpc<Object?>(
      'get_payment',
      params: {'payment_id': paymentId},
    );
    return paymentViewFromJson(json);
  });

  /// Uploads the screenshot into the payment's folder, then sends it.
  Future<void> submitProof(String paymentId, NewPhoto photo) =>
      guardSupabase(() async {
        final path =
            '$_uid/$paymentId/proof_${DateTime.now().millisecondsSinceEpoch}'
            '.${photo.extension}';
        await _client.storage
            .from(proofBucket)
            .uploadBinary(
              path,
              photo.bytes,
              fileOptions: FileOptions(contentType: photo.contentType),
            );
        await _client.rpc<Object?>(
          'submit_payment_proof',
          params: {'payment_id': paymentId, 'proof_path': path},
        );
      });

  Future<void> review(
    String paymentId, {
    required bool accept,
    String? reason,
  }) => guardSupabase(() async {
    await _client.rpc<Object?>(
      'review_payment',
      params: {
        'payment_id': paymentId,
        'accept': accept,
        'reason': accept ? null : reason?.trim(),
      },
    );
  });

  /// The URL and headers to load a QR code or proof with the user's own
  /// access (Storage checks who may read it).
  PhotoRequest image(String bucket, String path) => PhotoRequest(
    '${SupabaseConfig.url}/storage/v1/object/authenticated/$bucket/$path',
    {
      'apikey': SupabaseConfig.publishableKey,
      'Authorization':
          'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
    },
  );
}

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => PaymentRepository(ref.watch(supabaseClientProvider)),
);
