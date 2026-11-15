import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/listing_enums.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/state_views.dart';
import '../domain/listing_query.dart';
import 'marketplace_providers.dart';
import 'widgets/feed_footer.dart';
import 'widgets/listing_widgets.dart';

/// Search with filters (category, condition, price range) and sorting.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialCategory});

  final String? initialCategory;

  static const Key searchFieldKey = Key('search-field');

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _text = TextEditingController();
  late ListingQuery _query = ListingQuery(category: widget.initialCategory);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String value) => setState(() {
    final search = value.trim();
    _query = _query.copyWith(
      search: search,
      // Best match is only meaningful while searching for words.
      sort: search.isEmpty && _query.sort == ListingSort.relevance
          ? ListingSort.newest
          : search.isNotEmpty && _query.sort == ListingSort.newest
          ? ListingSort.relevance
          : _query.sort,
    );
  });

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<ListingQuery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FilterSheet(query: _query),
    );
    if (result != null) setState(() => _query = result);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider(_query));
    final filters = _query.activeFilterCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Search'),
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: SearchScreen.searchFieldKey,
                    controller: _text,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      hintText: 'What are you looking for?',
                      prefixIcon: const Icon(Icons.search_rounded),
                      fillColor: AppColors.surface,
                      suffixIcon: IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _text.clear();
                          _submit('');
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Badge(
                  isLabelVisible: filters > 0,
                  label: Text('$filters'),
                  backgroundColor: AppColors.accent,
                  child: IconButton.filled(
                    tooltip: 'Filters',
                    onPressed: _openFilters,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      fixedSize: const Size(56, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          _ActiveFilters(
            query: _query,
            onChanged: (q) => setState(() => _query = q),
          ),
          Expanded(
            child: switch (feed) {
              AsyncData(:final value) when value.items.isEmpty => EmptyView(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                message: _query.search.isEmpty && filters == 0
                    ? 'Nothing is for sale right now.'
                    : 'Try other words or fewer filters.',
              ),
              AsyncData(:final value) => RefreshIndicator(
                onRefresh: () => ref.refresh(feedProvider(_query).future),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 600) {
                      ref.read(feedProvider(_query).notifier).loadMore();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        sliver: ListingGrid(
                          listings: value.items,
                          onOpen: (l) => context.push(AppRoutes.listing(l.id)),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: FeedFooter(
                          state: value,
                          onRetry: () => ref
                              .read(feedProvider(_query).notifier)
                              .loadMore(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AsyncError(:final error) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(feedProvider(_query)),
              ),
              _ => const LoadingView(),
            },
          ),
        ],
      ),
    );
  }
}

/// Chips for the filters in use; tapping one removes it.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.onChanged});

  final ListingQuery query;
  final ValueChanged<ListingQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (query.category case final category?)
        _chip(category, () => onChanged(query.copyWith(category: () => null))),
      if (query.condition case final condition?)
        _chip(
          condition.label,
          () => onChanged(query.copyWith(condition: () => null)),
        ),
      if (query.minPriceSen case final min?)
        _chip(
          'From ${formatRm(min)}',
          () => onChanged(query.copyWith(minPriceSen: () => null)),
        ),
      if (query.maxPriceSen case final max?)
        _chip(
          'Up to ${formatRm(max)}',
          () => onChanged(query.copyWith(maxPriceSen: () => null)),
        ),
      if (query.sort != ListingSort.newest)
        _chip(
          query.sort.label,
          () => onChanged(query.copyWith(sort: ListingSort.newest)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => InputChip(
    label: Text(label),
    onDeleted: onRemove,
    backgroundColor: AppColors.primarySoft,
    side: BorderSide.none,
    labelStyle: const TextStyle(
      color: AppColors.primaryDark,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.query});

  final ListingQuery query;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late String? _category = widget.query.category;
  late ListingCondition? _condition = widget.query.condition;
  late ListingSort _sort = widget.query.sort;
  late final _min = TextEditingController(
    text: widget.query.minPriceSen == null
        ? ''
        : senToInput(widget.query.minPriceSen!),
  );
  late final _max = TextEditingController(
    text: widget.query.maxPriceSen == null
        ? ''
        : senToInput(widget.query.maxPriceSen!),
  );
  String? _priceError;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    int? read(TextEditingController c) =>
        c.text.trim().isEmpty ? null : parseRmToSen(c.text);
    final min = read(_min);
    final max = read(_max);
    final badMin = _min.text.trim().isNotEmpty && min == null;
    final badMax = _max.text.trim().isNotEmpty && max == null;
    if (badMin || badMax) {
      setState(() => _priceError = 'Enter prices like 10 or 12.50.');
      return;
    }
    if (min != null && max != null && min > max) {
      setState(() => _priceError = 'The minimum is above the maximum.');
      return;
    }
    Navigator.of(context).pop(
      widget.query.copyWith(
        category: () => _category,
        condition: () => _condition,
        minPriceSen: () => min,
        maxPriceSen: () => max,
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final sorts = widget.query.search.isEmpty
        ? ListingSort.values.where((s) => s != ListingSort.relevance)
        : ListingSort.values;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filters', style: theme.textTheme.titleLarge),
            label('Category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (on) =>
                        setState(() => _category = on ? c : null),
                  ),
              ],
            ),
            label('Condition'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in ListingCondition.values)
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _condition == c,
                    onSelected: (on) =>
                        setState(() => _condition = on ? c : null),
                  ),
              ],
            ),
            label('Price (RM)'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(hintText: 'Min'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('–'),
                ),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(hintText: 'Max'),
                  ),
                ),
              ],
            ),
            if (_priceError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            label('Sort by'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in sorts)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _sort == s,
                    onSelected: (_) => setState(() => _sort = s),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _category = null;
                      _condition = null;
                      _min.clear();
                      _max.clear();
                      _priceError = null;
                      _sort = widget.query.search.isEmpty
                          ? ListingSort.newest
                          : ListingSort.relevance;
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Show results'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
