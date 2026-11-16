import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/core/domain/listing_enums.dart';
import 'package:mobile/features/business/store/data/store_repository.dart';
import 'package:mobile/features/business/store/domain/store_models.dart';
import 'package:mobile/features/marketplace/data/listing_repository.dart';
import 'package:mobile/features/marketplace/domain/listing.dart';
import 'package:mobile/features/marketplace/domain/listing_input.dart';

const String storeId = 'b1';

/// Ali Bakes' brownie box: 3 in stock.
Listing aProduct({int stock = 3}) => Listing(
  id: 'p1',
  ownerId: 'u2',
  sellerName: 'Ali',
  title: 'Brownie box',
  description: 'Six fudgy brownies.',
  category: 'Food & Beverage',
  priceSen: 1200,
  condition: ListingCondition.brandNew,
  photoPaths: const [],
  stock: stock,
  pickupArea: 'Tekun lobby',
  status: stock > 0 ? ListingStatus.available : ListingStatus.sold,
  createdAt: DateTime.utc(2026, 11, 16),
  mode: ListingMode.business,
  businessId: storeId,
  businessName: 'Ali Bakes',
);

Campaign aCampaign({
  String id = 'c1',
  CampaignStatus status = CampaignStatus.open,
  int capacity = 3,
  int allocated = 0,
  int? perOrderLimit = 2,
}) => Campaign(
  id: id,
  listingId: 'p1',
  listingTitle: 'Brownie box',
  title: 'Raya brownies',
  priceSen: 1000,
  startAt: DateTime.now().subtract(const Duration(days: 1)),
  closeAt: DateTime.now().add(const Duration(days: 7)),
  capacity: capacity,
  allocatedQty: allocated,
  perOrderLimit: perOrderLimit,
  pickupDetails: 'Tekun lobby, Sat 10am',
  status: status,
);

Storefront aStorefront({
  List<Listing>? listings,
  List<Campaign>? campaigns,
  bool isOwner = false,
}) => Storefront(
  business: const StoreBusiness(
    id: storeId,
    name: 'Ali Bakes',
    description: 'Fudgy brownies every Friday.',
    pickupDetails: 'Tekun lobby, Fri 6-8pm',
    status: BusinessStatus.approved,
    ownerName: 'Ali',
  ),
  isOwner: isOwner,
  categories: const ['Food & Beverage'],
  listings: listings ?? [aProduct()],
  campaigns: campaigns ?? [aCampaign()],
);

OrderCard anOrder({
  String id = 'o1',
  OrderStatus status = OrderStatus.pendingConfirmation,
  bool iAmBuyer = true,
  String? campaignId,
  String? email,
}) => OrderCard(
  id: id,
  listingId: 'p1',
  listingTitle: 'Brownie box',
  businessId: storeId,
  businessName: 'Ali Bakes',
  campaignId: campaignId,
  campaignTitle: campaignId == null ? null : 'Raya brownies',
  qty: 2,
  unitPriceSen: 1200,
  totalSen: 2400,
  status: status,
  collectionDetails: 'Tekun lobby, Fri 6-8pm',
  buyerNote: 'After 6pm',
  createdAt: DateTime.utc(2026, 11, 16),
  cancelledBy: status == OrderStatus.cancelled ? 'seller' : null,
  iAmBuyer: iAmBuyer,
  otherPartyName: iAmBuyer ? 'Ali' : 'Siti',
  otherPartyEmail: email,
);

/// In-memory storefront, campaigns and orders; records every call.
class FakeStoreRepository implements StoreRepository {
  FakeStoreRepository({
    Storefront? storefront,
    List<Campaign>? campaigns,
    List<OrderCard>? buying,
    List<OrderCard>? selling,
  }) : store = storefront ?? aStorefront(),
       campaigns = campaigns ?? [],
       buying = buying ?? [],
       selling = selling ?? [];

  Storefront store;
  List<Campaign> campaigns;
  List<OrderCard> buying;
  List<OrderCard> selling;
  final List<String> calls = [];
  AppFailure? failWith;

  void _check() {
    if (failWith case final f?) throw f;
  }

  @override
  Future<Storefront> storefront(String businessId) async {
    _check();
    return store;
  }

  @override
  Future<void> updateStorefront({
    required String businessId,
    required String description,
    required String pickupDetails,
    String? logoPath,
    NewPhoto? newLogo,
  }) async {
    calls.add('storefront $businessId ${pickupDetails.trim()}');
    _check();
  }

  @override
  PhotoRequest logo(String path) =>
      PhotoRequest('https://example.invalid/$path', const {});

  @override
  Future<List<Campaign>> myCampaigns(String businessId) async => campaigns;

  @override
  Future<String> saveCampaign(CampaignInput input, {String? campaignId}) async {
    calls.add(
      'campaign ${campaignId ?? 'new'} ${input.listingId} ${input.title.trim()} '
      '${input.priceSen} cap${input.capacity} limit${input.perOrderLimit}',
    );
    _check();
    return campaignId ?? 'c9';
  }

  @override
  Future<void> setCampaignStatus(
    String campaignId,
    CampaignStatus status,
  ) async {
    calls.add('campaign $campaignId ${status.wireName}');
    _check();
  }

  @override
  Future<void> placeOrder({
    required String listingId,
    required int qty,
    String? campaignId,
    String? note,
  }) async {
    final trimmed = note?.trim() ?? '';
    calls.add(
      'order $listingId x$qty ${campaignId ?? 'stock'}'
      '${trimmed.isEmpty ? '' : ' $trimmed'}',
    );
    _check();
  }

  @override
  Future<void> transitionOrder(String orderId, OrderAction action) async {
    calls.add('transition $orderId ${action.wireName}');
    _check();
  }

  @override
  Future<void> setOrderCost(String orderId, int? costSen) async {
    calls.add('cost $orderId $costSen');
    _check();
  }

  @override
  Future<List<OrderCard>> myOrders(OrderSide side) async {
    _check();
    return side == OrderSide.buying ? buying : selling;
  }
}
