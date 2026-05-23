import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../providers/alerts_controller.dart';
import '../providers/events_provider.dart';
import '../services/prefs.dart';
import '../theme/app_theme.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../widgets/filter_sheet.dart';
import 'watched_roads_picker_screen.dart';

/// "V bližini": events on watched roads + events near the user's location, with
/// foreground notifications handled by [AlertsController]. Supports the same
/// free-text search as the Dogodki tab.
class NearbyTab extends StatefulWidget {
  const NearbyTab({super.key});

  @override
  State<NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<NearbyTab> {
  static const List<EventSeverity> _order = [
    EventSeverity.closed,
    EventSeverity.jam,
    EventSeverity.roadworks,
    EventSeverity.other,
  ];
  static const List<EventSource> _sourceOrder = [
    EventSource.drsi,
    EventSource.dars,
    EventSource.other,
  ];

  String _query = '';
  final Set<EventSeverity> _active = {..._order};
  final Set<EventSource> _sourceActive = {..._sourceOrder};

  @override
  void initState() {
    super.initState();
    if (Prefs.has('nearby.severities')) {
      _active
        ..clear()
        ..addAll(
          Prefs.getStringList('nearby.severities', const [])
              .map(_severityByName)
              .whereType<EventSeverity>(),
        );
    }
    if (Prefs.has('nearby.sources')) {
      _sourceActive
        ..clear()
        ..addAll(
          Prefs.getStringList('nearby.sources', const [])
              .map(_sourceByName)
              .whereType<EventSource>(),
        );
    }
  }

  static EventSeverity? _severityByName(String n) {
    for (final s in EventSeverity.values) {
      if (s.name == n) return s;
    }
    return null;
  }

  static EventSource? _sourceByName(String n) {
    for (final s in EventSource.values) {
      if (s.name == n) return s;
    }
    return null;
  }

  static String _distance(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  /// Free-text match across all of an event's text fields (same as Dogodki).
  bool _matchesQuery(TrafficEvent e) {
    if (_query.isEmpty) return true;
    final hay =
        '${e.title} ${e.description} ${e.road} ${e.cause} ${e.category} '
                '${e.sideContent} ${e.noticeText}'
            .toLowerCase();
    return hay.contains(_query);
  }

  bool _passes(TrafficEvent e) =>
      _matchesQuery(e) &&
      _active.contains(e.severity) &&
      _sourceActive.contains(e.source);

  int get _activeFilterCount {
    var n = 0;
    if (_active.length != _order.length) n += _active.length;
    if (_sourceActive.length != _sourceOrder.length) n += _sourceActive.length;
    return n;
  }

  void _openFilters() {
    final pending = {..._active};
    final pendingSrc = {..._sourceActive};
    final events = context.read<EventsProvider>().events;
    int count(EventSeverity s) => events.where((e) => e.severity == s).length;
    int srcCount(EventSource s) => events.where((e) => e.source == s).length;

    showFilterSheet(
      context: context,
      title: 'Filtri',
      onReset: () {
        pending
          ..clear()
          ..addAll(_order);
        pendingSrc
          ..clear()
          ..addAll(_sourceOrder);
      },
      onApply: () {
        setState(() {
          _active
            ..clear()
            ..addAll(pending);
          _sourceActive
            ..clear()
            ..addAll(pendingSrc);
        });
        Prefs.setStringList(
          'nearby.severities',
          _active.map((s) => s.name).toList(),
        );
        Prefs.setStringList(
          'nearby.sources',
          _sourceActive.map((s) => s.name).toList(),
        );
      },
      contentBuilder: (setSheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FilterSectionLabel('Tipi dogodkov'),
          for (final s in _order)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(EventVisuals.icon(s), color: EventVisuals.color(s)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${EventVisuals.label(s)} (${count(s)})',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  Switch.adaptive(
                    value: pending.contains(s),
                    activeTrackColor: EventVisuals.color(s),
                    onChanged: (v) => setSheet(() {
                      if (v) {
                        pending.add(s);
                      } else {
                        pending.remove(s);
                      }
                    }),
                  ),
                ],
              ),
            ),
          const FilterSectionLabel('Vir'),
          for (final s in _sourceOrder)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(EventVisuals.sourceIcon(s)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${EventVisuals.sourceLabel(s)} (${srcCount(s)})',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  Switch.adaptive(
                    value: pendingSrc.contains(s),
                    onChanged: (v) => setSheet(() {
                      if (v) {
                        pendingSrc.add(s);
                      } else {
                        pendingSrc.remove(s);
                      }
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    void onChanged(String v) => setState(() => _query = v.toLowerCase().trim());
    return PlatformInfo.isIOS
        ? CupertinoSearchTextField(
            placeholder: 'Išči dogodke…',
            onChanged: onChanged,
          )
        : AdaptiveTextField(
            placeholder: 'Išči dogodke…',
            prefixIcon: const Icon(Icons.search),
            onChanged: onChanged,
          );
  }

  void _openPicker() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WatchedRoadsPickerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(child: _searchField()),
                  const SizedBox(width: 8),
                  FilterButton(
                    activeCount: _activeFilterCount,
                    onTap: _openFilters,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<AlertsController>(
                builder: (context, alerts, _) {
                  final cs = Theme.of(context).colorScheme;
                  final watched = alerts.watchedEvents.where(_passes).toList();
                  final nearby = alerts.nearbyEvents
                      .where((n) => _passes(n.event))
                      .toList();
                  final allEvents = alerts.events.where(_passes).toList();

                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      top: 4,
                      bottom: 16 + AppTheme.bottomBarContentInset(context),
                    ),
                    children: [
                      // Watched roads.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'SPREMLJANE CESTE',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            AdaptiveButton.child(
                              onPressed: _openPicker,
                              style: AdaptiveButtonStyle.plain,
                              size: AdaptiveButtonSize.small,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.map, size: 16, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Izberi na karti',
                                    style: TextStyle(color: cs.primary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!alerts.hasWatched)
                        _hint(
                          cs,
                          'Dodaj ceste (npr. A1) za opozorila o dogodkih na njih.',
                        )
                      else if (watched.isEmpty)
                        _hint(
                          cs,
                          _query.isNotEmpty
                              ? 'Ni zadetkov na spremljanih cestah.'
                              : 'Na spremljanih cestah ni aktivnih dogodkov.',
                        )
                      else
                        _eventCard(
                          context,
                          watched.map((e) => _eventRow(context, e)).toList(),
                        ),

                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          alerts.locationEnabled ? 'V BLIŽINI' : 'VSI DOGODKI',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      // Non-blocking prompt to enable distance + alerts.
                      if (!alerts.locationEnabled)
                        _locationPrompt(context, alerts),
                      if (alerts.locationEnabled)
                        if (nearby.isEmpty)
                          _hint(
                            cs,
                            _query.isNotEmpty
                                ? 'Ni zadetkov v bližini.'
                                : 'Ni dogodkov v bližini.',
                          )
                        else
                          _eventCard(
                            context,
                            nearby
                                .take(50)
                                .map(
                                  (n) => _eventRow(
                                    context,
                                    n.event,
                                    trailing: _distance(n.distanceMeters),
                                  ),
                                )
                                .toList(),
                          )
                      else if (allEvents.isEmpty)
                        _hint(
                          cs,
                          _query.isNotEmpty
                              ? 'Ni zadetkov.'
                              : 'Trenutno ni dogodkov.',
                        )
                      else
                        _eventCard(
                          context,
                          allEvents.map((e) => _eventRow(context, e)).toList(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventCard(BuildContext context, List<Widget> rows) {
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (!PlatformInfo.isIOS && i < rows.length - 1) {
        children.add(
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 48,
            color: cs.outline.withValues(alpha: 0.3),
          ),
        );
      }
    }
    return AdaptiveFormSection.insetGrouped(children: children);
  }

  Widget _eventRow(BuildContext context, TrafficEvent e, {String? trailing}) {
    final cs = Theme.of(context).colorScheme;
    final color = EventVisuals.color(e.severity);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showEventSheet(context, e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Icon(EventVisuals.causeIcon(e), color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (e.road.isNotEmpty) ...[
                        Text(
                          e.road,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          e.title.isEmpty ? e.cause : e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (e.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      e.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hint(ColorScheme cs, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        text,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      ),
    );
  }

  Widget _locationPrompt(BuildContext context, AlertsController alerts) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: AdaptiveCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.my_location, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Vklopi lokacijo za prikaz dogodkov v bližini in opozorila.',
                    style: TextStyle(color: cs.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveButton(
              onPressed: alerts.requesting ? () {} : alerts.enableLocation,
              label: alerts.requesting ? 'Pridobivanje…' : 'Vklopi lokacijo',
            ),
          ],
        ),
      ),
    );
  }
}
