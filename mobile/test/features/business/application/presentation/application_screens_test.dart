import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/auth/presentation/profile_screen.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';
import 'package:mobile/features/business/application/presentation/business_application_screen.dart';
import 'package:mobile/features/business/application/presentation/widgets/application_widgets.dart';

import '../../../../support/app_harness.dart';
import '../../../../support/business_fakes.dart';

/// The M2 applicant screens, driven through the real router with an
/// in-memory application.
void main() {
  Future<void> openBusiness(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileScreen.businessKey));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> fillDetails(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('application-name')),
      'Ali Bakes',
    );
    await tester.tap(find.byKey(const Key('application-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('application-description')),
      'Homemade brownies and cookies, baked fresh every week.',
    );
    await tester.enterText(
      find.byKey(const Key('application-contact')),
      '012-3456789',
    );
    await tester.enterText(
      find.byKey(const Key('application-collection')),
      'Desasiswa Tekun lobby, 6-8pm',
    );
  }

  testWidgets(
    'a student applies: details, a document, submit, then tracks it',
    (tester) async {
      final applications = FakeBusinessApplicationRepository();
      await pumpApp(
        tester,
        () async => student,
        applications: applications,
        documentPicker: FakeDocumentPicker(aDocument()),
      );
      await openBusiness(tester);

      expect(find.byKey(SimulatedReviewNotice.noticeKey), findsOneWidget);
      await tapVisible(tester, find.byKey(BusinessApplicationScreen.startKey));

      // Nothing is sent while the details are incomplete.
      await tapVisible(tester, find.byKey(const Key('application-next')));
      expect(find.text('Use at least 3 characters.'), findsOneWidget);
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(applications.calls, isEmpty);

      await fillDetails(tester);
      await tapVisible(tester, find.byKey(const Key('application-next')));
      expect(applications.calls, ['create Ali Bakes']);
      expect(find.text('Step 2 of 2 · Documents'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('documents-add')));
      expect(find.text('Food_certificate.pdf'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('documents-submit')));
      expect(applications.calls, [
        'create Ali Bakes',
        'upload Food certificate.pdf',
        'documents a2 1',
        'submit a2',
      ]);
      // Back on Track Status.
      expect(find.text('Waiting for an administrator'), findsOneWidget);
      expect(find.byKey(BusinessApplicationScreen.continueKey), findsNothing);
    },
  );

  testWidgets('a half-finished application can be saved as a draft', (
    tester,
  ) async {
    final applications = FakeBusinessApplicationRepository();
    await pumpApp(tester, () async => student, applications: applications);
    await openBusiness(tester);
    await tapVisible(tester, find.byKey(BusinessApplicationScreen.startKey));

    await tester.enterText(find.byKey(const Key('application-name')), 'Ali');
    await tapVisible(tester, find.byKey(const Key('application-save-draft')));

    expect(applications.calls, ['create Ali']);
    expect(find.text('Draft saved'), findsOneWidget);
    expect(find.text('Continue application'), findsOneWidget);
  });

  testWidgets(
    'Respond to Request: the administrator’s note, edits, and a resubmission',
    (tester) async {
      final applications = FakeBusinessApplicationRepository(
        application: anApplication(
          status: ApplicationStatus.infoRequested,
          remarks: 'Add your price list.',
        ),
        entries: [
          ApplicationHistoryEntry(
            from: ApplicationStatus.underReview,
            to: ApplicationStatus.infoRequested,
            actor: ApplicationActor.reviewer,
            note: 'Add your price list.',
            createdAt: DateTime.utc(2026, 11, 16, 10),
          ),
        ],
      );
      await pumpApp(tester, () async => student, applications: applications);
      await openBusiness(tester);

      expect(find.text('Changes requested'), findsWidgets);
      expect(find.text('What the administrator asked for'), findsOneWidget);
      expect(find.textContaining('Add your price list.'), findsWidgets);

      await tapVisible(
        tester,
        find.byKey(BusinessApplicationScreen.continueKey),
      );
      expect(find.text('What the administrator asked for'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('application-description')),
        'Brownies RM 3, cookies RM 1.50, baked fresh every week.',
      );
      await tapVisible(tester, find.byKey(const Key('application-next')));
      await tester.enterText(
        find.byKey(const Key('documents-reply')),
        'Price list added.',
      );
      await tapVisible(tester, find.byKey(const Key('documents-submit')));

      expect(applications.calls, [
        'save a1 Ali Bakes',
        'submit a1 Price list added.',
      ]);
      expect(find.text('Waiting for an administrator'), findsOneWidget);
    },
  );

  testWidgets(
    'a submitted application shows its timeline and can’t be edited',
    (tester) async {
      final applications = FakeBusinessApplicationRepository(
        application: anApplication(status: ApplicationStatus.underReview),
        entries: [
          ApplicationHistoryEntry(
            from: ApplicationStatus.draft,
            to: ApplicationStatus.submitted,
            actor: ApplicationActor.applicant,
            createdAt: DateTime.utc(2026, 11, 16, 9),
          ),
          ApplicationHistoryEntry(
            from: ApplicationStatus.submitted,
            to: ApplicationStatus.underReview,
            actor: ApplicationActor.reviewer,
            createdAt: DateTime.utc(2026, 11, 16, 10),
          ),
        ],
      );
      await pumpApp(tester, () async => student, applications: applications);
      await openBusiness(tester);

      expect(find.text('Being reviewed'), findsOneWidget);
      expect(find.byKey(BusinessApplicationScreen.continueKey), findsNothing);
      await tester.scrollUntilVisible(find.text('Review started'), 200);
      expect(find.text('Submitted'), findsWidgets);
      expect(find.text('Review started'), findsOneWidget);
    },
  );

  testWidgets('an approved applicant sees their business', (tester) async {
    final applications = FakeBusinessApplicationRepository(
      application: anApplication(status: ApplicationStatus.approved),
      business: const MyBusiness(
        id: 'b1',
        name: 'Ali Bakes',
        description: 'Brownies',
        pickupDetails: 'Tekun lobby',
        status: BusinessStatus.approved,
      ),
    );
    await pumpApp(tester, () async => student, applications: applications);
    await openBusiness(tester);

    expect(find.text('Approved'), findsWidgets);
    expect(find.text('Pickup: Tekun lobby'), findsOneWidget);
    expect(find.byKey(BusinessApplicationScreen.continueKey), findsNothing);
    expect(find.byKey(BusinessApplicationScreen.startKey), findsNothing);
  });

  testWidgets('a rejected applicant sees why and may apply again', (
    tester,
  ) async {
    final applications = FakeBusinessApplicationRepository(
      application: anApplication(
        status: ApplicationStatus.rejected,
        remarks: 'Printing needs a supplier agreement.',
      ),
    );
    await pumpApp(tester, () async => student, applications: applications);
    await openBusiness(tester);

    expect(find.text('Why it wasn’t approved'), findsOneWidget);
    await tapVisible(tester, find.byKey(BusinessApplicationScreen.startKey));
    // A fresh form, not the rejected application.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('application-name')))
          .controller
          ?.text,
      '',
    );
  });

  testWidgets('a refused submission shows the database’s reason', (
    tester,
  ) async {
    final applications = FakeBusinessApplicationRepository(
      application: anApplication(),
    );
    await pumpApp(tester, () async => student, applications: applications);
    await openBusiness(tester);
    await tapVisible(tester, find.byKey(BusinessApplicationScreen.continueKey));
    await tapVisible(tester, find.byKey(const Key('application-next')));

    applications.failWith = const AppFailure(
      AppFailureReason.alreadyExists,
      'You already have a business.',
    );
    await tapVisible(tester, find.byKey(const Key('documents-submit')));

    expect(find.text('You already have a business.'), findsOneWidget);
    expect(find.text('Step 2 of 2 · Documents'), findsOneWidget);
  });
}
