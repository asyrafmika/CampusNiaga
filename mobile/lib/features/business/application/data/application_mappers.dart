import '../../../../core/domain/business_enums.dart';
import '../domain/business_application.dart';

/// Maps rows from `business_applications`, `application_status_history` and
/// the `get_my_business()` result into domain models. Unknown status values
/// throw [FormatException], so a schema change is noticed instead of misread.

DateTime _time(Object? value) => DateTime.parse(value! as String);

DateTime? _timeOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

BusinessApplication applicationFromRow(Map<String, dynamic> row) =>
    BusinessApplication(
      id: row['id'] as String,
      content: ApplicationContent(
        businessName: row['business_name'] as String? ?? '',
        category: row['category'] as String? ?? '',
        description: row['description'] as String? ?? '',
        contactDetails: row['contact_details'] as String? ?? '',
        collectionDetails: row['collection_details'] as String? ?? '',
      ),
      documentPaths: (row['document_paths'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      status: ApplicationStatus.fromWire(row['status']),
      remarks: row['remarks'] as String?,
      createdAt: _time(row['created_at']),
      submittedAt: _timeOrNull(row['submitted_at']),
      decidedAt: _timeOrNull(row['decided_at']),
    );

/// The content columns the applicant may write.
Map<String, Object> contentToRow(ApplicationContent content) {
  final c = content.trimmed();
  return {
    'business_name': c.businessName,
    'category': c.category,
    'description': c.description,
    'contact_details': c.contactDetails,
    'collection_details': c.collectionDetails,
  };
}

ApplicationHistoryEntry historyFromRow(Map<String, dynamic> row) =>
    ApplicationHistoryEntry(
      from: ApplicationStatus.fromWire(row['from_status']),
      to: ApplicationStatus.fromWire(row['to_status']),
      actor: ApplicationActor.fromWire(row['actor_role']),
      note: row['note'] as String?,
      createdAt: _time(row['created_at']),
    );

MyBusiness businessFromJson(Object? json) {
  if (json case {
    'business_id': final String id,
    'name': final String name,
    'description': final String description,
    'pickup_details': final String pickupDetails,
    'status': final String status,
  }) {
    return MyBusiness(
      id: id,
      name: name,
      description: description,
      pickupDetails: pickupDetails,
      status: BusinessStatus.fromWire(status),
    );
  }
  throw FormatException('Unexpected get_my_business response: $json');
}
