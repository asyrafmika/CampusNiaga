import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/geo_point.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/domain/payment.dart';
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
  String? businessId,
  String? businessName,
  GeoPoint? pickupPin,
}) => Listing(
  id: id,
  ownerId: ownerId,
  mode: businessId == null ? ListingMode.personal : ListingMode.business,
  businessId: businessId,
  businessName: businessName,
  sellerName: ownerId == meId ? 'Me' : 'Siti',
  title: title,
  description: 'Used for one semester.',
  category: category,
  priceSen: priceSen,
  condition: ListingCondition.good,
  photoPaths: photos,
  stock: stock,
  pickupArea: 'Desasiswa Tekun',
  pickupPin: pickupPin,
  status: status,
  createdAt: DateTime.utc(2026, 11, 16),
);

ReservationCard aReservation({
  String id = 'r1',
  bool iAmBuyer = false,
  ReservationStatus status = ReservationStatus.requested,
  String? email,
  PaymentSummary? payment,
}) => ReservationCard(
  payment: payment,
  id: id,
  listingId: 'l1',
  listingTitle: 'Casio FX-570 calculator',
  listingPhoto: null,
  pickupArea: 'Desasiswa Tekun',
  priceSen: 2500,
  qty: 1,
  pickupNote: 'After 5pm',
  status: status,
  // Relative to now: a fixed date would make every reservation overdue once
  // it passed (which hides the chat button).
  expiresAt: DateTime.now().add(const Duration(days: 2)),
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

  /// The pin the last save sent.
  GeoPoint? savedPin;

  @override
  Future<String> save({
    required ListingInput input,
    required List<String> keptPhotos,
    required List<NewPhoto> newPhotos,
    String? listingId,
    List<String> previousPhotos = const [],
    ListingMode mode = ListingMode.personal,
  }) async {
    calls.add(
      'save ${listingId ?? 'new'} ${input.title} ${input.priceSen} '
      'x${input.quantity} photos:${keptPhotos.length + newPhotos.length}'
      '${mode == ListingMode.business ? ' business' : ''}',
    );
    savedPin = input.pickupPin;
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
        pickupPin: input.pickupPin,
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

  /// The payment id a transfer reservation returns.
  String transferPaymentId = 'pay1';

  @override
  Future<String?> request({
    required String listingId,
    required int qty,
    String? pickupNote,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    final transfer = paymentMethod == PaymentMethod.transfer;
    calls.add(
      'request $listingId x$qty ${pickupNote ?? ''}'.trim() +
          (transfer ? ' transfer' : ''),
    );
    if (failWith case final f?) throw f;
    return transfer ? transferPaymentId : null;
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
