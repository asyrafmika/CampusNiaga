import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/geo_point.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/core/domain/payment.dart';
import 'package:mobile/features/marketplace/data/listing_repository.dart';
import 'package:mobile/features/marketplace/data/purchase_repository.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';
import 'package:mobile/features/marketplace/domain/listing_query.dart';
import 'package:mobile/features/marketplace/domain/purchase.dart';

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

PurchaseCard aPurchase({
  String id = 'r1',
  bool iAmBuyer = false,
  PurchaseStatus? status,
  PaymentSummary? payment,
  String? cancelledBy,
  String? cancelReason,
  DateTime? relistFrom,
}) {
  final resolved =
      status ??
      (payment == null
          ? PurchaseStatus.awaitingHandover
          : PurchaseStatus.awaitingPayment);
  return PurchaseCard(
    payment: payment,
    id: id,
    listingId: 'l1',
    listingTitle: 'Casio FX-570 calculator',
    listingPhoto: null,
    pickupArea: 'Desasiswa Tekun',
    qty: 1,
    unitPriceSen: 2500,
    totalSen: 2500,
    paymentMethod: payment == null
        ? PaymentMethod.cash
        : PaymentMethod.transfer,
    status: resolved,
    cancelledBy: cancelledBy,
    cancelReason: cancelReason,
    // Relative to now, as the database's is: 24 hours after a cash purchase.
    relistFrom:
        relistFrom ??
        (payment == null && resolved == PurchaseStatus.awaitingHandover
            ? DateTime.now().add(const Duration(hours: 20))
            : null),
    createdAt: DateTime.utc(2026, 11, 16),
    iAmBuyer: iAmBuyer,
    otherPartyName: iAmBuyer ? 'Ali' : 'Siti',
  );
}

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

/// In-memory purchases and reports; records every call.
class FakePurchaseRepository implements PurchaseRepository {
  FakePurchaseRepository({
    List<PurchaseCard>? buying,
    List<PurchaseCard>? selling,
  }) : buying = buying ?? [],
       selling = selling ?? [];

  List<PurchaseCard> buying;
  List<PurchaseCard> selling;
  final List<String> calls = [];
  AppFailure? failWith;

  /// The payment id a transfer purchase returns.
  String transferPaymentId = 'pay1';

  /// Set to keep a purchase in flight until it completes.
  Future<void>? buyGate;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith case final f?) throw f;
  }

  @override
  Future<String?> buy({
    required String listingId,
    required int qty,
    PaymentMethod paymentMethod = PaymentMethod.cash,
  }) async {
    final transfer = paymentMethod == PaymentMethod.transfer;
    await _record('buy $listingId x$qty${transfer ? ' transfer' : ''}');
    await buyGate;
    return transfer ? transferPaymentId : null;
  }

  @override
  Future<void> complete(String purchaseId) => _record('complete $purchaseId');

  @override
  Future<void> relist(String purchaseId) => _record('relist $purchaseId');

  @override
  Future<void> cancel(
    String purchaseId, {
    String? reason,
    bool relist = true,
  }) => _record(
    'cancel $purchaseId${reason == null ? '' : ' "$reason"'}'
    '${relist ? '' : ' delete'}',
  );

  @override
  Future<List<PurchaseCard>> mine(PurchaseSide side) async =>
      side == PurchaseSide.buying ? buying : selling;

  @override
  Future<void> reportListing({
    required String listingId,
    required ReportReason reason,
    required String details,
  }) => _record('report $listingId ${reason.wireName} $details'.trim());
}
