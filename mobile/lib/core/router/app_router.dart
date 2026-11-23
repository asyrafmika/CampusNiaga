import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/domain/access_gate.dart';
import '../../features/auth/presentation/gate_screens.dart';
import '../../features/auth/presentation/password_screens.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/business/application/presentation/application_documents_screen.dart';
import '../../features/business/application/presentation/application_form_screen.dart';
import '../../features/business/application/presentation/business_application_screen.dart';
import '../../features/business/store/domain/store_models.dart';
import '../../features/business/store/presentation/campaign_form_screen.dart';
import '../../features/business/store/presentation/manage_store_screen.dart';
import '../../features/business/store/presentation/my_orders_screen.dart';
import '../../features/business/store/presentation/order_screen.dart';
import '../../features/business/store/presentation/storefront_edit_screen.dart';
import '../../features/business/store/presentation/storefront_screen.dart';
import '../../features/chat/domain/chat_models.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/messages_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/discovery/presentation/discover_screen.dart';
import '../../features/discovery/presentation/opportunity_detail_screen.dart';
import '../../features/discovery/presentation/request_form_screen.dart';
import '../../features/marketplace/presentation/home_screen.dart';
import '../../features/marketplace/presentation/listing_detail_screen.dart';
import '../../features/marketplace/presentation/listing_form_screen.dart';
import '../../features/marketplace/presentation/listing_payment_screen.dart';
import '../../features/marketplace/presentation/my_listings_screen.dart';
import '../../features/marketplace/presentation/my_purchases_screen.dart';
import '../../features/marketplace/presentation/report_listing_screen.dart';
import '../../features/marketplace/presentation/search_screen.dart';
import '../../features/onboarding/presentation/onboarding_controller.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/payments/presentation/payment_details_screen.dart';
import '../../features/payments/presentation/payment_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';

/// The app's single router. It re-runs [redirectFor] whenever the user's
/// access gate or onboarding state changes, so screens never navigate after
/// signing in, signing out or finishing onboarding.
final appRouterProvider = Provider<GoRouter>((ref) {
  final state = ValueNotifier<(AccessGate, bool)>((
    ref.read(accessGateProvider),
    ref.read(onboardingSeenProvider),
  ));
  ref.listen(
    accessGateProvider,
    (_, gate) => state.value = (gate, state.value.$2),
  );
  ref.listen(
    onboardingSeenProvider,
    (_, seen) => state.value = (state.value.$1, seen),
  );

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: state,
    redirect: (context, routerState) => redirectFor(
      state.value.$1,
      routerState.matchedLocation,
      onboardingSeen: state.value.$2,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.notEligible,
        builder: (context, state) => const NotEligibleScreen(),
      ),
      GoRoute(
        path: AppRoutes.suspended,
        builder: (context, state) => const SuspendedScreen(),
      ),
      // The signed-in app: four tabs, each keeping its own page stack.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search,
                builder: (context, state) {
                  final category = state.uri.queryParameters['category'];
                  return SearchScreen(
                    key: ValueKey(category),
                    initialCategory: category,
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.purchases,
                builder: (context, state) => const MyPurchasesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen pages, above the tabs.
      GoRoute(
        path: AppRoutes.sell,
        builder: (context, state) => ListingFormScreen(
          business: state.uri.queryParameters['mode'] == 'business',
        ),
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => MyOrdersScreen(
          initialSide: state.uri.queryParameters['side'] == 'selling'
              ? OrderSide.selling
              : OrderSide.buying,
        ),
      ),
      GoRoute(
        path: AppRoutes.discover,
        builder: (context, state) => const DiscoverScreen(),
        routes: [
          GoRoute(
            path: 'request',
            builder: (context, state) => const RequestFormScreen(),
          ),
          GoRoute(
            path: 'opportunity',
            builder: (context, state) => OpportunityDetailScreen(
              clusterKey: state.uri.queryParameters['key'] ?? '',
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.messages,
        builder: (context, state) => const MessagesScreen(),
        routes: [
          // Before ':id', so "open" is never read as a chat id.
          GoRoute(
            path: 'open',
            builder: (context, state) {
              final query = state.uri.queryParameters;
              return ChatScreen(
                deal: switch (query) {
                  {'order': final id} => ChatDeal.order(id),
                  {'purchase': final id} => ChatDeal.purchase(id),
                  _ => ChatDeal.listing(query['listing'] ?? ''),
                },
              );
            },
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                ChatScreen(conversationId: state.pathParameters['id']),
          ),
        ],
      ),
      GoRoute(
        path: '/store/:id',
        builder: (context, state) =>
            StorefrontScreen(businessId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.myListings,
        builder: (context, state) => const MyListingsScreen(),
      ),
      GoRoute(
        path: '/payments/:id',
        builder: (context, state) =>
            PaymentScreen(paymentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/listing/:id',
        builder: (context, state) =>
            ListingDetailScreen(listingId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) =>
                ListingFormScreen(listingId: state.pathParameters['id']),
          ),
          GoRoute(
            path: 'payment',
            builder: (context, state) => ListingPaymentScreen(
              listingId: state.pathParameters['id']!,
              publish: state.uri.queryParameters['publish'] == '1',
            ),
          ),
          GoRoute(
            path: 'report',
            builder: (context, state) =>
                ReportListingScreen(listingId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'order',
            builder: (context, state) => OrderScreen(
              listingId: state.pathParameters['id']!,
              campaignId: state.uri.queryParameters['campaign'],
            ),
          ),
        ],
      ),
      // Business application (M2): track status > apply > documents.
      GoRoute(
        path: AppRoutes.business,
        builder: (context, state) => const BusinessApplicationScreen(),
        routes: [
          GoRoute(
            path: 'store',
            builder: (context, state) => const ManageStoreScreen(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => const StorefrontEditScreen(),
              ),
              GoRoute(
                path: 'dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
              GoRoute(
                path: 'payment-details',
                builder: (context, state) => const PaymentDetailsScreen(),
              ),
              GoRoute(
                path: 'campaigns/new',
                builder: (context, state) => const CampaignFormScreen(),
              ),
              GoRoute(
                path: 'campaigns/:campaignId',
                builder: (context, state) => CampaignFormScreen(
                  campaignId: state.pathParameters['campaignId'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'apply',
            builder: (context, state) => const ApplicationFormScreen(),
            routes: [
              GoRoute(
                path: 'documents',
                builder: (context, state) => const ApplicationDocumentsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    state.dispose();
  });
  return router;
});
