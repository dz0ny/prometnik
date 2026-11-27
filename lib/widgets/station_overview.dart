import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/drsi_station.dart';
import '../models/weather_station.dart';
import '../services/weather_history_service.dart';
import '../theme/app_theme.dart';
import 'drsi_sheet.dart' show drsiRiskAdvice, drsiRiskColor, drsiRiskLabel;
import 'weather_details.dart' show WeatherFormat;

/// Compact combined readout for a place: air and road temperature side by
/// side, the last 24 hours of air temperature (or today's min–max range
/// until history exists), and a dense wrap of compact chips with the
/// remaining readings from the weather station and the DRSI road station.
class StationOverview extends StatefulWidget {
  final WeatherStation station;
  final DrsiStation? road;

  /// Tests: use this series instead of fetching it.
  @visibleForTesting
  final List<WeatherPoint>? historyOverride;

  const StationOverview({
    super.key,
    required this.station,
    this.road,
    this.historyOverride,
  });

  @override
  State<StationOverview> createState() => _StationOverviewState();
}

class _StationOverviewState extends State<StationOverview> {
  List<WeatherPoint> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StationOverview old) {
    super.didUpdateWidget(old);
    if (old.station.stationId != widget.station.stationId) {
      _history = const [];
      _load();
    }
  }

  void _load() {
    if (widget.historyOverride != null) {
      _history = widget.historyOverride!;
      return;
    }
    if (!widget.station.hasWeather) return;
    final id = widget.station.stationId;
    final svc = WeatherHistoryService.instance;
    _history = svc.cached(id) ?? const [];
    unawaited(
      svc.fetch(id).then((points) {
        if (mounted && widget.station.stationId == id) {
          setState(() => _history = points);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = widget.station.weather;
    final road = widget.road;
    final risk = road?.risk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Air | road.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w != null)
                Expanded(
                  child: _HeadlineTile(
                    icon: Icons.thermostat,
                    label: 'Zrak',
                    value: WeatherFormat.temp(w.outdoorTemperatureC),
                    temp: w.outdoorTemperatureC,
                    color: AppTheme.temperatureColor(w.outdoorTemperatureC),
                    detail: _minMax(w),
                  ),
                ),
              if (w != null && road != null) const SizedBox(width: 8),
              if (road != null)
                Expanded(
                  child: _HeadlineTile(
                    icon: risk == RoadRisk.ok ? Icons.add_road : Icons.ac_unit,
                    label: 'Cestišče',
                    value: WeatherFormat.temp(road.roadTemp),
                    temp: road.roadTemp,
                    color: drsiRiskColor(risk!),
                    detail: road.roadState.isEmpty
                        ? drsiRiskLabel(risk)
                        : road.roadState,
                  ),
                ),
            ],
          ),
        ),
        if (road != null && risk != RoadRisk.ok) ...[
          const SizedBox(height: 8),
          _RiskBanner(risk: risk!, alarms: road.alarms),
        ],
        if (w != null) ...[
          const SizedBox(height: 8),
          _TemperatureHistoryCard(reading: w, history: _history),
        ],
        const SizedBox(height: 8),
        _ReadingChips(stats: _stats(cs, w, road)),
        if (road != null) ...[
          const SizedBox(height: 8),
          Text(
            'Cestišče: Direkcija RS za infrastrukturo (CVIS)',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ],
    );
  }

  String? _minMax(WeatherReading w) {
    final lo = w.minOutdoorTemperatureC;
    final hi = w.maxOutdoorTemperatureC;
    if (lo == null && hi == null) return null;
    return 'danes ${WeatherFormat.degrees(lo)} … ${WeatherFormat.degrees(hi)}';
  }

  List<_Stat> _stats(ColorScheme cs, WeatherReading? w, DrsiStation? road) {
    String kmh(double? v) => v == null ? '–' : '${v.round()} km/h';
    final wind = w?.windSpeedKmh ?? road?.windKmh;
    final gust = w?.windGustKmh ?? road?.gustKmh;
    final dir = WeatherFormat.windDirection(w?.windDirection);
    final humidity = w?.humidityPercentage?.toDouble() ?? road?.humidity;
    final dew = w?.dewPointC ?? road?.dewPoint;
    return [
      if (wind != null)
        _Stat(
          Icons.air,
          'Veter',
          dir.isEmpty ? kmh(wind) : '${kmh(wind)} $dir',
        ),
      if (gust != null) _Stat(Icons.storm, 'Sunki', kmh(gust)),
      if (humidity != null && humidity > 0)
        _Stat(Icons.opacity, 'Vlažnost', '${humidity.round()} %'),
      if (w?.dailyRainMm != null)
        _Stat(Icons.umbrella, 'Padavine', WeatherFormat.rain(w!.dailyRainMm)),
      if (road != null && road.precipitation.isNotEmpty)
        _Stat(Icons.grain, 'Trenutno', road.precipitation),
      if (dew != null)
        _Stat(Icons.water_drop, 'Rosišče', WeatherFormat.temp(dew)),
      if (w?.pressureHpa != null)
        _Stat(Icons.speed, 'Tlak', WeatherFormat.pressure(w!.pressureHpa)),
      if (road?.freezePoint != null)
        _Stat(Icons.ac_unit, 'Zmrzišče', WeatherFormat.temp(road!.freezePoint)),
      if (road?.waterFilmMm != null)
        _Stat(
          Icons.waves,
          'Vodni film',
          '${WeatherFormat.decimal(road!.waterFilmMm!, 2)} mm',
        ),
      if (road?.salinity != null)
        _Stat(
          Icons.scatter_plot,
          'Slanost',
          '${road!.salinity!.round()} ${road.salinityUnit}'.trim(),
        ),
    ];
  }
}

class _HeadlineTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// The temperature shown in [value]; tints the number.
  final double? temp;

  /// Tile accent (border, fill, icon and detail).
  final Color color;
  final String? detail;

  const _HeadlineTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.temp,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final accent = AppTheme.readableText(color, brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTheme.numberStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: temp == null
                    ? cs.onSurface
                    : AppTheme.temperatureTextColor(temp, brightness),
              ),
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _RiskBanner extends StatelessWidget {
  final RoadRisk risk;
  final List<String> alarms;

  const _RiskBanner({required this.risk, required this.alarms});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = drsiRiskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppTheme.readableText(color, Theme.of(context).brightness),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${drsiRiskLabel(risk)}. ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: drsiRiskAdvice(risk)),
                  if (alarms.isNotEmpty)
                    TextSpan(text: ' Opozorila: ${alarms.join(', ')}.'),
                ],
              ),
              style: TextStyle(color: cs.onSurface, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// One chart point: an hourly reading, or the current one (last). [rain] is
/// the rain that fell since the previous point (the feed only has today's
/// running total).
typedef _ChartPoint = ({
  DateTime at,
  double? t,
  double? h,
  double? w,
  double? g,
  double? rain,
});

/// Which series the 24-hour card shows.
enum _Metric {
  temp('Temperatura', Icons.thermostat),
  wind('Veter', Icons.air),
  rain('Padavine', Icons.umbrella);

  const _Metric(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Builds the chart points from the stored hours plus the current reading,
/// turning the daily running rain total into per-hour amounts.
List<_ChartPoint> _chartPoints(WeatherReading r, List<WeatherPoint> history) {
  final raw = <({DateTime at, WeatherPoint p})>[
    for (final p in history) (at: p.at, p: p),
    (
      at: DateTime.now(),
      p: WeatherPoint(
        at: DateTime.now(),
        tempC: r.outdoorTemperatureC,
        humidity: r.humidityPercentage?.toDouble(),
        windKmh: r.windSpeedKmh,
        gustKmh: r.windGustKmh,
        rainMm: r.dailyRainMm,
      ),
    ),
  ];
  final out = <_ChartPoint>[];
  for (var i = 0; i < raw.length; i++) {
    final p = raw[i].p;
    final prev = i > 0 ? raw[i - 1].p : null;
    double? rain;
    final total = p.rainMm;
    final before = prev?.rainMm;
    if (total != null && before != null) {
      final newDay = prev!.at.day != p.at.day;
      // The total resets at midnight: after it, everything counted so far
      // today fell since the previous point.
      rain = newDay && total < before ? total : math.max(0, total - before);
    }
    out.add((
      at: raw[i].at,
      t: p.tempC,
      h: p.humidity,
      w: p.windKmh,
      g: p.gustKmh,
      rain: rain,
    ));
  }
  return out;
}

int _count(List<_ChartPoint> points, _Metric m) => points.where((p) {
  return switch (m) {
    _Metric.temp => p.t != null,
    _Metric.wind => p.w != null || p.g != null,
    _Metric.rain => p.rain != null,
  };
}).length;

/// The last 24 hours of air temperature, wind with gusts, and rain, one at a
/// time. Tap or drag across the chart to read any hour; until at least three
/// temperature points exist it shows today's min–max range.
class _TemperatureHistoryCard extends StatefulWidget {
  final WeatherReading reading;
  final List<WeatherPoint> history;

  const _TemperatureHistoryCard({required this.reading, required this.history});

  @override
  State<_TemperatureHistoryCard> createState() =>
      _TemperatureHistoryCardState();
}

class _TemperatureHistoryCardState extends State<_TemperatureHistoryCard> {
  int? _selected;
  _Metric _metric = _Metric.temp;

  /// Nearest point to horizontal position [dx] inside a chart [width] wide.
  void _selectAt(double dx, double width, List<_ChartPoint> points) {
    final chartWidth = width - _HistoryChartPainter.leftPad;
    if (chartWidth <= 0) return;
    final t0 = points.first.at.millisecondsSinceEpoch;
    final t1 = points.last.at.millisecondsSinceEpoch;
    final f = ((dx - _HistoryChartPainter.leftPad) / chartWidth).clamp(
      0.0,
      1.0,
    );
    final target = t0 + (t1 - t0) * f;
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if ((points[i].at.millisecondsSinceEpoch - target).abs() <
          (points[best].at.millisecondsSinceEpoch - target).abs()) {
        best = i;
      }
    }
    if (best != _selected) {
      HapticFeedback.selectionClick();
      setState(() => _selected = best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.reading;
    final now = r.outdoorTemperatureC;
    final points = _chartPoints(r, widget.history);
    final available = [
      for (final m in _Metric.values)
        if (_count(points, m) >= 3) m,
    ];
    final metric = available.contains(_metric)
        ? _metric
        : (available.isEmpty ? _Metric.temp : available.first);
    final hasChart = available.contains(metric);
    final lo = r.minOutdoorTemperatureC;
    final hi = r.maxOutdoorTemperatureC;
    if (!hasChart && (lo == null || hi == null || now == null)) {
      return const SizedBox.shrink();
    }
    final sel = _selected != null && _selected! < points.length
        ? _selected
        : null;
    final color = switch (metric) {
      _Metric.temp => cs.primary,
      _Metric.wind => const Color(0xFF26A69A),
      _Metric.rain => const Color(0xFF42A5F5),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (available.length > 1) ...[
            _MetricSwitch(
              metrics: available,
              selected: metric,
              onSelect: (m) {
                HapticFeedback.selectionClick();
                setState(() => _metric = m);
              },
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(
                hasChart ? Icons.show_chart : metric.icon,
                size: 15,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasChart ? '${metric.label} · 24 ur' : 'Temperatura danes',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasChart)
                _readout(
                  cs,
                  metric,
                  color,
                  points[sel ?? points.length - 1],
                  sel,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Fade between series; only the plot changes, the title and the
          // readout above update in place.
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [
                for (final p in previous) IgnorePointer(child: p),
                ?current,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(hasChart ? 'plot-${metric.name}' : 'plot-range'),
              child: hasChart
                  ? LayoutBuilder(
                      builder: (context, c) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) =>
                            _selectAt(d.localPosition.dx, c.maxWidth, points),
                        onHorizontalDragStart: (d) =>
                            _selectAt(d.localPosition.dx, c.maxWidth, points),
                        onHorizontalDragUpdate: (d) =>
                            _selectAt(d.localPosition.dx, c.maxWidth, points),
                        child: SizedBox(
                          key: ValueKey('${metric.name}-chart'),
                          height: 96,
                          width: c.maxWidth,
                          child: CustomPaint(
                            painter: _HistoryChartPainter(
                              metric: metric,
                              points: points,
                              selected: sel,
                              line: color,
                              grid: cs.outlineVariant,
                              label: cs.onSurfaceVariant,
                              marker: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _RangeBar(lo: lo!, hi: hi!, now: now!),
                        const SizedBox(height: 6),
                        Text(
                          'Graf zadnjih 24 ur se še zbira.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// The selected hour's values, e.g. "22:00  0,4 °C  95 % · 4 km/h", or
  /// "zdaj  …" for the current reading.
  Widget _readout(
    ColorScheme cs,
    _Metric metric,
    Color color,
    _ChartPoint p,
    int? sel,
  ) {
    String kmh(double v) => '${v.round()} km/h';
    final when = sel == null
        ? 'zdaj'
        : '${p.at.hour.toString().padLeft(2, '0')}:00';
    final (String main, List<String> extras) = switch (metric) {
      _Metric.temp => (
        WeatherFormat.temp(p.t),
        [
          if (p.h != null && p.h! > 0) '${p.h!.round()} %',
          if (p.w != null) kmh(p.w!),
        ],
      ),
      _Metric.wind => (
        p.w == null ? '–' : kmh(p.w!),
        [if (p.g != null) 'sunki ${kmh(p.g!)}'],
      ),
      _Metric.rain => (WeatherFormat.rain(p.rain), const <String>[]),
    };
    return Flexible(
      flex: 2,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$when  ',
              style: sel == null
                  ? TextStyle(color: cs.onSurfaceVariant)
                  : AppTheme.numberStyle(color: cs.onSurfaceVariant),
            ),
            TextSpan(
              text: main,
              style: AppTheme.numberStyle(
                fontSize: 13,
                color: sel == null ? cs.onSurface : color,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (extras.isNotEmpty)
              TextSpan(
                text: '  ${extras.join(' · ')}',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Compact pill switch between the chart series.
class _MetricSwitch extends StatelessWidget {
  final List<_Metric> metrics;
  final _Metric selected;
  final ValueChanged<_Metric> onSelect;

  const _MetricSwitch({
    required this.metrics,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final m in metrics)
            Expanded(
              child: Semantics(
                button: true,
                selected: m == selected,
                child: GestureDetector(
                  key: ValueKey('metric-${m.name}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: m == selected
                          ? cs.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          m.icon,
                          size: 14,
                          color: m == selected
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: m == selected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                            ),
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
}

class _RangeBar extends StatelessWidget {
  final double lo;
  final double hi;
  final double now;

  const _RangeBar({required this.lo, required this.hi, required this.now});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final span = math.max(hi - lo, 0.1);
    final pos = ((now - lo) / span).clamp(0.0, 1.0);
    final labelStyle = AppTheme.numberStyle(
      color: cs.onSurfaceVariant,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Text(WeatherFormat.degrees(lo), style: labelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: 16,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.temperatureColor(lo),
                          AppTheme.temperatureColor(hi),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth - 14) * pos,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cs.onSurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(WeatherFormat.degrees(hi), style: labelStyle),
      ],
    );
  }
}

/// Draws one 24-hour series: temperature as a filled line, wind as a filled
/// line with gusts dashed above it, rain as hourly bars.
class _HistoryChartPainter extends CustomPainter {
  static const double leftPad = 30;

  final _Metric metric;
  final List<_ChartPoint> points;
  final int? selected;
  final Color line;
  final Color grid;
  final Color label;
  final Color marker;

  _HistoryChartPainter({
    required this.metric,
    required this.points,
    required this.selected,
    required this.line,
    required this.grid,
    required this.label,
    required this.marker,
  });

  double? _primary(_ChartPoint p) => switch (metric) {
    _Metric.temp => p.t,
    _Metric.wind => p.w,
    _Metric.rain => p.rain,
  };

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 14.0;
    final chart = Rect.fromLTRB(
      leftPad,
      4,
      size.width,
      size.height - bottomPad,
    );
    final values = [
      for (final p in points) ?_primary(p),
      if (metric == _Metric.wind)
        for (final p in points) ?p.g,
    ];
    double lo;
    double hi;
    switch (metric) {
      case _Metric.temp:
        lo = values.reduce(math.min);
        hi = values.reduce(math.max);
        if (hi - lo < 2) {
          final mid = (hi + lo) / 2;
          lo = mid - 1;
          hi = mid + 1;
        }
      case _Metric.wind:
        lo = 0;
        hi = math.max(values.fold(0.0, math.max), 10);
      case _Metric.rain:
        lo = 0;
        hi = math.max(values.fold(0.0, math.max), 1);
    }
    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.at.millisecondsSinceEpoch.toDouble();
    final dt = math.max(t1 - t0, 1.0);
    double x(DateTime at) =>
        chart.left + (at.millisecondsSinceEpoch - t0) / dt * chart.width;
    double y(double v) => chart.bottom - (v - lo) / (hi - lo) * chart.height;

    void text(String s, Offset at, {bool right = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: label,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = at.dx;
      if (right) dx -= tp.width;
      if (center) dx -= tp.width / 2;
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    String axisLabel(double v) => switch (metric) {
      _Metric.temp => '${v.round()}°',
      _Metric.wind => '${v.round()}',
      _Metric.rain => hi < 10 ? WeatherFormat.decimal(v) : '${v.round()}',
    };

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: .6)
      ..strokeWidth = 1;
    for (final v in [hi, lo]) {
      canvas.drawLine(
        Offset(chart.left, y(v)),
        Offset(chart.right, y(v)),
        gridPaint,
      );
      text(axisLabel(v), Offset(chart.left - 5, y(v)), right: true);
    }
    // Freezing line when the temperature range crosses 0 °C.
    if (metric == _Metric.temp && lo < 0 && hi > 0) {
      final zero = Paint()
        ..color = const Color(0xFF42A5F5)
        ..strokeWidth = 1;
      for (var dx = chart.left; dx < chart.right; dx += 6) {
        canvas.drawLine(Offset(dx, y(0)), Offset(dx + 3, y(0)), zero);
      }
    }

    if (metric == _Metric.rain) {
      _paintBars(canvas, chart, x, y);
    } else {
      if (metric == _Metric.wind) _paintGusts(canvas, x, y);
      _paintLine(canvas, chart, x, y);
    }

    final sel = selected;
    if (sel != null) {
      final p = points[sel];
      final v = _primary(p);
      final dx = x(p.at);
      canvas.drawLine(
        Offset(dx, chart.top),
        Offset(dx, chart.bottom),
        Paint()
          ..color = marker.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      if (v != null) {
        final at = Offset(dx, y(v));
        canvas.drawCircle(at, 6, Paint()..color = line.withValues(alpha: .25));
        canvas.drawCircle(at, 4, Paint()..color = line);
        canvas.drawCircle(
          at,
          4,
          Paint()
            ..color = marker
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Time axis: start, middle, now.
    String hh(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h';
    final axisY = size.height - bottomPad / 2 + 2;
    text(hh(points.first.at), Offset(chart.left, axisY));
    final mid = DateTime.fromMillisecondsSinceEpoch((t0 + dt / 2).round());
    text(hh(mid), Offset(chart.center.dx, axisY), center: true);
    text('zdaj', Offset(chart.right, axisY), right: true);
  }

  /// The primary series as a line with a soft fill; gaps break the line.
  void _paintLine(
    Canvas canvas,
    Rect chart,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final path = Path();
    final fill = Path();
    Offset? first;
    Offset? last;
    void closeFill() {
      if (first != null && last != null) {
        fill
          ..lineTo(last.dx, chart.bottom)
          ..lineTo(first!.dx, chart.bottom)
          ..close();
      }
      first = null;
    }

    for (final p in points) {
      final v = _primary(p);
      if (v == null) {
        closeFill();
        last = null;
        continue;
      }
      final o = Offset(x(p.at), y(v));
      if (first == null) {
        path.moveTo(o.dx, o.dy);
        fill.moveTo(o.dx, o.dy);
        first = o;
      } else {
        path.lineTo(o.dx, o.dy);
        fill.lineTo(o.dx, o.dy);
      }
      last = o;
    }
    closeFill();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: .28), line.withValues(alpha: 0)],
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = line.withValues(alpha: .55);
    for (final p in points.take(points.length - 1)) {
      final v = _primary(p);
      if (v != null) canvas.drawCircle(Offset(x(p.at), y(v)), 1.8, dot);
    }
    final now = _primary(points.last);
    if (now != null) {
      canvas.drawCircle(
        Offset(x(points.last.at), y(now)),
        3.5,
        Paint()..color = line,
      );
    }
  }

  /// Gusts as a thin dashed line above the wind.
  void _paintGusts(
    Canvas canvas,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final paint = Paint()
      ..color = line.withValues(alpha: .7)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    for (final p in points) {
      final g = p.g;
      if (g == null) {
        prev = null;
        continue;
      }
      final o = Offset(x(p.at), y(g));
      if (prev != null) {
        final d = o - prev;
        final len = d.distance;
        if (len > 0) {
          final step = d / len;
          for (var s = 0.0; s < len; s += 6) {
            canvas.drawLine(
              prev + step * s,
              prev + step * math.min(s + 3, len),
              paint,
            );
          }
        }
      }
      canvas.drawCircle(o, 1.6, paint);
      prev = o;
    }
  }

  /// Rain per hour as bars centred on each hour.
  void _paintBars(
    Canvas canvas,
    Rect chart,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final width = math.max(
      2.0,
      math.min(10.0, chart.width / points.length * .6),
    );
    final paint = Paint()..color = line;
    final faint = Paint()..color = line.withValues(alpha: .45);
    for (var i = 0; i < points.length; i++) {
      final v = points[i].rain;
      if (v == null || v <= 0) continue;
      final cx = x(points[i].at)
          .clamp(chart.left + width / 2, chart.right - width / 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            cx - width / 2,
            math.min(y(v), chart.bottom - 1.5),
            cx + width / 2,
            chart.bottom,
          ),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        // The last bar is the hour still in progress.
        i == points.length - 1 ? faint : paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HistoryChartPainter old) =>
      old.metric != metric ||
      old.selected != selected ||
      old.points.length != points.length ||
      old.points.last != points.last ||
      old.line != line;
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;
  const _Stat(this.icon, this.label, this.value);
}

/// Dense wrap of compact reading chips — icon, value and a small label —
/// three per row (two on narrow screens or at large text).
class _ReadingChips extends StatelessWidget {
  final List<_Stat> stats;
  const _ReadingChips({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 6.0;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale > 1.3 || c.maxWidth < 330 ? 2 : 3;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in stats)
              SizedBox(
                width: width,
                child: _ReadingChip(stat: s),
              ),
          ],
        );
      },
    );
  }
}

class _ReadingChip extends StatelessWidget {
  final _Stat stat;
  const _ReadingChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(stat.icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stat.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.numberStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.2,
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
