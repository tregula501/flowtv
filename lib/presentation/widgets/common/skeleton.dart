import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/themes/motion.dart';

/// Shimmer skeleton primitives shared across loading states.
///
/// These replace bare `CircularProgressIndicator`s with placeholders shaped like
/// the real content, so startup/refresh feels instant. Pure presentation — they
/// render behind existing `isLoading` guards and never read playback state.
///
/// Under reduced-motion the shimmer sweep is suppressed (a static grey block is
/// shown) so the screen is calm for users who opt out of animation.

/// A single rounded placeholder block. Use as a building brick for skeletons.
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.margin,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Wraps a tree of [ShimmerBox]es in a themed shimmer sweep. When reduced-motion
/// is active it returns the children without the animated sweep.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor:
          Color.lerp(scheme.surfaceContainerHighest, scheme.surface, 0.6) ??
              scheme.surface,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// A grid of channel-tile-shaped placeholders matching ChannelGrid's layout
/// (200px max extent, 1.2 aspect). Drop in behind the channel-list loading guard.
class SkeletonChannelGrid extends StatelessWidget {
  const SkeletonChannelGrid({super.key, this.itemCount = 12});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 1.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) =>
            const ShimmerBox(borderRadius: 12),
      ),
    );
  }
}

/// A list of row-shaped placeholders (leading square + two text bars) matching
/// the mobile channel list / channel-picker layout.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 8,
    this.leadingSize = 48,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final int itemCount;
  final double leadingSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) => Padding(
          padding: padding,
          child: Row(
            children: [
              ShimmerBox(
                width: leadingSize,
                height: leadingSize,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShimmerBox(
                      width: double.infinity,
                      height: 12,
                      margin: EdgeInsets.only(right: 48),
                    ),
                    SizedBox(height: 8),
                    ShimmerBox(width: 120, height: 10),
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

/// A fade-in shimmer placeholder sized to fill its parent — for use as a
/// `CachedNetworkImage` placeholder so logos shimmer instead of popping in.
class ShimmerLogoPlaceholder extends StatelessWidget {
  const ShimmerLogoPlaceholder({super.key, this.borderRadius = 8});

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ShimmerBox(borderRadius: borderRadius, width: double.infinity),
    );
  }
}
