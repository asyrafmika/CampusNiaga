import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/marketplace/data/listing_repository.dart';
import 'package:mobile/features/marketplace/data/reservation_repository.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/domain/reservation.dart';

const String meId = 'u1';
const String sellerId = 'u2';

Listing aListing({
  String id = 'l1',
  String ownerId = sellerId,
  String title = 'Casio FX-570 calculator',
  int priceSen = 2500,
  int stock = 1,
  ListingStatus status = ListingStatus.available,
  String category = 'Stationery',
  List<String> photos = const [],
}) => Listing(
  id: id,
  ownerId: ownerId,
  sellerName: ownerId == meId ? 'Me' : 'Siti',
  title: title,
  description: 'Used for one semester.',
  category: category,
  priceSen: priceSen,
  condition: ListingCondition.good,
  photoPaths: photos,
  stock: stock,
  pickupArea: 'Desasiswa Tekun',
  status: status,
  createdAt: DateTime.utc(2026, 11, 16),
);

ReservationCard aReservation({
  String id = 'r1',
  bool iAmBuyer = false,
  ReservationStatus status = ReservationStatus.requested,
  String? email,
}) => ReservationCard(
  id: id,
  listingId: 'l1',
  listingTitle: 'Casio FX-570 calculator',
  listingPhoto: null,
  pickupArea: 'Desasiswa Tekun',
  priceSen: 2500,
  qty: 1,
  pickupNote: 'After 5pm',
  status: status,
  expiresAt: DateTime.utc(2026, 11, 18),
  createdAt: DateTime.utc(2026, 11, 16),
  iAmBuyer: iAmBuyer,
  otherPartyName: iAmBuyer ? 'Ali' : 'Siti',
  otherPartyEmail: email,
);

/// In-memory listings; records every call.
class FakeListingRepository implements ListingRepository {
  FakeListingRepository({List<Listing>? feed, List<Listing>? mine})
    : feed = feed ?? [aListing()],
      mineList = mine ?? [];

  List<Listing> feed;
  List<Listing> mineList;
  final List<ListingQuery> queries = [];
  final List<String> calls = [];
  AppFailure? failWith;

  @override
  Future<List<String>> categories() async => const [
    'Books',
    'Electronics',
    'Stationery',
    'Others',
  ];

  @override
  Future<List<Listing>> search(ListingQuery query, {int offset = 0}) async {
    queries.add(query);
    if (failWith case final f?) throw f;
    return offset == 0 ? feed : const [];
  }

  @override
  Future<Listing> fetch(String id) async {
    if (failWith case final f?) throw f;
    return [...feed, ...mineList].firstWhere(
      (l) => l.id == id,
      orElse: () => throw const AppFailure(
        AppFailureReason.notFound,
        'This listing is no longer available.',
      ),
    );
  }

  @override
  Future<List<Listing>> mine() async => mineList;

  @override
  Future<String> save({
    required ListingInput input,
    required List<String> keptPhotos,
    required List<NewPhoto> newPhotos,
    String? listingId,
    List<String> previousPhotos = const [],
  }) async {
    calls.add(
      'save ${listingId ?? 'new'} ${input.title} ${input.priceSen} '
      'x${input.quantity} photos:${keptPhotos.length + newPhotos.length}',
    );
    if (failWith case final f?) throw f;
    final id = listingId ?? 'new1';
    mineList = [
      aListing(
        id: id,
        ownerId: meId,
        title: input.title,
        priceSen: input.priceSen,
        stock: input.quantity,
        status: ListingStatus.draft,
      ),
      ...mineList.where((l) => l.id != id),
    ];
    return id;
  }

  @override
  Future<void> setStatus(String id, ListingStatus status) async {
    calls.add('status $id ${status.wireName}');
    if (failWith case final f?) throw f;
  }

  @override
  PhotoRequest photo(String path) =>
      PhotoRequest('https://example.invalid/$path', const {});
}

/// In-memory reservations and reports; records every call.
class FakeReservationRepository implements ReservationRepository {
  FakeReservationRepository({
    List<ReservationCard>? buying,
    List<ReservationCard>? selling,
  }) : buying = buying ?? [],
       selling = selling ?? [];

  List<ReservationCard> buying;
  List<ReservationCard> selling;
  final List<String> calls = [];
  AppFailure? failWith;

  @override
  Future<void> request({
    required String listingId,
    required int qty,
    String? pickupNote,
  }) async {
    calls.add('request $listingId x$qty ${pickupNote ?? ''}'.trim());
    if (failWith case final f?) throw f;
  }

  @override
  Future<void> resolve(String reservationId, ReservationAction action) async {
    calls.add('resolve $reservationId ${action.wireName}');
    if (failWith case final f?) throw f;
  }

  @override
  Future<List<ReservationCard>> mine(ReservationSide side) async =>
      side == ReservationSide.buying ? buying : selling;

  @override
  Future<void> reportListing({
    required String listingId,
    required ReportReason reason,
    required String details,
  }) async {
    calls.add('report $listingId ${reason.wireName} $details'.trim());
    if (failWith case final f?) throw f;
  }
}
