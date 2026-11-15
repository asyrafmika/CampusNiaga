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
import '../../features/marketplace/presentation/home_screen.dart';
import '../../features/marketplace/presentation/listing_detail_screen.dart';
import '../../features/marketplace/presentation/listing_form_screen.dart';
import '../../features/marketplace/presentation/my_listings_screen.dart';
import '../../features/marketplace/presentation/my_reservations_screen.dart';
import '../../features/marketplace/presentation/report_listing_screen.dart';
import '../../features/marketplace/presentation/search_screen.dart';
import '../../features/onboarding/presentation/onboarding_controller.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
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
                path: AppRoutes.reservations,
                builder: (context, state) => const MyReservationsScreen(),
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
        builder: (context, state) => const ListingFormScreen(),
      ),
      GoRoute(
        path: AppRoutes.myListings,
        builder: (context, state) => const MyListingsScreen(),
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
            path: 'report',
            builder: (context, state) =>
                ReportListingScreen(listingId: state.pathParameters['id']!),
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
