import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/business/application/data/application_mappers.dart';
import 'package:mobile/features/business/application/domain/business_application.dart';

Map<String, dynamic> applicationRow({String status = 'info_requested'}) => {
  'id': 'a1',
  'business_name': 'Ali Bakes',
  'category': 'Food & Beverage',
  'description': 'Homemade brownies.',
  'contact_details': '012-3456789',
  'collection_details': 'Tekun lobby',
  'document_paths': ['u1/a1/1_menu.pdf'],
  'status': status,
  'remarks': 'Add your price list.',
  'submitted_at': '2026-11-16T09:00:00+00:00',
  'decided_at': null,
  'created_at': '2026-11-16T08:00:00+00:00',
};

void main() {
  test('reads a business_applications row', () {
    final a = applicationFromRow(applicationRow());
    expect(a.id, 'a1');
    expect(a.content.businessName, 'Ali Bakes');
    expect(a.content.collectionDetails, 'Tekun lobby');
    expect(a.documentPaths, ['u1/a1/1_menu.pdf']);
    expect(a.status, ApplicationStatus.infoRequested);
    expect(a.remarks, 'Add your price list.');
    expect(a.submittedAt, DateTime.utc(2026, 11, 16, 9));
    expect(a.decidedAt, isNull);
    expect(a.canEdit, isTrue);
  });

  test('an unknown application status is an error, not a guess', () {
    expect(
      () => applicationFromRow(applicationRow(status: 'pending')),
      throwsFormatException,
    );
  });

  test('writes only the trimmed content columns', () {
    const content = ApplicationContent(
      businessName: ' Ali Bakes ',
      category: 'Others',
      description: ' Brownies ',
      contactDetails: '012',
      collectionDetails: ' Tekun ',
    );
    expect(contentToRow(content), {
      'business_name': 'Ali Bakes',
      'category': 'Others',
      'description': 'Brownies',
      'contact_details': '012',
      'collection_details': 'Tekun',
    });
  });

  test('reads a history row', () {
    final entry = historyFromRow({
      'from_status': 'under_review',
      'to_status': 'info_requested',
      'actor_role': 'reviewer',
      'note': 'Add your price list.',
      'created_at': '2026-11-16T10:00:00+00:00',
    });
    expect(entry.from, ApplicationStatus.underReview);
    expect(entry.to, ApplicationStatus.infoRequested);
    expect(entry.actor, ApplicationActor.reviewer);
    expect(entry.note, 'Add your price list.');
  });

  test('reads get_my_business, and rejects a malformed one', () {
    final business = businessFromJson({
      'business_id': 'b1',
      'application_id': 'a1',
      'name': 'Ali Bakes',
      'description': 'Brownies',
      'pickup_details': 'Tekun lobby',
      'status': 'suspended',
      'created_at': '2026-11-17T00:00:00+00:00',
    });
    expect(business.name, 'Ali Bakes');
    expect(business.status, BusinessStatus.suspended);
    expect(() => businessFromJson({'name': 'x'}), throwsFormatException);
  });
}
