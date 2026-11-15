import '../../../core/domain/listing_enums.dart';

enum ListingSort {
  newest('newest', 'Newest'),
  priceAsc('price_asc', 'Price: low to high'),
  priceDesc('price_desc', 'Price: high to low'),
  relevance('relevance', 'Best match');

  const ListingSort(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// What the feed is filtered by. Used as a provider key, so it has value
/// equality.
class ListingQuery {
  const ListingQuery({
    this.search = '',
    this.category,
    this.condition,
    this.minPriceSen,
    this.maxPriceSen,
    this.sort = ListingSort.newest,
  });

  final String search;
  final String? category;
  final ListingCondition? condition;
  final int? minPriceSen;
  final int? maxPriceSen;
  final ListingSort sort;

  /// Filters other than the search text, for the "Filters (2)" badge.
  int get activeFilterCount => [
    category,
    condition,
    minPriceSen,
    maxPriceSen,
  ].where((f) => f != null).length;

  ListingQuery copyWith({
    String? search,
    ListingSort? sort,
    String? Function()? category,
    ListingCondition? Function()? condition,
    int? Function()? minPriceSen,
    int? Function()? maxPriceSen,
  }) => ListingQuery(
    search: search ?? this.search,
    sort: sort ?? this.sort,
    category: category != null ? category() : this.category,
    condition: condition != null ? condition() : this.condition,
    minPriceSen: minPriceSen != null ? minPriceSen() : this.minPriceSen,
    maxPriceSen: maxPriceSen != null ? maxPriceSen() : this.maxPriceSen,
  );

  ListingQuery clearFilters() => ListingQuery(search: search, sort: sort);

  @override
  bool operator ==(Object other) =>
      other is ListingQuery &&
      other.search == search &&
      other.category == category &&
      other.condition == condition &&
      other.minPriceSen == minPriceSen &&
      other.maxPriceSen == maxPriceSen &&
      other.sort == sort;

  @override
  int get hashCode =>
      Object.hash(search, category, condition, minPriceSen, maxPriceSen, sort);
}
