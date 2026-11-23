/// Route paths, defined once.
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/welcome';
  static const String login = '/login';
  static const String signUp = '/sign-up';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifyEmail = '/verify-email';
  static const String notEligible = '/not-eligible';
  static const String suspended = '/suspended';
  static const String home = '/';

  // Bottom navigation tabs (home is the first).
  static const String search = '/search';
  static const String purchases = '/purchases';
  static const String profile = '/profile';

  // Full-screen pages opened from the tabs.
  static const String sell = '/sell';
  static const String myListings = '/my-listings';
  static String listing(String id) => '/listing/$id';
  static String editListing(String id) => '/listing/$id/edit';
  static String reportListing(String id) => '/listing/$id/report';
  static String listingPayment(String id, {bool publish = false}) => Uri(
    path: '/listing/$id/payment',
    queryParameters: publish ? {'publish': '1'} : null,
  ).toString();

  // Business application (M2): track status, the form, its documents.
  static const String business = '/business';
  static const String businessApply = '/business/apply';
  static const String businessDocuments = '/business/apply/documents';

  // Storefronts and orders (M3).
  static String storefront(String businessId) => '/store/$businessId';
  static String orderListing(String listingId, {String? campaignId}) => Uri(
    path: '/listing/$listingId/order',
    queryParameters: campaignId == null ? null : {'campaign': campaignId},
  ).toString();
  static const String orders = '/orders';
  static const String ordersSelling = '/orders?side=selling';
  static const String sellBusiness = '/sell?mode=business';
  static const String manageStore = '/business/store';
  static const String editStorefront = '/business/store/edit';
  static const String dashboard = '/business/store/dashboard';
  static const String newCampaign = '/business/store/campaigns/new';
  static String editCampaign(String campaignId) =>
      '/business/store/campaigns/$campaignId';

  // Transfer payments (ADR 0005): one payment, and where a business saves
  // its bank account or QR code. A student's own are on the listing's
  // payment step (ADR 0008).
  static String payment(String paymentId) => '/payments/$paymentId';
  static const String businessPaymentDetails =
      '/business/store/payment-details';

  // Opportunity discovery (M4). Cluster keys contain spaces, '&' and '|',
  // so they travel as an encoded query parameter.
  static const String discover = '/discover';
  static const String discoverRequest = '/discover/request';
  static String opportunity(String clusterKey) => Uri(
    path: '/discover/opportunity',
    queryParameters: {'key': clusterKey},
  ).toString();

  // Chat (ADRs 0004 and 0006): the list, one chat, or the chat of an item,
  // purchase or order (opened, and created if needed, from the listing,
  // Purchases and My orders).
  static const String messages = '/messages';
  static String chat(String conversationId) => '/messages/$conversationId';
  static String chatForListing(String listingId) => Uri(
    path: '/messages/open',
    queryParameters: {'listing': listingId},
  ).toString();
  static String chatForPurchase(String purchaseId) => Uri(
    path: '/messages/open',
    queryParameters: {'purchase': purchaseId},
  ).toString();
  static String chatForOrder(String orderId) => Uri(
    path: '/messages/open',
    queryParameters: {'order': orderId},
  ).toString();

  /// The search tab, opened on one category.
  static String searchCategory(String category) =>
      Uri(path: search, queryParameters: {'category': category}).toString();

  /// Screens a signed-out visitor may open.
  static const Set<String> public = {onboarding, login, signUp, forgotPassword};

  /// Screens that only make sense before a user is allowed in. An allowed user
  /// who lands on one is sent home.
  static const Set<String> gates = {
    splash,
    ...public,
    resetPassword,
    verifyEmail,
    notEligible,
    suspended,
  };
}
