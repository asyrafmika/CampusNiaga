import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/storage/preferences.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';
import 'package:mobile/features/auth/domain/auth_failure.dart';
import 'package:mobile/features/auth/domain/user_access.dart';
import 'package:mobile/features/business/application/data/business_application_repository.dart';
import 'package:mobile/features/business/application/data/document_picker.dart';
import 'package:mobile/features/business/store/data/store_repository.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/dashboard/data/dashboard_repository.dart';
import 'package:mobile/features/discovery/data/discovery_repository.dart';
import 'package:mobile/features/marketplace/data/listing_repository.dart';
import 'package:mobile/features/marketplace/data/reservation_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'business_fakes.dart';
import 'chat_fakes.dart';
import 'dashboard_fakes.dart';
import 'discovery_fakes.dart';
import 'marketplace_fakes.dart';
import 'store_fakes.dart';

const student = UserAccess(
  userId: 'u1',
  email: 'ali@student.usm.my',
  emailConfirmed: true,
  accountStatus: AccountStatus.active,
  isStudent: true,
  isReviewer: false,
  isAdmin: false,
);

/// Records calls instead of talking to Supabase.
class FakeAuthRepository implements AuthRepository {
  AuthFailure? failWith;
  final List<String> calls = [];

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith case final failure?) throw failure;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _record('signIn $email');

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) => _record('signUp $name $email');

  @override
  Future<void> sendPasswordReset(String email) => _record('reset $email');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs the whole app with access and auth replaced, so screens and
/// navigation can be tested without Supabase.
Future<FakeAuthRepository> pumpApp(
  WidgetTester tester,
  Future<UserAccess?> Function() lookup, {
  bool onboardingSeen = true,
  FakeListingRepository? listings,
  FakeReservationRepository? reservations,
  FakeBusinessApplicationRepository? applications,
  FakeDocumentPicker? documentPicker,
  FakeStoreRepository? store,
  FakeDiscoveryRepository? discovery,
  FakeDashboardRepository? dashboard,
  FakeChatRepository? chat,
}) async {
  // A Pixel 9-sized screen (the default test surface is 800x600).
  tester.view.physicalSize = const Size(1080, 2424);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({'onboarding_seen': onboardingSeen});
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWithValue(auth),
        userAccessProvider.overrideWith((ref) => lookup()),
        myNameProvider.overrideWith((ref) async => 'Ali Bin Abu'),
        listingRepositoryProvider.overrideWithValue(
          listings ?? FakeListingRepository(),
        ),
        reservationRepositoryProvider.overrideWithValue(
          reservations ?? FakeReservationRepository(),
        ),
        businessApplicationRepositoryProvider.overrideWithValue(
          applications ?? FakeBusinessApplicationRepository(),
        ),
        documentPickerProvider.overrideWithValue(
          documentPicker ?? FakeDocumentPicker(),
        ),
        storeRepositoryProvider.overrideWithValue(
          store ?? FakeStoreRepository(),
        ),
        discoveryRepositoryProvider.overrideWithValue(
          discovery ?? FakeDiscoveryRepository(),
        ),
        dashboardRepositoryProvider.overrideWithValue(
          dashboard ?? FakeDashboardRepository(),
        ),
        chatRepositoryProvider.overrideWithValue(
          chat ?? FakeChatRepository(chats: const []),
        ),
      ],
      child: const CampusNiagaApp(),
    ),
  );
  return auth;
}
