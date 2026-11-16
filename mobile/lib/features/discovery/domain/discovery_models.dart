/// A product request as the requests list shows it (`list_product_requests`).
/// Nobody's identity is included: only counts and the caller's own flags.
class ProductRequest {
  const ProductRequest({
    required this.id,
    required this.name,
    required this.category,
    required this.campusArea,
    required this.isActive,
    required this.clusterKey,
    required this.createdAt,
    required this.interestCount,
    required this.iAmInterested,
    required this.isMine,
    this.preferredPriceSen,
    this.notes,
  });

  final String id;
  final String name;
  final String category;
  final int? preferredPriceSen;
  final String campusArea;
  final String? notes;
  final bool isActive;
  final String clusterKey;
  final DateTime createdAt;

  /// Students who tapped Interested (the creator is counted separately).
  final int interestCount;
  final bool iAmInterested;
  final bool isMine;

  /// Students behind this request: its creator plus the interested ones.
  int get studentCount => interestCount + 1;

  ProductRequest withInterest({required bool interested, required int count}) =>
      ProductRequest(
        id: id,
        name: name,
        category: category,
        preferredPriceSen: preferredPriceSen,
        campusArea: campusArea,
        notes: notes,
        isActive: isActive,
        clusterKey: clusterKey,
        createdAt: createdAt,
        interestCount: count,
        iAmInterested: interested,
        isMine: isMine,
      );
}

/// The fields of the request form.
class RequestInput {
  const RequestInput({
    required this.name,
    required this.category,
    required this.campusArea,
    this.preferredPriceSen,
    this.notes,
  });

  final String name;
  final String category;
  final String campusArea;
  final int? preferredPriceSen;
  final String? notes;
}

/// One ranked cluster of similar requests (`opportunities`). A possible
/// opportunity, not a confirmed demand: interest is not a purchase.
class Opportunity {
  const Opportunity({
    required this.clusterKey,
    required this.category,
    required this.headTerm,
    required this.keywords,
    required this.requestCount,
    required this.uniqueInterestCount,
    required this.activeSupplyCount,
    required this.distinctSellerCount,
    required this.priceGap,
    required this.score,
    required this.reasons,
    required this.insufficientData,
    required this.algoVersion,
    required this.calculatedAt,
    this.medianListedPriceSen,
    this.medianPreferredPriceSen,
  });

  final String clusterKey;
  final String category;

  /// The main word all its requests share, e.g. "brownie".
  final String headTerm;
  final List<String> keywords;
  final int requestCount;

  /// D: distinct students who asked or are interested.
  final int uniqueInterestCount;

  /// S: matching listings for sale now.
  final int activeSupplyCount;
  final int distinctSellerCount;
  final int? medianListedPriceSen;
  final int? medianPreferredPriceSen;
  final bool priceGap;
  final int score;

  /// The database's explanation, built from the same numbers.
  final List<String> reasons;
  final bool insufficientData;
  final String algoVersion;
  final DateTime calculatedAt;

  /// "Brownie" from "brownie".
  String get title => headTerm.isEmpty
      ? headTerm
      : '${headTerm[0].toUpperCase()}${headTerm.substring(1)}';
}

/// Form checks mirroring `create_product_request`. The database checks again,
/// including that the name has a real product word.
abstract final class RequestRules {
  static String? name(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 3) return 'Name the product (3 characters or more).';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  static String? campusArea(String? value) {
    final length = (value ?? '').trim().length;
    if (length < 2) return 'Where on campus?';
    if (length > 80) return 'Keep it under 80 characters.';
    return null;
  }

  static String? notes(String? value) => (value ?? '').trim().length > 300
      ? 'Keep it under 300 characters.'
      : null;
}
