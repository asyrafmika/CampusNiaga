import 'package:flutter/material.dart';

import '../../../../core/widgets/state_views.dart';
import '../marketplace_providers.dart';

/// Below the grid: a spinner while the next page loads, or a retry button.
class FeedFooter extends StatelessWidget {
  const FeedFooter({super.key, required this.state, required this.onRetry});

  final FeedState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    if (state.loadMoreFailed) {
      return Center(
        child: TextButton(
          onPressed: onRetry,
          child: const Text('Couldn’t load more. Try again'),
        ),
      );
    }
    return const SizedBox(height: 32);
  }
}
