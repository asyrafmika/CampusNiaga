import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/discovery_repository.dart';
import '../domain/discovery_models.dart';

/// Which requests a list shows: all active ones, one cluster's, or mine.
typedef RequestFilter = ({String? clusterKey, bool mine});

const RequestFilter allRequests = (clusterKey: null, mine: false);
const RequestFilter myRequests = (clusterKey: null, mine: true);

/// The top-ranked opportunities (the first page).
final opportunitiesProvider = FutureProvider.autoDispose<List<Opportunity>>(
  (ref) => ref.watch(discoveryRepositoryProvider).opportunities(),
);

final opportunityProvider = FutureProvider.autoDispose
    .family<Opportunity?, String>(
      (ref, clusterKey) =>
          ref.watch(discoveryRepositoryProvider).opportunity(clusterKey),
    );

final requestsProvider = FutureProvider.autoDispose
    .family<List<ProductRequest>, RequestFilter>(
      (ref, filter) => ref
          .watch(discoveryRepositoryProvider)
          .requests(clusterKey: filter.clusterKey, mine: filter.mine),
    );

/// Every change a student makes in Discover. Each method calls the
/// database (which recomputes the ranking), then refreshes the screens.
class DiscoveryActions {
  DiscoveryActions(this._ref);

  final Ref _ref;

  DiscoveryRepository get _repository => _ref.read(discoveryRepositoryProvider);

  Future<void> createRequest(RequestInput input) async {
    await _repository.createRequest(input);
    _refresh();
  }

  Future<void> closeRequest(String requestId) async {
    await _repository.closeRequest(requestId);
    _refresh();
  }

  /// Returns whether the student is now interested, and the new count.
  Future<({bool interested, int count})> toggleInterest(
    String requestId,
  ) async {
    final result = await _repository.toggleInterest(requestId);
    _refresh();
    return result;
  }

  void _refresh() {
    _ref
      ..invalidate(requestsProvider)
      ..invalidate(opportunitiesProvider)
      ..invalidate(opportunityProvider);
  }
}

final discoveryActionsProvider = Provider<DiscoveryActions>(
  DiscoveryActions.new,
);
