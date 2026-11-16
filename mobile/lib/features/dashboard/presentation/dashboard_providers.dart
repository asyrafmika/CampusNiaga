import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_models.dart';

/// The business's figures for one period, worked out from the phone's clock
/// when the period is chosen.
final dashboardProvider = FutureProvider.autoDispose
    .family<BusinessDashboard, DashboardPeriod>((ref, period) {
      final range = period.rangeAt(DateTime.now());
      return ref
          .watch(dashboardRepositoryProvider)
          .fetch(from: range.from, to: range.to);
    });
