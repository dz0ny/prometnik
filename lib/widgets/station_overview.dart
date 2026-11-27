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
        // Current air conditions, then the road surface.
        if (w != null && w.outdoorTemperatureC != null)
          _AirCard(reading: w, history: _history)
        else if (w != null)
          _HeadlineTile(
            icon: Icons.thermostat,
            label: 'Zrak',
            value: WeatherFormat.temp(w.outdoorTemperatureC),
            temp: w.outdoorTemperatureC,
            color: AppTheme.temperatureColor(w.outdoorTemperatureC),
            detail: _minMax(w),
          ),
        if (w != null && road != null) const SizedBox(height: 8),
        if (road != null)
          _HeadlineTile(
            icon: risk == RoadRisk.ok ? Icons.add_road : Icons.ac_unit,
            label: 'Cestišče',
            value: WeatherFormat.temp(road.roadTemp),
            temp: road.roadTemp,
            color: drsiRiskColor(risk!),
            detail: road.roadState.isEmpty
                ? drsiRiskLabel(risk)
                : road.roadState,
          ),
        if (road != null && risk != RoadRisk.ok) ...[
          const SizedBox(height: 8),
          _RiskBanner(risk: risk!, alarms: road.alarms),
        ],
        if (w != null) ...[
          const SizedBox(height: 8),
          _TemperatureHistoryCard(
            reading: w,
            history: _history,
            title: widget.station.name,
          ),
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

/// Change of [now] against the reading about an hour earlier in [history]
/// (40 minutes to 2 hours back); null without such a reading.
@visibleForTesting
double? hourlyTrend(double now, List<WeatherPoint> history, DateTime at) {
  WeatherPoint? best;
  for (final p in history) {
    final age = at.difference(p.at);
    if (p.tempC == null ||
        age < const Duration(minutes: 40) ||
        age > const Duration(hours: 2)) {
      continue;
    }
    if (best == null ||
        (age - const Duration(hours: 1)).abs() <
            (at.difference(best.at) - const Duration(hours: 1)).abs()) {
      best = p;
    }
  }
  return best == null ? null : now - best.tempC!;
}

/// The current air reading: a large temperature tinted by its value with the
/// change over the last hour, and today's range as a bar with the current
/// value marked.
class _AirCard extends StatelessWidget {
  final WeatherReading reading;
  final List<WeatherPoint> history;

  const _AirCard({required this.reading, required this.history});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final t = reading.outdoorTemperatureC!;
    final tint = AppTheme.temperatureColor(t);
    final text = AppTheme.temperatureTextColor(t, brightness);
    final trend = hourlyTrend(t, history, DateTime.now());
    final lo = reading.minOutdoorTemperatureC;
    final hi = reading.maxOutdoorTemperatureC;
    final number = WeatherFormat.decimal(t);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            tint.withValues(alpha: .22),
            cs.surfaceContainerHighest.withValues(alpha: .55),
          ],
        ),
        border: Border.all(color: tint.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.thermostat, size: 15, color: text),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Zrak',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: number),
                        TextSpan(
                          text: ' °C',
                          style: AppTheme.numberStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                      ],
                    ),
                    key: const ValueKey('air-now'),
                    style: AppTheme.numberStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: text,
                    ),
                  ),
                ),
                if (trend != null) _Trend(delta: trend),
              ],
            ),
          ),
          if (lo != null && hi != null) ...[
            const SizedBox(width: 14),
            Expanded(
              flex: 9,
              child: _TodayRange(lo: lo, hi: hi, now: t),
            ),
          ],
        ],
      ),
    );
  }
}

/// "↑ 0,8° v zadnji uri" — steady within ±0,2°.
class _Trend extends StatelessWidget {
  final double delta;

  const _Trend({required this.delta});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steady = delta.abs() < 0.25;
    final icon = steady
        ? Icons.trending_flat
        : delta > 0
        ? Icons.trending_up
        : Icons.trending_down;
    final label = steady
        ? 'brez spremembe v zadnji uri'
        : '${delta > 0 ? '+' : '−'}${WeatherFormat.decimal(delta.abs())}° '
              'v zadnji uri';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.numberStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Today's minimum and maximum with a gradient bar and the current value.
class _TodayRange extends StatelessWidget {
  final double lo;
  final double hi;
  final double now;

  const _TodayRange({required this.lo, required this.hi, required this.now});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final span = math.max(hi - lo, 0.1);
    final pos = ((now - lo) / span).clamp(0.0, 1.0);
    Widget end(String caption, double v, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          WeatherFormat.degrees(v),
          style: AppTheme.numberStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.temperatureTextColor(v, brightness),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Danes',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.temperatureColor(lo),
                        AppTheme.temperatureColor(hi),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (c.maxWidth - 16) * pos,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: cs.onSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: end('najnižja', lo, CrossAxisAlignment.start),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: end('najvišja', hi, CrossAxisAlignment.end),
                ),
              ),
            ),
          ],
        ),
      ],
    );
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
  String? d,
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
        windDir: r.windDirection?.trim(),
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
      d: p.windDir == null || p.windDir!.isEmpty ? null : p.windDir,
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

  /// Station name for the fullscreen view's title.
  final String title;

  /// Fills its parent with a tall chart (the fullscreen view).
  final bool fullscreen;
  final _Metric? initialMetric;

  const _TemperatureHistoryCard({
    required this.reading,
    required this.history,
    this.title = '',
    this.fullscreen = false,
    this.initialMetric,
  });

  @override
  State<_TemperatureHistoryCard> createState() =>
      _TemperatureHistoryCardState();
}

class _TemperatureHistoryCardState extends State<_TemperatureHistoryCard> {
  int? _selected;
  late _Metric _metric = widget.initialMetric ?? _Metric.temp;

  void _openFullscreen(_Metric metric) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _HistoryFullscreen(
          title: widget.title,
          reading: widget.reading,
          history: widget.history,
          metric: metric,
        ),
      ),
    );
  }

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
        color: widget.fullscreen
            ? null
            : cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: widget.fullscreen ? MainAxisSize.max : MainAxisSize.min,
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
                  hasChart ? _title(metric, points) : 'Temperatura danes',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasChart && !widget.fullscreen)
                SizedBox(
                  width: 32,
                  height: 24,
                  child: IconButton(
                    key: const ValueKey('chart-fullscreen'),
                    tooltip: 'Celoten zaslon',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: cs.onSurfaceVariant,
                    icon: const Icon(Icons.open_in_full),
                    onPressed: () => _openFullscreen(metric),
                  ),
                ),
            ],
          ),
          if (hasChart) ...[
            const SizedBox(height: 6),
            _readout(cs, metric, color, points[sel ?? points.length - 1], sel),
          ],
          const SizedBox(height: 10),
          // Fade between series; only the plot changes, the title and the
          // readout above update in place.
          _expandIf(
            widget.fullscreen,
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
                            height: widget.fullscreen ? c.maxHeight : 150,
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
                                textScale: widget.fullscreen ? 1.2 : 1,
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
          ),
          if (hasChart && metric == _Metric.wind) ...[
            const SizedBox(height: 8),
            _WindLegend(color: color, arrows: points.any((p) => p.d != null)),
          ],
        ],
      ),
    );
  }

  /// "Temperatura · 24 ur"; rain adds the total that fell in that time.
  static String _title(_Metric metric, List<_ChartPoint> points) {
    if (metric != _Metric.rain) return '${metric.label} · 24 ur';
    final total = points.fold<double>(0, (sum, p) => sum + (p.rain ?? 0));
    return '${metric.label} · 24 ur: ${WeatherFormat.rain(total)}';
  }

  static Widget _expandIf(bool expand, Widget child) =>
      expand ? Expanded(child: child) : child;

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
        [
          if (p.d != null) WeatherFormat.windDirection(p.d),
          if (p.g != null) 'sunki ${kmh(p.g!)}',
        ],
      ),
      _Metric.rain => (WeatherFormat.rain(p.rain), const ['v eni uri']),
    };
    // Big value in the series colour, the time and secondary values beside
    // it; two lines reserved so the card doesn't jump while scrubbing.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          main,
          key: const ValueKey('chart-readout'),
          style: AppTheme.numberStyle(
            fontSize: widget.fullscreen ? 32 : 26,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: sel == null ? 'zdaj' : 'ob $when',
                  style: AppTheme.numberStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (extras.isNotEmpty)
                  TextSpan(text: '\n${extras.join(' · ')}'),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Key under the wind chart: what the solid and dashed lines and the arrows
/// mean.
class _WindLegend extends StatelessWidget {
  final Color color;
  final bool arrows;

  const _WindLegend({required this.color, required this.arrows});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
    );
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 6),
        Text(text, style: style),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(Container(width: 16, height: 3, color: color), 'Povprečni veter'),
        item(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 4,
                  height: 2,
                  margin: const EdgeInsets.only(right: 2),
                  color: color.withValues(alpha: .8),
                ),
            ],
          ),
          'Sunki',
        ),
        if (arrows)
          item(
            Icon(Icons.navigation, size: 14, color: cs.onSurface),
            'Smer pihanja',
          ),
      ],
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

/// Draws one 24-hour series: temperature as a smooth filled line, wind as a
/// line with gusts dashed above it and direction arrows on top, rain as
/// hourly bars. Three labelled gridlines and a 6-hourly time axis.
class _HistoryChartPainter extends CustomPainter {
  static const double leftPad = 34;
  static const double _arrowBand = 22;
  static const double _bottomPad = 18;

  final _Metric metric;
  final List<_ChartPoint> points;
  final int? selected;
  final Color line;
  final Color grid;
  final Color label;
  final Color marker;

  /// Larger type for the fullscreen view.
  final double textScale;

  _HistoryChartPainter({
    required this.metric,
    required this.points,
    required this.selected,
    required this.line,
    required this.grid,
    required this.label,
    required this.marker,
    this.textScale = 1,
  });

  double? _primary(_ChartPoint p) => switch (metric) {
    _Metric.temp => p.t,
    _Metric.wind => p.w,
    _Metric.rain => p.rain,
  };

  /// A "nice" step (1, 2, 5 × 10ⁿ) so gridlines land on round values.
  static double _niceStep(double span, int steps) {
    final raw = span / steps;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 5.0, 10.0]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final arrows = metric == _Metric.wind && points.any((p) => p.d != null);
    final chart = Rect.fromLTRB(
      leftPad,
      arrows ? _arrowBand + 4 : 8,
      size.width - 4,
      size.height - _bottomPad,
    );
    final values = [
      for (final p in points) ?_primary(p),
      if (metric == _Metric.wind)
        for (final p in points) ?p.g,
    ];
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (metric != _Metric.temp) lo = 0;
    final minSpan = switch (metric) {
      _Metric.temp => 4.0,
      _Metric.wind => 10.0,
      _Metric.rain => 1.0,
    };
    if (hi - lo < minSpan) hi = lo + minSpan;
    final step = _niceStep(hi - lo, 3);
    lo = (lo / step).floor() * step;
    hi = math.max((hi / step).ceil() * step, lo + 2 * step);

    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.at.millisecondsSinceEpoch.toDouble();
    final dt = math.max(t1 - t0, 1.0);
    double x(DateTime at) =>
        chart.left + (at.millisecondsSinceEpoch - t0) / dt * chart.width;
    double y(double v) => chart.bottom - (v - lo) / (hi - lo) * chart.height;

    void text(
      String s,
      Offset at, {
      bool right = false,
      bool center = false,
      Color? color,
      FontWeight weight = FontWeight.w700,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: AppTheme.numberStyle(
            fontSize: 11 * textScale,
            fontWeight: weight,
            color: color ?? label,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = at.dx;
      if (right) dx -= tp.width;
      if (center) dx -= tp.width / 2;
      dx = dx.clamp(0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    String num(double v) => (v - v.roundToDouble()).abs() < 1e-6
        ? '${v.round()}'
        : WeatherFormat.decimal(v);
    final unit = switch (metric) {
      _Metric.temp => '°',
      _Metric.wind => '',
      _Metric.rain => '',
    };

    // Gridlines: dashed, with values on the left; the unit sits on the top one.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: .5)
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + step / 2; v += step) {
      final gy = y(v);
      for (var dx = chart.left; dx < chart.right; dx += 5) {
        canvas.drawLine(
          Offset(dx, gy),
          Offset(math.min(dx + 2.5, chart.right), gy),
          gridPaint,
        );
      }
      text('${num(v)}$unit', Offset(chart.left - 6, gy), right: true);
    }
    final unitLabel = switch (metric) {
      _Metric.temp => null,
      _Metric.wind => 'km/h',
      _Metric.rain => 'mm',
    };
    if (unitLabel != null) {
      text(
        unitLabel,
        Offset(chart.left - 6, chart.top - 10 * textScale),
        right: true,
        weight: FontWeight.w600,
      );
    }
    // Freezing line when the temperature range crosses 0 °C.
    if (metric == _Metric.temp && lo < 0 && hi > 0) {
      canvas.drawLine(
        Offset(chart.left, y(0)),
        Offset(chart.right, y(0)),
        Paint()
          ..color = const Color(0xFF42A5F5).withValues(alpha: .8)
          ..strokeWidth = 1.2,
      );
    }

    // Time axis: every 6 hours on the hour, and "zdaj" at the end.
    final axisY = size.height - _bottomPad / 2 + 1;
    final tickPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final first = points.first.at;
    var tick = DateTime(first.year, first.month, first.day, first.hour + 1);
    while (tick.hour % 6 != 0) {
      tick = tick.add(const Duration(hours: 1));
    }
    final nowX = x(points.last.at);
    for (; x(tick) < nowX - 28; tick = tick.add(const Duration(hours: 6))) {
      final tx = x(tick);
      canvas.drawLine(
        Offset(tx, chart.bottom),
        Offset(tx, chart.bottom + 3),
        tickPaint,
      );
      text(
        '${tick.hour.toString().padLeft(2, '0')}h',
        Offset(tx, axisY),
        center: true,
      );
    }
    text('zdaj', Offset(chart.right, axisY), right: true, color: marker);

    if (metric == _Metric.rain) {
      _paintBars(canvas, chart, x, y);
    } else {
      if (metric == _Metric.wind) _paintGusts(canvas, chart, x, y);
      _paintLine(canvas, chart, x, y);
      if (arrows) _paintDirections(canvas, x);
    }

    final sel = selected;
    if (sel != null) {
      final p = points[sel];
      final v = _primary(p);
      final dx = x(p.at);
      canvas.drawLine(
        Offset(dx, chart.top - (arrows ? _arrowBand : 0)),
        Offset(dx, chart.bottom),
        Paint()
          ..color = marker.withValues(alpha: .6)
          ..strokeWidth = 1.2,
      );
      if (v != null && metric != _Metric.rain) {
        final at = Offset(dx, y(v));
        canvas.drawCircle(at, 8, Paint()..color = line.withValues(alpha: .25));
        canvas.drawCircle(at, 5, Paint()..color = line);
        canvas.drawCircle(
          at,
          5,
          Paint()
            ..color = marker
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  /// A smooth path through [pts] (Catmull-Rom as cubic Béziers), with the
  /// control points clamped vertically so it never overshoots a reading.
  static Path _smooth(List<Offset> pts, {Path? into}) {
    final path = into ?? Path();
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final lo = math.min(p1.dy, p2.dy);
      final hi = math.max(p1.dy, p2.dy);
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        (p1.dy + (p2.dy - p0.dy) / 6).clamp(lo, hi),
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        (p2.dy - (p3.dy - p1.dy) / 6).clamp(lo, hi),
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  /// Consecutive runs of present values as screen points (gaps break runs).
  List<List<Offset>> _runs(
    double? Function(_ChartPoint) value,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (final p in points) {
      final v = value(p);
      if (v == null) {
        if (run.isNotEmpty) runs.add(run);
        run = [];
        continue;
      }
      run.add(Offset(x(p.at), y(v)));
    }
    if (run.isNotEmpty) runs.add(run);
    return runs;
  }

  void _paintLine(
    Canvas canvas,
    Rect chart,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [line.withValues(alpha: .30), line.withValues(alpha: 0)],
      ).createShader(chart);
    for (final run in _runs(_primary, x, y)) {
      if (run.length == 1) {
        canvas.drawCircle(run.first, 3, Paint()..color = line);
        continue;
      }
      final path = _smooth(run);
      canvas.drawPath(
        Path.from(path)
          ..lineTo(run.last.dx, chart.bottom)
          ..lineTo(run.first.dx, chart.bottom)
          ..close(),
        fill,
      );
      canvas.drawPath(path, stroke);
    }
    final now = _primary(points.last);
    if (now != null) {
      final at = Offset(x(points.last.at), y(now));
      canvas
        ..drawCircle(at, 5, Paint()..color = line.withValues(alpha: .3))
        ..drawCircle(at, 3.5, Paint()..color = line);
    }
  }

  /// Wind direction as arrows in a band above the chart, pointing where the
  /// wind blows to; thinned out so they never crowd.
  void _paintDirections(Canvas canvas, double Function(DateTime) x) {
    final paint = Paint()..color = marker.withValues(alpha: .85);
    const cy = _arrowBand / 2;
    final s = 1.2 * textScale;
    double? lastX;
    for (var i = points.length - 1; i >= 0; i--) {
      final from = WeatherFormat.bearing(points[i].d);
      if (from == null) continue;
      final px = x(points[i].at);
      if (lastX != null && lastX - px < 22 * textScale) continue;
      lastX = px;
      // Bearing is where the wind comes from; screen angle 0 = up.
      canvas
        ..save()
        ..translate(px, cy)
        ..rotate((from + 180) * math.pi / 180)
        ..scale(s);
      canvas
        ..drawPath(
          Path()
            ..moveTo(0, -7)
            ..lineTo(5, 5)
            ..lineTo(0, 2.5)
            ..lineTo(-5, 5)
            ..close(),
          paint,
        )
        ..restore();
    }
  }

  /// Gusts as a dashed smooth line above the wind.
  void _paintGusts(
    Canvas canvas,
    Rect chart,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final paint = Paint()
      ..color = line.withValues(alpha: .75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final run in _runs((p) => p.g, x, y)) {
      if (run.length < 2) continue;
      for (final metric in _smooth(run).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 7) {
          canvas.drawPath(metric.extractPath(d, d + 3.5), paint);
        }
      }
    }
  }

  /// Rain per hour as bars filling each hour's slot.
  void _paintBars(
    Canvas canvas,
    Rect chart,
    double Function(DateTime) x,
    double Function(double) y,
  ) {
    final slot = chart.width / math.max(points.length - 1, 1);
    final width = (slot * .7).clamp(3.0, 28.0);
    final paint = Paint()..color = line;
    final faint = Paint()..color = line.withValues(alpha: .45);
    for (var i = 0; i < points.length; i++) {
      final v = points[i].rain;
      if (v == null || v <= 0) continue;
      final cx = x(points[i].at)
          .clamp(chart.left + width / 2, chart.right - width / 2);
      final top = math.min(y(v), chart.bottom - 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(cx - width / 2, top, cx + width / 2, chart.bottom),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
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
      old.line != line ||
      old.textScale != textScale;
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

/// The 24-hour chart filling the screen (also in landscape), opened from the
/// card's expand button.
class _HistoryFullscreen extends StatelessWidget {
  final String title;
  final WeatherReading reading;
  final List<WeatherPoint> history;
  final _Metric metric;

  const _HistoryFullscreen({
    required this.title,
    required this.reading,
    required this.history,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? 'Zadnjih 24 ur' : title),
        leading: IconButton(
          tooltip: 'Zapri',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 16, 12),
          child: _TemperatureHistoryCard(
            reading: reading,
            history: history,
            title: title,
            fullscreen: true,
            initialMetric: metric,
          ),
        ),
      ),
    );
  }
}
