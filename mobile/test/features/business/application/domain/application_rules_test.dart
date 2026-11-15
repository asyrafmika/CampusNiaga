import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';

import '../../../../support/business_fakes.dart';

void main() {
  group('the state machine, as the app sees it', () {
    test('the applicant edits only a draft or after a request for changes', () {
      final editable = {
        for (final s in ApplicationStatus.values)
          s: ApplicationRules.canEdit(s),
      };
      expect(editable, {
        ApplicationStatus.draft: true,
        ApplicationStatus.submitted: false,
        ApplicationStatus.underReview: false,
        ApplicationStatus.infoRequested: true,
        ApplicationStatus.approved: false,
        ApplicationStatus.rejected: false,
      });
    });

    test('only approved and rejected are final', () {
      expect(ApplicationStatus.values.where(ApplicationRules.isFinal), [
        ApplicationStatus.approved,
        ApplicationStatus.rejected,
      ]);
    });

    test('submitted and under review are with the reviewer', () {
      expect(ApplicationStatus.values.where(ApplicationRules.isWithReviewer), [
        ApplicationStatus.submitted,
        ApplicationStatus.underReview,
      ]);
    });

    test('status values match the data dictionary', () {
      expect(ApplicationStatus.values.map((s) => s.wireName), [
        'draft',
        'submitted',
        'under_review',
        'info_requested',
        'approved',
        'rejected',
      ]);
      expect(
        ApplicationStatus.fromWire('info_requested'),
        ApplicationStatus.infoRequested,
      );
      expect(
        () => ApplicationStatus.fromWire('pending'),
        throwsFormatException,
      );
      expect(BusinessStatus.fromWire('suspended'), BusinessStatus.suspended);
      expect(() => BusinessStatus.fromWire('closed'), throwsFormatException);
      expect(ApplicationActor.fromWire('reviewer'), ApplicationActor.reviewer);
    });
  });

  group('field checks mirror submit_business_application', () {
    test('business name: 3 to 80 characters after trimming', () {
      expect(ApplicationRules.businessName('  AB  '), isNotNull);
      expect(ApplicationRules.businessName('ABC'), isNull);
      expect(ApplicationRules.businessName('x' * 80), isNull);
      expect(ApplicationRules.businessName('x' * 81), isNotNull);
    });

    test('description: 20 to 1,000 characters', () {
      expect(ApplicationRules.description('x' * 19), isNotNull);
      expect(ApplicationRules.description('x' * 20), isNull);
      expect(ApplicationRules.description('x' * 1001), isNotNull);
    });

    test('contact and collection: 5 to 200 characters', () {
      for (final rule in [
        ApplicationRules.contactDetails,
        ApplicationRules.collectionDetails,
      ]) {
        expect(rule('1234'), isNotNull);
        expect(rule('12345'), isNull);
        expect(rule('x' * 201), isNotNull);
      }
    });

    test('a category is required to submit', () {
      expect(ApplicationRules.category(null), isNotNull);
      expect(ApplicationRules.category(' '), isNotNull);
      expect(ApplicationRules.category('Books'), isNull);
    });

    test('the reply is optional, up to 500 characters', () {
      expect(ApplicationRules.responseNote(null), isNull);
      expect(ApplicationRules.responseNote('x' * 500), isNull);
      expect(ApplicationRules.responseNote('x' * 501), isNotNull);
    });

    test('a draft only has length limits', () {
      expect(ApplicationRules.draftLength('', 80), isNull);
      expect(ApplicationRules.draftLength('x' * 81, 80), isNotNull);
    });

    test('submitProblem finds the first missing field', () {
      expect(ApplicationRules.submitProblem(completeContent), isNull);
      expect(
        ApplicationRules.submitProblem(ApplicationContent.empty),
        isNotNull,
      );
      const noCollection = ApplicationContent(
        businessName: 'Ali Bakes',
        category: 'Others',
        description: 'Homemade brownies and cookies, every week.',
        contactDetails: '012-3456789',
        collectionDetails: '',
      );
      expect(
        ApplicationRules.submitProblem(noCollection),
        ApplicationRules.collectionDetails(''),
      );
    });
  });

  group('documents', () {
    test('PDF, JPEG and PNG are allowed, in any case', () {
      expect(ApplicationRules.documentExtension('Menu.PDF'), 'pdf');
      expect(ApplicationRules.documentExtension('photo.jpeg'), 'jpeg');
      expect(ApplicationRules.documentExtension('scan.png'), 'png');
      expect(ApplicationRules.documentExtension('notes.docx'), isNull);
      expect(ApplicationRules.documentExtension('no-extension'), isNull);
    });

    test('the upload content type follows the extension', () {
      expect(aDocument('a.pdf').contentType, 'application/pdf');
      expect(aDocument('a.png').contentType, 'image/png');
      expect(aDocument('a.JPG').contentType, 'image/jpeg');
    });

    test('file names are made safe for Storage paths', () {
      expect(
        ApplicationRules.safeFileName('Food handling cert (2026).PDF'),
        'Food_handling_cert_2026.pdf',
      );
      expect(
        ApplicationRules.safeFileName('../../etc/passwd.png'),
        'etc_passwd.png',
      );
      expect(ApplicationRules.safeFileName('مينو.pdf'), 'document.pdf');
      expect(
        ApplicationRules.safeFileName('${'a' * 100}.jpg'),
        '${'a' * 60}.jpg',
      );
    });

    test('a stored path shows the original-ish name', () {
      expect(
        ApplicationRules.documentName('u1/a1/1731744000000_Menu_2026.pdf'),
        'Menu_2026.pdf',
      );
      expect(ApplicationRules.documentName('u1/a1/menu.pdf'), 'menu.pdf');
    });
  });
}
