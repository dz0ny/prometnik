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
/// until history exists), and one dense grid of the remaining readings from
/// the weather station and the DRSI road station.
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
        _StatGrid(stats: _stats(cs, w, road)),
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
  final Color color;
  final String? detail;

  const _HeadlineTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = AppTheme.readableText(color, Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.15,
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
                fontSize: 12,
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

/// 24-hour air temperature chart; until at least two hourly points exist it
/// shows today's min–max range with the current value marked.
/// One chart point: an hourly reading, or the current one (last).
typedef _ChartPoint = ({DateTime at, double t, double? h, double? w});

/// 24-hour air temperature chart. Tap or drag across it to read any hour;
/// until at least three points exist it shows today's min–max range.
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

  List<_ChartPoint> _points() {
    final r = widget.reading;
    return [
      for (final p in widget.history)
        if (p.tempC != null)
          (at: p.at, t: p.tempC!, h: p.humidity, w: p.windKmh),
      if (r.outdoorTemperatureC != null)
        (
          at: DateTime.now(),
          t: r.outdoorTemperatureC!,
          h: r.humidityPercentage?.toDouble(),
          w: r.windSpeedKmh,
        ),
    ];
  }

  /// Nearest point to horizontal position [dx] inside a chart [width] wide.
  void _selectAt(double dx, double width, List<_ChartPoint> points) {
    final chartWidth = width - _TempChartPainter.leftPad;
    if (chartWidth <= 0) return;
    final t0 = points.first.at.millisecondsSinceEpoch;
    final t1 = points.last.at.millisecondsSinceEpoch;
    final f = ((dx - _TempChartPainter.leftPad) / chartWidth).clamp(0.0, 1.0);
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
    final points = _points();
    final hasChart = points.length >= 3;
    final lo = r.minOutdoorTemperatureC;
    final hi = r.maxOutdoorTemperatureC;
    if (!hasChart && (lo == null || hi == null || now == null)) {
      return const SizedBox.shrink();
    }
    final sel = _selected != null && _selected! < points.length
        ? _selected
        : null;

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
          Row(
            children: [
              Icon(Icons.show_chart, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasChart ? 'Temperatura · 24 ur' : 'Temperatura danes',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasChart) _readout(cs, points[sel ?? points.length - 1], sel),
            ],
          ),
          const SizedBox(height: 8),
          if (hasChart)
            LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _selectAt(d.localPosition.dx, c.maxWidth, points),
                onHorizontalDragStart: (d) =>
                    _selectAt(d.localPosition.dx, c.maxWidth, points),
                onHorizontalDragUpdate: (d) =>
                    _selectAt(d.localPosition.dx, c.maxWidth, points),
                child: SizedBox(
                  key: const ValueKey('temperature-chart'),
                  height: 96,
                  width: c.maxWidth,
                  child: CustomPaint(
                    painter: _TempChartPainter(
                      points: points,
                      selected: sel,
                      line: cs.primary,
                      grid: cs.outlineVariant,
                      label: cs.onSurfaceVariant,
                      marker: cs.onSurface,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            _RangeBar(lo: lo!, hi: hi!, now: now!),
            const SizedBox(height: 6),
            Text(
              'Graf zadnjih 24 ur se še zbira.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// "22:00 · 0,4 °C · 95 % · 4 km/h" for the selected hour, "zdaj · …" for
  /// the current reading.
  Widget _readout(ColorScheme cs, _ChartPoint p, int? sel) {
    final when = sel == null
        ? 'zdaj'
        : '${p.at.hour.toString().padLeft(2, '0')}:00';
    final extras = [
      if (p.h != null && p.h! > 0) '${p.h!.round()} %',
      if (p.w != null) '${p.w!.round()} km/h',
    ];
    return Flexible(
      flex: 2,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$when  ',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            TextSpan(
              text: WeatherFormat.temp(p.t),
              style: TextStyle(
                color: sel == null ? cs.onSurface : cs.primary,
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
    final labelStyle = TextStyle(
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

class _TempChartPainter extends CustomPainter {
  static const double leftPad = 30;

  final List<_ChartPoint> points;
  final int? selected;
  final Color line;
  final Color grid;
  final Color label;
  final Color marker;

  _TempChartPainter({
    required this.points,
    required this.selected,
    required this.line,
    required this.grid,
    required this.label,
    required this.marker,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bottomPad = 14.0;
    final chart = Rect.fromLTRB(
      leftPad,
      4,
      size.width,
      size.height - bottomPad,
    );
    var lo = points.map((p) => p.t).reduce(math.min);
    var hi = points.map((p) => p.t).reduce(math.max);
    if (hi - lo < 2) {
      final mid = (hi + lo) / 2;
      lo = mid - 1;
      hi = mid + 1;
    }
    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.at.millisecondsSinceEpoch.toDouble();
    final dt = math.max(t1 - t0, 1.0);
    double x(DateTime at) =>
        chart.left + (at.millisecondsSinceEpoch - t0) / dt * chart.width;
    double y(double t) => chart.bottom - (t - lo) / (hi - lo) * chart.height;

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

    final gridPaint = Paint()
      ..color = grid.withValues(alpha: .6)
      ..strokeWidth = 1;
    // Min / max guides with their values.
    for (final v in [hi, lo]) {
      canvas.drawLine(
        Offset(chart.left, y(v)),
        Offset(chart.right, y(v)),
        gridPaint,
      );
      text('${v.round()}°', Offset(chart.left - 5, y(v)), right: true);
    }
    // Freezing line when the range crosses 0 °C.
    if (lo < 0 && hi > 0) {
      final zero = Paint()
        ..color = const Color(0xFF42A5F5)
        ..strokeWidth = 1;
      for (var dx = chart.left; dx < chart.right; dx += 6) {
        canvas.drawLine(Offset(dx, y(0)), Offset(dx + 3, y(0)), zero);
      }
    }

    final path = Path()..moveTo(x(points.first.at), y(points.first.t));
    for (final p in points.skip(1)) {
      path.lineTo(x(p.at), y(p.t));
    }
    final fill = Path.from(path)
      ..lineTo(chart.right, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
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
    final last = Offset(x(points.last.at), y(points.last.t));
    canvas.drawCircle(last, 3.5, Paint()..color = line);

    // Hour dots, and the selected hour's guide line.
    final dot = Paint()..color = line.withValues(alpha: .55);
    for (final p in points.take(points.length - 1)) {
      canvas.drawCircle(Offset(x(p.at), y(p.t)), 1.8, dot);
    }
    final sel = selected;
    if (sel != null) {
      final p = points[sel];
      final at = Offset(x(p.at), y(p.t));
      canvas.drawLine(
        Offset(at.dx, chart.top),
        Offset(at.dx, chart.bottom),
        Paint()
          ..color = marker.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
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

    // Time axis: start, middle, now.
    String hh(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h';
    final axisY = size.height - bottomPad / 2 + 2;
    text(hh(points.first.at), Offset(chart.left, axisY));
    final mid = DateTime.fromMillisecondsSinceEpoch((t0 + dt / 2).round());
    text(hh(mid), Offset(chart.center.dx, axisY), center: true);
    text('zdaj', Offset(chart.right, axisY), right: true);
  }

  @override
  bool shouldRepaint(_TempChartPainter old) =>
      old.selected != selected ||
      old.points.length != points.length ||
      old.points.last.t != points.last.t ||
      old.line != line;
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;
  const _Stat(this.icon, this.label, this.value);
}

/// Three-column grid of small label/value tiles.
class _StatGrid extends StatelessWidget {
  final List<_Stat> stats;
  const _StatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale > 1.3 || c.maxWidth < 330 ? 2 : 3;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in stats)
              Container(
                width: width,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(s.icon, size: 13, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
