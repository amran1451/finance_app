import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/analytics.dart';
import '../../state/analytics_providers.dart';
import '../../utils/color_hex.dart';
import '../../utils/formatting.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _controller ??= TabController(length: 2, vsync: this);
    final filters = ref.watch(analyticsFilterProvider);
    final rangeLabel = _formatRange(filters.from, filters.to);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика'),
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Плановые'),
            Tab(text: 'Внеплановые'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Экспортировать',
            onPressed: () => _exportCurrent(context),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnalyticsFilterBar(rangeLabel: rangeLabel),
          Expanded(
            child: TabBarView(
              controller: _controller,
              children: const [
                _AnalyticsTabContent(tab: AnalyticsTab.planned),
                _AnalyticsTabContent(tab: AnalyticsTab.unplanned),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCurrent(BuildContext context) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Экспорт аналитики будет доступен в будущих обновлениях'),
      ),
    );
  }

  String _formatRange(DateTime from, DateTime to) {
    final startLabel = '${from.day.toString().padLeft(2, '0')}.${from.month.toString().padLeft(2, '0')}.${from.year}';
    final endLabel = '${to.day.toString().padLeft(2, '0')}.${to.month.toString().padLeft(2, '0')}.${to.year}';
    if (startLabel == endLabel) {
      return startLabel;
    }
    return '$startLabel – $endLabel';
  }
}

class AnalyticsFilterBar extends ConsumerWidget {
  const AnalyticsFilterBar({super.key, required this.rangeLabel});

  final String rangeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(analyticsFilterProvider);
    final notifier = ref.read(analyticsFilterProvider.notifier);
    final media = MediaQuery.of(context);
    final textScale = media.textScaleFactor.clamp(0.9, 1.1).toDouble();

    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MediaQuery(
                  data: media.copyWith(textScaleFactor: textScale),
                  child: SegmentedButton<AnalyticsRangePreset>(
                    segments: const [
                      ButtonSegment(
                        value: AnalyticsRangePreset.currentHalf,
                        label: Text('Текущий полупериод'),
                      ),
                      ButtonSegment(
                        value: AnalyticsRangePreset.thisMonth,
                        label: Text('Этот месяц'),
                      ),
                      ButtonSegment(
                        value: AnalyticsRangePreset.lastMonth,
                        label: Text('Прошлый месяц'),
                      ),
                      ButtonSegment(
                        value: AnalyticsRangePreset.custom,
                        label: Text('Диапазон…'),
                      ),
                    ],
                    showSelectedIcon: false,
                    selected: {filters.preset},
                    onSelectionChanged: (selection) async {
                      if (selection.isEmpty) {
                        return;
                      }
                      final value = selection.first;
                      if (value == AnalyticsRangePreset.custom) {
                        notifier.setPreset(value);
                        await _pickCustomRange(context, ref);
                      } else {
                        notifier.setPreset(value);
                      }
                    },
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(rangeLabel),
                  onPressed: () => _pickCustomRange(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MediaQuery(
              data: media.copyWith(textScaleFactor: textScale),
              child: SegmentedButton<AnalyticsInterval>(
                segments: const [
                  ButtonSegment(
                    value: AnalyticsInterval.days,
                    label: Text('Дни'),
                  ),
                  ButtonSegment(
                    value: AnalyticsInterval.weekdays,
                    label: Text('Дни недели'),
                  ),
                  ButtonSegment(
                    value: AnalyticsInterval.months,
                    label: Text('Месяцы'),
                  ),
                  ButtonSegment(
                    value: AnalyticsInterval.halfPeriods,
                    label: Text('Полупериоды'),
                  ),
                ],
                showSelectedIcon: false,
                selected: {filters.interval},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) {
                    return;
                  }
                  notifier.setInterval(selection.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsTabContent extends ConsumerWidget {
  const _AnalyticsTabContent({required this.tab});

  final AnalyticsTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planned = tab == AnalyticsTab.planned;
    final primaryBreakdown = planned
        ? AnalyticsBreakdown.plannedCriticality
        : AnalyticsBreakdown.unplannedReason;
    final secondaryBreakdown = planned
        ? AnalyticsBreakdown.plannedCategory
        : AnalyticsBreakdown.unplannedCategory;
    final primaryProvider =
        analyticsPieProvider((breakdown: primaryBreakdown, tab: tab));
    final secondaryProvider =
        analyticsPieProvider((breakdown: secondaryBreakdown, tab: tab));
    final seriesProvider = analyticsSeriesProvider(tab);

    final primaryAsync = ref.watch(primaryProvider);
    final secondaryAsync = ref.watch(secondaryProvider);
    final seriesAsync = ref.watch(seriesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final charts = [
          _PieChartCard(
            title: planned ? 'По критичности' : 'По причинам',
            data: primaryAsync,
            onRetry: () => ref.refresh(primaryProvider),
          ),
          _PieChartCard(
            title: 'По категориям',
            data: secondaryAsync,
            onRetry: () => ref.refresh(secondaryProvider),
          ),
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: charts[0]),
                    const SizedBox(width: 16),
                    Expanded(child: charts[1]),
                  ],
                )
              else ...[
                charts[0],
                const SizedBox(height: 16),
                charts[1],
              ],
              const SizedBox(height: 16),
              _SeriesCard(
                data: seriesAsync,
                onRetry: () => ref.refresh(seriesProvider),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PieChartCard extends ConsumerWidget {
  const _PieChartCard({
    required this.title,
    required this.data,
    required this.onRetry,
  });

  final String title;
  final AsyncValue<List<AnalyticsPieSlice>> data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            data.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => SizedBox(
                height: 220,
                child: _AnalyticsErrorState(
                  message: 'Не удалось загрузить данные: $error',
                  onRetry: onRetry,
                ),
              ),
              data: (slices) {
                if (slices.isEmpty) {
                  return const SizedBox(
                    height: 220,
                    child: _AnalyticsEmptyState(),
                  );
                }
                return _AnalyticsPieChart(slices: slices);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesCard extends ConsumerWidget {
  const _SeriesCard({required this.data, required this.onRetry});

  final AsyncValue<List<AnalyticsTimePoint>> data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final interval = ref.watch(analyticsFilterProvider.select((value) => value.interval));
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Динамика расходов', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => _AnalyticsErrorState(
                  message: 'Не удалось загрузить динамику: $error',
                  onRetry: onRetry,
                ),
                data: (series) {
                  if (series.isEmpty) {
                    return const _AnalyticsEmptyState();
                  }
                  return _AnalyticsSeriesChart(series: series, interval: interval);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsEmptyState extends ConsumerWidget {
  const _AnalyticsEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insights_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('Нет данных за период'),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _pickCustomRange(context, ref),
            child: const Text('Изменить период'),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsErrorState extends StatelessWidget {
  const _AnalyticsErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber, size: 48),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsPieChart extends StatefulWidget {
  const _AnalyticsPieChart({required this.slices});

  final List<AnalyticsPieSlice> slices;

  @override
  State<_AnalyticsPieChart> createState() => _AnalyticsPieChartState();
}

class _AnalyticsPieChartState extends State<_AnalyticsPieChart> {
  int? _focusedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slices = widget.slices;
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.valueMinor);
    final palette = _generatePalette(theme);

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        response == null ||
                        response.touchedSection == null) {
                      _focusedIndex = null;
                    } else {
                      _focusedIndex = response.touchedSection!.touchedSectionIndex;
                    }
                  });
                },
              ),
              sections: [
                for (var i = 0; i < slices.length; i++)
                  _buildSection(
                    slices[i],
                    palette[i % palette.length],
                    total,
                    isFocused: _focusedIndex == i,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < slices.length; i++)
              _LegendEntry(
                color: palette[i % palette.length],
                slice: slices[i],
                total: total,
                isFocused: _focusedIndex == i,
              ),
          ],
        ),
      ],
    );
  }

  PieChartSectionData _buildSection(
    AnalyticsPieSlice slice,
    Color color,
    int total, {
    required bool isFocused,
  }) {
    final ratio = total == 0 ? 0 : slice.valueMinor / total;
    return PieChartSectionData(
      color: hexToColor(slice.colorHex) ?? color,
      value: slice.valueMinor.toDouble().clamp(0.0, double.infinity),
      radius: isFocused ? 68 : 58,
      showTitle: false,
      badgeWidget: isFocused
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${slice.label}: ${(ratio * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          : null,
      badgePositionPercentageOffset: 1.2,
    );
  }

  List<Color> _generatePalette(ThemeData theme) {
    final scheme = theme.colorScheme;
    return [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.error,
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      ...Colors.primaries.map((color) => color.shade400),
    ];
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.slice,
    required this.total,
    required this.isFocused,
  });

  final Color color;
  final AnalyticsPieSlice slice;
  final int total;
  final bool isFocused;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0 : slice.valueMinor / total;
    final percentValue = percent.isNaN ? 0 : percent * 100;
    final percentLabel = percentValue <= 0
        ? '0'
        : percentValue < 0.1
            ? '<0.1'
            : percentValue.toStringAsFixed(1);
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: hexToColor(slice.colorHex) ?? color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isFocused
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slice.label, style: labelStyle),
                Text(
                  '${formatCurrencyMinor(slice.valueMinor)} • $percentLabel%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text('×${slice.operationCount}'),
        ],
      ),
    );
  }
}

class _AnalyticsSeriesChart extends StatelessWidget {
  const _AnalyticsSeriesChart({required this.series, required this.interval});

  final List<AnalyticsTimePoint> series;
  final AnalyticsInterval interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final data = series.toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].valueMinor.toDouble() / 100));
    }
    final maxY = spots.fold<double>(0, (value, spot) => math.max(value, spot.y));
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * 1.2,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (items) {
              return items
                  .map(
                    (item) => LineTooltipItem(
                      '${data[item.spotIndex].bucket}\n${formatCurrencyMinor((item.y * 100).round())}',
                      theme.textTheme.bodyMedium!,
                    ),
                  )
                  .toList();
            },
          ),
        ),
        gridData: FlGridData(show: true, horizontalInterval: math.max(maxY / 4, 1)),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= data.length) {
                  return const SizedBox.shrink();
                }
                final label = _formatBucketLabel(interval, data[index].bucket);
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (value, meta) {
                final rubles = (value).round();
                return Text('${rubles.toString()} ₽', style: theme.textTheme.bodySmall);
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          border: Border.all(color: theme.dividerColor),
        ),
        lineBarsData: [
          LineChartBarData(
            color: color,
            spots: spots,
            isCurved: true,
            dotData: FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBucketLabel(AnalyticsInterval interval, String raw) {
    switch (interval) {
      case AnalyticsInterval.days:
        return raw.substring(5);
      case AnalyticsInterval.weekdays:
        return raw;
      case AnalyticsInterval.months:
        return raw;
      case AnalyticsInterval.halfPeriods:
        return raw;
    }
  }
}

Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
  final filters = ref.read(analyticsFilterProvider);
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2018, 1, 1),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    initialDateRange: DateTimeRange(start: filters.from, end: filters.to),
    helpText: 'Выберите период',
  );
  if (range != null) {
    ref.read(analyticsFilterProvider.notifier).setCustomRange(range);
  }
}
