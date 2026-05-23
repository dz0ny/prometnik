import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/traffic_event.dart';
import '../providers/events_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/event_sheet.dart';
import '../widgets/event_visuals.dart';
import '../widgets/filter_sheet.dart';

/// Lists current traffic events ("dogodki"), grouped by severity, from the
/// promet.si data channel. Severity filter pills at the top narrow the list;
/// tapping a row opens the event detail sheet.
class EventsTab extends StatefulWidget {
  const EventsTab({super.key});

  @override
  State<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<EventsTab> {
  static const List<EventSeverity> _order = [
    EventSeverity.closed,
    EventSeverity.jam,
    EventSeverity.roadworks,
    EventSeverity.other,
  ];

  /// Active severity filters; all on by default.
  final Set<EventSeverity> _active = {..._order};

  String _query = '';

  /// Free-text match across all of an event's text fields.
  bool _matchesQuery(TrafficEvent e) {
    if (_query.isEmpty) return true;
    final hay =
        '${e.title} ${e.description} ${e.road} ${e.cause} ${e.category} '
                '${e.sideContent} ${e.noticeText}'
            .toLowerCase();
    return hay.contains(_query);
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

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      body: SafeArea(
        bottom: false,
        child: Consumer<EventsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && !provider.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (provider.error != null && !provider.hasData) {
              return _error(context, provider);
            }
            if (provider.events.isEmpty) {
              return _empty(
                context,
                Icons.check_circle_outline,
                'Trenutno ni dogodkov.',
              );
            }

            // Apply the text search, then bucket by severity (counts drive the
            // filter sheet and section headers).
            final matched = provider.events.where(_matchesQuery).toList();
            final buckets = {for (final s in _order) s: <TrafficEvent>[]};
            for (final e in matched) {
              buckets[e.severity]!.add(e);
            }
            final sections = _order
                .where((s) => _active.contains(s) && buckets[s]!.isNotEmpty)
                .toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(child: _searchField()),
                      const SizedBox(width: 8),
                      FilterButton(
                        activeCount: _activeFilterCount,
                        onTap: () => _openFilters(buckets),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: sections.isEmpty
                      ? _empty(
                          context,
                          _query.isNotEmpty
                              ? Icons.search_off
                              : Icons.filter_alt_off,
                          _query.isNotEmpty
                              ? 'Ni zadetkov.'
                              : 'Ni dogodkov za izbrane filtre.',
                        )
                      : RefreshIndicator(
                          onRefresh: provider.refresh,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(
                              top: 4,
                              bottom:
                                  16 + AppTheme.bottomBarContentInset(context),
                            ),
                            itemCount: sections.length,
                            itemBuilder: (context, i) =>
                                _section(context, sections[i], buckets),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  int get _activeFilterCount =>
      _active.length == _order.length ? 0 : _active.length;

  void _openFilters(Map<EventSeverity, List<TrafficEvent>> buckets) {
    final pending = {..._active};
    showFilterSheet(
      context: context,
      title: 'Filtri dogodkov',
      onReset: () => pending
        ..clear()
        ..addAll(_order),
      onApply: () => setState(() => _active
        ..clear()
        ..addAll(pending)),
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
                      '${EventVisuals.label(s)} (${buckets[s]!.length})',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  AdaptiveSwitch(
                    value: pending.contains(s),
                    activeColor: EventVisuals.color(s),
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
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    EventSeverity sev,
    Map<EventSeverity, List<TrafficEvent>> buckets,
  ) {
    final items = buckets[sev]!;
    return AdaptiveFormSection.insetGrouped(
      header: Text(
        '${EventVisuals.label(sev).toUpperCase()} (${items.length})',
        style: TextStyle(
          color: EventVisuals.color(sev),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
      children: [
        for (var j = 0; j < items.length; j++) ...[
          _EventRow(event: items[j]),
          if (!PlatformInfo.isIOS && j < items.length - 1)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 56,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
        ],
      ],
    );
  }

  Widget _empty(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, EventsProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(provider.error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            AdaptiveButton.child(
              onPressed: provider.refresh,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Poskusi znova'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final TrafficEvent event;

  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = EventVisuals.color(event.severity);
    final subtitle = event.description.isNotEmpty
        ? event.description
        : event.cause;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showEventSheet(context, event),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(EventVisuals.causeIcon(event), color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (event.road.isNotEmpty) ...[
                        Text(
                          event.road,
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
                          event.title.isEmpty ? event.cause : event.title,
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
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
