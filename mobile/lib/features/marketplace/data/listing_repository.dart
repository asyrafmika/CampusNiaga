import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/domain/app_failure.dart';
import '../../../core/domain/listing_enums.dart';
import '../../../core/supabase/supabase_guard.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../domain/listing.dart';
import '../domain/listing_input.dart';
import '../domain/listing_query.dart';
import 'marketplace_mappers.dart';

/// How the app loads a private listing photo: the Storage URL plus the
/// signed-in user's token.
class PhotoRequest {
  const PhotoRequest(this.url, this.headers);

  final String url;
  final Map<String, String> headers;
}

/// Listings: the feed, the detail page, My Listings, saving (with photo
/// upload) and status changes. Writes go only through `upsert_listing` and
/// `set_listing_status`.
class ListingRepository {
  ListingRepository(this._client);

  static const int pageSize = 20;
  static const String _bucket = 'listing-photos';

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AppFailure(AppFailureReason.forbidden, 'Sign in again.');
    }
    return id;
  }

  Future<List<String>> categories() => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>('listing_categories');
    return (result as List<dynamic>? ?? const []).cast<String>();
  });

  Future<List<Listing>> search(ListingQuery query, {int offset = 0}) =>
      guardSupabase(() async {
        final Object? result = await _client.rpc<Object?>(
          'search_listings',
          params: {
            'search': query.search.trim().isEmpty ? null : query.search.trim(),
            'category': query.category,
            'condition': query.condition?.wireName,
            'min_price_sen': query.minPriceSen,
            'max_price_sen': query.maxPriceSen,
            'sort': query.sort.wireName,
            'page_size': pageSize,
            'page_offset': offset,
          },
        );
        return rowsOf(result).map(listingFromRow).toList();
      });

  Future<Listing> fetch(String id) => guardSupabase(() async {
    final Object? result = await _client.rpc<Object?>(
      'get_listing',
      params: {'listing_id': id},
    );
    final rows = rowsOf(result);
    if (rows.isEmpty) {
      throw const AppFailure(
        AppFailureReason.notFound,
        'This listing is no longer available.',
      );
    }
    return listingFromRow(rows.first);
  });

  /// The user's own listings, newest change first. Read straight from the
  /// table: Row Level Security lets owners see their own rows.
  Future<List<Listing>> mine() => guardSupabase(() async {
    final List<Map<String, dynamic>> rows = await _client
        .from('listings')
        .select(
          'id, owner_id, mode, business_id, title, description, category, '
          'price_sen, condition, photo_paths, stock, pickup_area, pickup_lat, '
          'pickup_lng, status, hidden, created_at',
        )
        .eq('owner_id', _uid)
        .order('updated_at', ascending: false);
    return rows.map(listingFromRow).toList();
  });

  /// Creates or edits a listing and returns its id. A new listing is created
  /// as a draft first, because photos are stored under the listing's id;
  /// then the photos are uploaded and the listing saved with their paths.
  /// Photos the user removed are deleted from Storage afterwards.
  Future<String> save({
    required ListingInput input,
    required List<String> keptPhotos,
    required List<NewPhoto> newPhotos,
    String? listingId,
    List<String> previousPhotos = const [],
    ListingMode mode = ListingMode.personal,
  }) => guardSupabase(() async {
    final uid = _uid;
    var id = listingId;
    if (id == null) {
      id = await _upsert(null, input, const [], mode: mode);
      if (newPhotos.isEmpty) return id;
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final uploaded = <String>[];
    for (var i = 0; i < newPhotos.length; i++) {
      final photo = newPhotos[i];
      final path = '$uid/$id/${stamp}_$i.${photo.extension}';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            photo.bytes,
            fileOptions: FileOptions(contentType: photo.contentType),
          );
      uploaded.add(path);
    }

    await _upsert(id, input, [...keptPhotos, ...uploaded]);

    final removed = previousPhotos
        .where((p) => !keptPhotos.contains(p))
        .toList();
    if (removed.isNotEmpty) {
      // Best effort: a leftover file is harmless, the listing no longer
      // points at it.
      try {
        await _client.storage.from(_bucket).remove(removed);
      } on Object catch (_) {}
    }
    return id;
  });

  Future<String> _upsert(
    String? id,
    ListingInput input,
    List<String> photos, {
    ListingMode mode = ListingMode.personal,
  }) async {
    final Object? result = await _client.rpc<Object?>(
      'upsert_listing',
      params: {
        'listing_id': id,
        'title': input.title.trim(),
        'description': input.description.trim(),
        'category': input.category,
        'price_sen': input.priceSen,
        'condition': input.condition.wireName,
        'quantity': input.quantity,
        'photo_paths': photos,
        'pickup_area': input.pickupArea.trim(),
        // Always sent: null removes the pin.
        'pickup_lat': input.pickupPin?.latitude,
        'pickup_lng': input.pickupPin?.longitude,
        // Only sent for business products (the mode matters only when
        // creating), so personal listings work with any database version.
        if (mode == ListingMode.business) 'mode': mode.wireName,
      },
    );
    return (result! as Map)['listing_id'] as String;
  }

  Future<void> setStatus(String id, ListingStatus status) =>
      guardSupabase(() async {
        await _client.rpc<Object?>(
          'set_listing_status',
          params: {'listing_id': id, 'new_status': status.wireName},
        );
      });

  /// The URL and headers to load a photo with the user's own access.
  PhotoRequest photo(String path) => PhotoRequest(
    '${SupabaseConfig.url}/storage/v1/object/authenticated/$_bucket/$path',
    {
      'apikey': SupabaseConfig.publishableKey,
      'Authorization':
          'Bearer ${_client.auth.currentSession?.accessToken ?? ''}',
    },
  );
}

final listingRepositoryProvider = Provider<ListingRepository>(
  (ref) => ListingRepository(ref.watch(supabaseClientProvider)),
);
