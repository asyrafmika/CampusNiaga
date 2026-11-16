import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/business_enums.dart';
import '../../../marketplace/domain/listing_input.dart';
import '../../../marketplace/presentation/marketplace_providers.dart';
import '../../application/presentation/application_providers.dart';
import '../data/store_repository.dart';
import '../domain/store_models.dart';

final storefrontProvider = FutureProvider.autoDispose
    .family<Storefront, String>(
      (ref, businessId) =>
          ref.watch(storeRepositoryProvider).storefront(businessId),
    );

/// The signed-in owner's campaigns; empty without a business.
final myCampaignsProvider = FutureProvider.autoDispose<List<Campaign>>((
  ref,
) async {
  final business = await ref.watch(myBusinessProvider.future);
  if (business == null) return const [];
  return ref.watch(storeRepositoryProvider).myCampaigns(business.id);
});

final myOrdersProvider = FutureProvider.autoDispose
    .family<List<OrderCard>, OrderSide>(
      (ref, side) => ref.watch(storeRepositoryProvider).myOrders(side),
    );

/// Every storefront, pre-order and order change. Each method calls the
/// database, then refreshes the screens that show what changed. Failures
/// are thrown as `AppFailure`.
class StoreActions {
  StoreActions(this._ref);

  final Ref _ref;

  StoreRepository get _store => _ref.read(storeRepositoryProvider);

  Future<void> placeOrder({
    required String listingId,
    required String businessId,
    required int qty,
    String? campaignId,
    String? note,
  }) async {
    await _store.placeOrder(
      listingId: listingId,
      qty: qty,
      campaignId: campaignId,
      note: note,
    );
    _refreshProduct(listingId, businessId);
  }

  Future<void> transitionOrder(OrderCard order, OrderAction action) async {
    await _store.transitionOrder(order.id, action);
    _refreshProduct(order.listingId, order.businessId);
  }

  Future<String> saveCampaign(CampaignInput input, {String? campaignId}) async {
    final id = await _store.saveCampaign(input, campaignId: campaignId);
    _refreshCampaigns();
    return id;
  }

  Future<void> setCampaignStatus(
    String campaignId,
    CampaignStatus status,
  ) async {
    await _store.setCampaignStatus(campaignId, status);
    _refreshCampaigns();
  }

  Future<void> updateStorefront({
    required String businessId,
    required String description,
    required String pickupDetails,
    String? logoPath,
    NewPhoto? newLogo,
  }) async {
    await _store.updateStorefront(
      businessId: businessId,
      description: description,
      pickupDetails: pickupDetails,
      logoPath: logoPath,
      newLogo: newLogo,
    );
    _ref
      ..invalidate(myBusinessProvider)
      ..invalidate(storefrontProvider(businessId));
  }

  void _refreshProduct(String listingId, String businessId) {
    _ref
      ..invalidate(myOrdersProvider)
      ..invalidate(storefrontProvider(businessId))
      ..invalidate(listingDetailProvider(listingId))
      ..invalidate(myListingsProvider)
      ..invalidate(myCampaignsProvider)
      ..invalidate(feedProvider);
  }

  void _refreshCampaigns() {
    _ref
      ..invalidate(myCampaignsProvider)
      ..invalidate(storefrontProvider);
  }
}

final storeActionsProvider = Provider<StoreActions>(StoreActions.new);
