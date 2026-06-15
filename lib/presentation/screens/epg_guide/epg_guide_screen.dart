import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/themes/motion.dart';
import '../../../data/datasources/local/drift/app_database.dart' show Channel, EpgProgram;
import '../../providers/channel_provider.dart';
import '../../providers/epg_provider.dart';
import '../../providers/player_provider.dart';
import '../../../core/extensions/datetime_extensions.dart';
import '../../../core/extensions/epg_program_extensions.dart';
import '../../widgets/common/entrance.dart';
import '../../widgets/common/skeleton.dart';

class EpgGuideScreen extends ConsumerStatefulWidget {
  const EpgGuideScreen({super.key});

  @override
  ConsumerState<EpgGuideScreen> createState() => _EpgGuideScreenState();
}

class _EpgGuideScreenState extends ConsumerState<EpgGuideScreen> {
  late ScrollController _timeHeaderController;
  late ScrollController _programHorizontalController;
  late ScrollController _channelListController;
  late ScrollController _programGridController;
  late DateTime _startTime;
  bool _isSyncingVerticalScroll = false;
  bool _isSyncingHorizontalScroll = false;

  /// Live "now" reference, refreshed every minute so isLive highlighting and
  /// program progress bars stay accurate instead of going stale.
  late DateTime _now;
  Timer? _nowTicker;

  /// Guards the one-shot auto scroll-to-now after the first data load.
  bool _didInitialScroll = false;

  static const double _timeSlotWidth = AppConstants.epgTimeSlotWidth;
  static const double _channelColumnWidth = AppConstants.epgChannelColumnWidth;
  static const double _rowHeight = AppConstants.epgGridRowHeight;
  static const int _hoursToShow = AppConstants.epgHoursToShow;

  @override
  void initState() {
    super.initState();
    _timeHeaderController = ScrollController();
    _programHorizontalController = ScrollController();
    _channelListController = ScrollController();
    _programGridController = ScrollController();

    // Sync vertical scrolling between channel list and program grid
    _channelListController.addListener(_onChannelListScroll);
    _programGridController.addListener(_onProgramGridScroll);

    // Sync horizontal scrolling between time header and program grid
    _timeHeaderController.addListener(_onTimeHeaderScroll);
    _programHorizontalController.addListener(_onProgramHorizontalScroll);

    _now = DateTime.now();
    _startTime = _now.subtract(const Duration(hours: 1));
    _startTime = DateTime(
      _startTime.year,
      _startTime.month,
      _startTime.day,
      _startTime.hour,
    );

    // Tick the live "now" reference every minute so isLive highlighting, live
    // progress bars and the NOW line keep advancing instead of freezing at
    // first build. Cheap setState on a non-streaming screen.
    _nowTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  void _onChannelListScroll() {
    if (_isSyncingVerticalScroll) return;
    _isSyncingVerticalScroll = true;
    _programGridController.jumpTo(_channelListController.offset);
    _isSyncingVerticalScroll = false;
  }

  void _onProgramGridScroll() {
    if (_isSyncingVerticalScroll) return;
    _isSyncingVerticalScroll = true;
    _channelListController.jumpTo(_programGridController.offset);
    _isSyncingVerticalScroll = false;
  }

  void _onTimeHeaderScroll() {
    if (_isSyncingHorizontalScroll) return;
    _isSyncingHorizontalScroll = true;
    _programHorizontalController.jumpTo(_timeHeaderController.offset);
    _isSyncingHorizontalScroll = false;
  }

  void _onProgramHorizontalScroll() {
    if (_isSyncingHorizontalScroll) return;
    _isSyncingHorizontalScroll = true;
    _timeHeaderController.jumpTo(_programHorizontalController.offset);
    _isSyncingHorizontalScroll = false;
  }

  @override
  void dispose() {
    _nowTicker?.cancel();
    _channelListController.removeListener(_onChannelListScroll);
    _programGridController.removeListener(_onProgramGridScroll);
    _timeHeaderController.removeListener(_onTimeHeaderScroll);
    _programHorizontalController.removeListener(_onProgramHorizontalScroll);
    _timeHeaderController.dispose();
    _programHorizontalController.dispose();
    _channelListController.dispose();
    _programGridController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final channelsAsync = ref.watch(channelsProvider);
    final isLoading = ref.watch(epgLoadingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tvGuide),
        actions: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(epgManagerProvider).fetchEpg(),
              tooltip: l10n.refreshEpg,
            ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: _scrollToNow,
            tooltip: l10n.goToNow,
          ),
        ],
      ),
      body: SafeArea(
        child: channelsAsync.when(
          loading: () => _buildEpgSkeleton(),
          error: (_, _) => Center(child: Text(l10n.failedToLoadChannels)),
          data: (channels) => _buildEpgGrid(context, channels),
        ),
      ),
    );
  }

  Widget _buildEpgGrid(BuildContext context, List<Channel> channels) {
    final l10n = AppLocalizations.of(context)!;
    final endTime = _startTime.add(const Duration(hours: _hoursToShow));
    final epgDataAsync = ref.watch(
      epgGridDataProvider((from: _startTime, to: endTime)),
    );

    return epgDataAsync.when(
      loading: () => _buildEpgSkeleton(),
      error: (_, _) => Center(child: Text(l10n.failedToLoadGuide)),
      data: (epgData) => Column(
        children: [
          // Time header
          _buildTimeHeader(),

          // Channel rows
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel list (fixed width, synced vertical scroll)
                SizedBox(
                  width: _channelColumnWidth,
                  child: _buildChannelList(channels),
                ),

                // Vertical divider
                const VerticalDivider(width: 1),

                // Programs grid (horizontal + vertical scroll)
                Expanded(
                  child: _buildProgramsGrid(channels, epgData),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// EPG-shaped loading placeholder: a time-header bar plus channel rows, each
  /// row a logo + name block followed by staggered program blocks. Mirrors the
  /// real grid metrics so the transition into loaded content is seamless.
  Widget _buildEpgSkeleton() {
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time header bar.
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: ShimmerBox(width: double.infinity, height: 14),
          ),
          Expanded(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: 8,
              itemBuilder: (context, index) => const SizedBox(
                height: _rowHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      // Channel column: logo + name bar.
                      SizedBox(
                        width: _channelColumnWidth - 16,
                        child: Row(
                          children: [
                            ShimmerBox(width: 40, height: 40),
                            SizedBox(width: 8),
                            Expanded(child: ShimmerBox(height: 12)),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      // Program blocks of varying widths.
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: ShimmerBox(height: double.infinity),
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              flex: 3,
                              child: ShimmerBox(height: double.infinity),
                            ),
                            SizedBox(width: 4),
                            Expanded(
                              flex: 2,
                              child: ShimmerBox(height: double.infinity),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader() {
    final slots = <Widget>[];
    var time = _startTime;

    for (var i = 0; i < _hoursToShow * 2; i++) {
      slots.add(
        Container(
          width: _timeSlotWidth / 2,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          child: Text(
            time.timeString,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
      time = time.add(const Duration(minutes: 30));
    }

    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Empty space for channel column
          const SizedBox(width: _channelColumnWidth),
          const VerticalDivider(width: 1),
          // Time slots (synced with horizontal scroll)
          Expanded(
            child: SingleChildScrollView(
              controller: _timeHeaderController,
              scrollDirection: Axis.horizontal,
              child: Row(children: slots),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(List<Channel> channels) {
    return ListView.builder(
      controller: _channelListController,
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              if (channel.logoUrl != null)
                CachedNetworkImage(
                  imageUrl: channel.logoUrl!,
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Icon(Icons.tv, size: 40),
                )
              else
                const Icon(Icons.tv, size: 40),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgramsGrid(
    List<Channel> channels,
    Map<String, List<EpgProgram>> epgData,
  ) {
    // Once data is first available, center the timeline on "now".
    if (!_didInitialScroll && channels.isNotEmpty) {
      _didInitialScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToNow();
      });
    }

    // px-per-minute matches the program blocks (see _buildProgramBlock).
    const pixelsPerMinute = _timeSlotWidth / 60;
    final nowOffset =
        _now.difference(_startTime).inMinutes * pixelsPerMinute;
    final showNowLine = nowOffset >= 0 && nowOffset <= _timeSlotWidth * _hoursToShow;

    return SingleChildScrollView(
      controller: _programHorizontalController,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _timeSlotWidth * _hoursToShow,
        child: Stack(
          children: [
            ListView.builder(
              controller: _programGridController,
              itemCount: channels.length,
              itemBuilder: (context, index) {
                final channel = channels[index];
                final programs = epgData[channel.epgId] ?? [];
                return _buildProgramRow(channel, programs);
              },
            ),

            // Thin live "now" line spanning the full timeline height. Sibling
            // overlay above the rows — does not restructure the grid.
            if (showNowLine)
              Positioned(
                left: nowOffset,
                top: 0,
                bottom: 0,
                width: 2,
                child: IgnorePointer(
                  child: Container(
                    color: Theme.of(context).colorScheme.error,
                  ).livePulse(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgramRow(Channel channel, List<EpgProgram> programs) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Stack(
        children: programs.map((program) {
          return _buildProgramBlock(channel, program);
        }).toList(),
      ),
    );
  }

  Widget _buildProgramBlock(Channel channel, EpgProgram program) {
    final startOffset = program.startTime.difference(_startTime).inMinutes;
    final duration = program.durationMinutes;
    const pixelsPerMinute = _timeSlotWidth / 60;

    final left = startOffset * pixelsPerMinute;
    final width = duration * pixelsPerMinute;

    if (left + width < 0 || left > _timeSlotWidth * _hoursToShow) {
      return const SizedBox.shrink();
    }

    final isLive = program.isLive;

    return Positioned(
      left: left.clamp(0, double.infinity),
      width: width.clamp(70, double.infinity),
      top: 2,
      bottom: 2,
      child: GestureDetector(
        onTap: () => _onProgramTap(channel, program),
        child: Container(
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isLive
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isLive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isLive ? FontWeight.bold : null,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${program.startTime.timeString} - ${program.endTime.timeString}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
              if (isLive)
                LinearProgressIndicator(
                  value: program.progress,
                  minHeight: 2,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onProgramTap(Channel channel, EpgProgram program) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(program.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${program.startTime.timeString} - ${program.endTime.timeString}'),
            if (program.category != null)
              Chip(label: Text(program.category!)),
            if (program.description != null) ...[
              const SizedBox(height: 8),
              Text(program.description!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          if (program.isLive)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(currentChannelProvider.notifier).select(channel);
                ref.read(playerControllerProvider.notifier).playChannel(channel);
              },
              child: Text(l10n.watchNow),
            ),
        ],
      ),
    );
  }

  void _scrollToNow() {
    final now = DateTime.now();
    final offset = now.difference(_startTime).inMinutes * (_timeSlotWidth / 60);
    final targetOffset = (offset - 100).clamp(0.0, double.infinity);

    // Scroll both time header and program grid
    if (_timeHeaderController.hasClients) {
      _timeHeaderController.animateTo(
        targetOffset,
        duration: MotionTokens.emphasized,
        curve: MotionTokens.exit,
      );
    }
    if (_programHorizontalController.hasClients) {
      _programHorizontalController.animateTo(
        targetOffset,
        duration: MotionTokens.emphasized,
        curve: MotionTokens.exit,
      );
    }
  }
}
