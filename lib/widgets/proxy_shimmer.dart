import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_theme.dart';

class ProxyShimmer extends StatelessWidget {
  final int itemCount;

  const ProxyShimmer({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return _staticSkeleton();
    }
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceCard,
      highlightColor: AppColors.surfaceElevated,
      period: const Duration(milliseconds: 1500),
      child: _staticSkeleton(),
    );
  }

  Widget _staticSkeleton() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(itemCount, (_) => _tile()),
      ],
    );
  }

  Widget _tile() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 160,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 110,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
