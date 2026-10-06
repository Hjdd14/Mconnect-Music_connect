import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton list shown while a search is in flight.
///
/// The search page used to show a bare `CircularProgressIndicator`, which reads
/// as "nothing yet" rather than "results are coming"; `shimmer` was already a
/// declared dependency with zero usages in the repo.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surfaceContainerLow;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: ListView.builder(
        key: const Key('search-results-skeleton'),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: double.infinity, color: base),
                    const SizedBox(height: 8),
                    Container(height: 10, width: 140, color: base),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
