import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/domain/account_status.dart';
import 'package:mobile/core/domain/business_enums.dart';
import 'package:mobile/features/auth/data/user_access_mapper.dart';

Map<String, Object?> response({Object? accountStatus = 'active'}) => {
  'user_id': '83e3d28a-1676-4ccf-b874-4377a9b14f85',
  'email': 'ali@student.usm.my',
  'email_confirmed': true,
  'account_status': accountStatus,
  'is_student': true,
  'is_admin': true,
};

void main() {
  test('parses a get_my_access response', () {
    final access = userAccessFromJson(response());

    expect(access.userId, '83e3d28a-1676-4ccf-b874-4377a9b14f85');
    expect(access.email, 'ali@student.usm.my');
    expect(access.emailConfirmed, isTrue);
    expect(access.accountStatus, AccountStatus.active);
    expect(access.isStudent, isTrue);
    expect(access.isAdmin, isTrue);
  });

  test('reads a suspended account', () {
    expect(
      userAccessFromJson(response(accountStatus: 'suspended')).isSuspended,
      isTrue,
    );
  });

  test('rejects an unknown account status', () {
    expect(
      () => userAccessFromJson(response(accountStatus: 'banned')),
      throwsFormatException,
    );
  });

  test('rejects a response with a missing or mistyped field', () {
    expect(
      () => userAccessFromJson({...response(), 'is_student': 'yes'}),
      throwsFormatException,
    );
    expect(
      () => userAccessFromJson({...response()}..remove('email')),
      throwsFormatException,
    );
    expect(() => userAccessFromJson(null), throwsFormatException);
  });

  test('reads the business fields (Phase 3)', () {
    final owner = userAccessFromJson({
      ...response(),
      'is_business_owner': true,
      'business_status': 'approved',
    });
    expect(owner.isBusinessOwner, isTrue);
    expect(owner.businessStatus, BusinessStatus.approved);

    final suspended = userAccessFromJson({
      ...response(),
      'is_business_owner': false,
      'business_status': 'suspended',
    });
    expect(suspended.isBusinessOwner, isFalse);
    expect(suspended.businessStatus, BusinessStatus.suspended);
  });

  test('a response without business fields means no business', () {
    final access = userAccessFromJson(response());
    expect(access.isBusinessOwner, isFalse);
    expect(access.businessStatus, isNull);
  });

  test('rejects mistyped business fields', () {
    expect(
      () => userAccessFromJson({...response(), 'is_business_owner': 'yes'}),
      throwsFormatException,
    );
    expect(
      () => userAccessFromJson({...response(), 'business_status': 'closed'}),
      throwsFormatException,
    );
  });
}
