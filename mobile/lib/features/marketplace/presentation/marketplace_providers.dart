import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/listing_enums.dart';
import '../../auth/data/auth_repository.dart';
import '../data/listing_repository.dart';
import '../data/reservation_repository.dart';
import '../domain/listing.dart';
import '../domain/listing_input.dart';
import '../domain/listing_query.dart';
import '../domain/reservation.dart';

/// The signed-in user's id, to tell their own listings apart.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(userAccessProvider).value?.userId,
);

final categoriesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(listingRepositoryProvider).categories(),
);

/// One page-by-page feed of listings.
class FeedState {
  const FeedState({
    required this.items,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<Listing> items;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
}

class FeedController extends AsyncNotifier<FeedState> {
  FeedController(this.query);

  final ListingQuery query;

  @override
  Future<FeedState> build() async {
    final items = await ref.watch(listingRepositoryProvider).search(query);
    return FeedState(
      items: items,
      hasMore: items.length == ListingRepository.pageSize,
    );
  }

  /// Appends the next page; does nothing while loading or at the end.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      FeedState(items: current.items, hasMore: true, loadingMore: true),
    );
    try {
      final next = await ref
          .read(listingRepositoryProvider)
          .search(query, offset: current.items.length);
      if (!ref.mounted) return;
      state = AsyncData(
        FeedState(
          items: [...current.items, ...next],
          hasMore: next.length == ListingRepository.pageSize,
        ),
      );
    } on Object {
      if (!ref.mounted) return;
      state = AsyncData(
        FeedState(items: current.items, hasMore: true, loadMoreFailed: true),
      );
    }
  }
}

final feedProvider = AsyncNotifierProvider.autoDispose
    .family<FeedController, FeedState, ListingQuery>(FeedController.new);

final listingDetailProvider = FutureProvider.autoDispose
    .family<Listing, String>(
      (ref, id) => ref.watch(listingRepositoryProvider).fetch(id),
    );

final myListingsProvider = FutureProvider.autoDispose<List<Listing>>(
  (ref) => ref.watch(listingRepositoryProvider).mine(),
);

final myReservationsProvider = FutureProvider.autoDispose
    .family<List<ReservationCard>, ReservationSide>(
      (ref, side) => ref.watch(reservationRepositoryProvider).mine(side),
    );

/// Every change a user makes in the marketplace. Each method calls the
/// database and then refreshes the screens that show what changed. Failures
/// are thrown as `AppFailure` for the screen to show.
class MarketplaceActions {
  MarketplaceActions(this._ref);

  final Ref _ref;

  ListingRepository get _listings => _ref.read(listingRepositoryProvider);
  ReservationRepository get _reservations =>
      _ref.read(reservationRepositoryProvider);

  /// Saves the form, then publishes if asked. Returns the listing's id.
  Future<String> saveListing({
    required ListingInput input,
    required List<String> keptPhotos,
    required List<NewPhoto> newPhotos,
    required bool publish,
    String? listingId,
    List<String> previousPhotos = const [],
  }) async {
    final id = await _listings.save(
      input: input,
      keptPhotos: keptPhotos,
      newPhotos: newPhotos,
      listingId: listingId,
      previousPhotos: previousPhotos,
    );
    if (publish) await _listings.setStatus(id, ListingStatus.available);
    _refreshListing(id);
    return id;
  }

  Future<void> setListingStatus(String id, ListingStatus status) async {
    await _listings.setStatus(id, status);
    _refreshListing(id);
  }

  Future<void> reserve({
    required String listingId,
    required int qty,
    String? pickupNote,
  }) async {
    await _reservations.request(
      listingId: listingId,
      qty: qty,
      pickupNote: pickupNote,
    );
    _refreshListing(listingId);
    _ref.invalidate(myReservationsProvider);
  }

  Future<void> resolveReservation(
    ReservationCard reservation,
    ReservationAction action,
  ) async {
    await _reservations.resolve(reservation.id, action);
    _refreshListing(reservation.listingId);
    _ref.invalidate(myReservationsProvider);
  }

  Future<void> reportListing({
    required String listingId,
    required ReportReason reason,
    required String details,
  }) => _reservations.reportListing(
    listingId: listingId,
    reason: reason,
    details: details,
  );

  void _refreshListing(String id) {
    _ref
      ..invalidate(listingDetailProvider(id))
      ..invalidate(myListingsProvider)
      ..invalidate(feedProvider);
  }
}

final marketplaceActionsProvider = Provider<MarketplaceActions>(
  MarketplaceActions.new,
);
