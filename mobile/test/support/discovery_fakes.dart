import 'package:mobile/core/domain/app_failure.dart';
import 'package:mobile/features/discovery/data/discovery_repository.dart';
import 'package:mobile/features/discovery/domain/discovery_models.dart';

const String brownieKey = 'Food & Beverage|brownie';

ProductRequest aRequest({
  String id = 'r1',
  String name = 'Chocolate brownie',
  bool mine = false,
  bool interested = false,
  int interestCount = 1,
  bool active = true,
}) => ProductRequest(
  id: id,
  name: name,
  category: 'Food & Beverage',
  preferredPriceSen: 500,
  campusArea: 'Desasiswa Tekun',
  notes: 'Fudgy please',
  isActive: active,
  clusterKey: brownieKey,
  createdAt: DateTime.utc(2026, 11, 16),
  interestCount: interestCount,
  iAmInterested: interested,
  isMine: mine,
);

Opportunity anOpportunity({
  String key = brownieKey,
  String head = 'brownie',
  int score = 22,
  bool insufficient = false,
}) => Opportunity(
  clusterKey: key,
  category: 'Food & Beverage',
  headTerm: head,
  keywords: const ['brownie', 'chocolate'],
  requestCount: 3,
  uniqueInterestCount: insufficient ? 1 : 4,
  activeSupplyCount: 1,
  distinctSellerCount: 1,
  medianListedPriceSen: 900,
  medianPreferredPriceSen: 500,
  priceGap: true,
  score: score,
  reasons: [
    if (insufficient) '1 student interested' else '4 students interested',
    '1 active matching listing from 1 seller',
    'Listings (median RM 9) are above requested prices (median RM 5)',
    if (insufficient) 'Insufficient data: fewer than 2 interested students',
  ],
  insufficientData: insufficient,
  algoVersion: 'm4-v1',
  calculatedAt: DateTime.utc(2026, 11, 16),
);

/// In-memory requests and opportunities; records every call.
class FakeDiscoveryRepository implements DiscoveryRepository {
  FakeDiscoveryRepository({
    List<ProductRequest>? requests,
    List<ProductRequest>? mine,
    List<Opportunity>? opportunities,
  }) : all = requests ?? [aRequest(), aRequest(id: 'r2', name: 'Brownies')],
       mineList = mine ?? [],
       ranked = opportunities ?? [anOpportunity()];

  List<ProductRequest> all;
  List<ProductRequest> mineList;
  List<Opportunity> ranked;
  final List<String> calls = [];
  AppFailure? failWith;

  void _check() {
    if (failWith case final f?) throw f;
  }

  @override
  Future<List<ProductRequest>> requests({
    String? category,
    String? clusterKey,
    bool mine = false,
    int offset = 0,
  }) async {
    _check();
    if (mine) return mineList;
    return clusterKey == null
        ? all
        : all.where((r) => r.clusterKey == clusterKey).toList();
  }

  @override
  Future<String> createRequest(RequestInput input) async {
    calls.add(
      'create ${input.name.trim()} ${input.category} '
      '${input.preferredPriceSen} ${input.campusArea.trim()}',
    );
    _check();
    return 'r9';
  }

  @override
  Future<void> closeRequest(String requestId) async {
    calls.add('close $requestId');
    _check();
  }

  @override
  Future<({bool interested, int count})> toggleInterest(
    String requestId,
  ) async {
    calls.add('toggle $requestId');
    _check();
    final request = all.firstWhere((r) => r.id == requestId);
    final interested = !request.iAmInterested;
    final count = request.interestCount + (interested ? 1 : -1);
    all = [
      for (final r in all)
        r.id == requestId
            ? r.withInterest(interested: interested, count: count)
            : r,
    ];
    return (interested: interested, count: count);
  }

  @override
  Future<List<Opportunity>> opportunities({int offset = 0}) async {
    _check();
    return ranked;
  }

  @override
  Future<Opportunity?> opportunity(String clusterKey) async {
    _check();
    return ranked.where((o) => o.clusterKey == clusterKey).firstOrNull;
  }
}
