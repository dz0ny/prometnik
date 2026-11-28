import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/routes_provider.dart';
import '../routing/route_warnings.dart';
import '../routing/saved_route.dart';
import '../screens/route_detail_screen.dart';
import '../screens/route_editor_screen.dart';

/// "Moje poti" in the Bližina tab: the user's saved routes, each with its
/// current warnings, and a button for a new one.
class MyRoutesSection extends ConsumerWidget {
  const MyRoutesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final routes = ref.watch(savedRoutesProvider);
    final warnings = ref.watch(routeWarningsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'MOJE POTI',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => showRouteEditor(context),
                icon: const Icon(Icons.add_road, size: 18),
                label: const Text('Nova pot'),
              ),
            ],
          ),
        ),
        if (routes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Shranite pot, ki jo pogosto vozite, in Prometnik vas opozori '
              'na zastoje, zapore, poledico, burjo in zamude na njej.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          )
        else
          for (final r in routes)
            _RouteCard(route: r, warnings: warnings[r.id] ?? const []),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  final SavedRoute route;
  final List<RouteWarning> warnings;

  const _RouteCard({required this.route, required this.warnings});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final worst = warnings.isEmpty ? 0 : warnings.first.severity;
    final color = severityColor(cs, worst);
    final next = route.nextDeparture(DateTime.now());
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: .55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: .5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showRouteDetail(context, route.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                worst == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${route.places.first.name} → ${route.places.last.name}',
                        '${(route.meters / 1000).round()} km',
                        if (next != null) 'odhod ${departureLabel(next)}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      warnings.isEmpty
                          ? 'Brez opozoril'
                          : warnings.length == 1
                          ? warnings.first.title
                          : '${warnings.first.title} in še ${warnings.length - 1}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: worst == 0 ? cs.onSurfaceVariant : color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour for a warning severity (0 = all clear).
Color severityColor(ColorScheme cs, int severity) => switch (severity) {
  0 => const Color(0xFF2E9E5B),
  1 => const Color(0xFFE0A100),
  2 => const Color(0xFFEF6C00),
  _ => cs.error,
};

/// "pon 07:30", or "danes 07:30" / "jutri 07:30".
String departureLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  const names = ['pon', 'tor', 'sre', 'čet', 'pet', 'sob', 'ned'];
  final d = diff == 0 ? 'danes' : (diff == 1 ? 'jutri' : names[at.weekday - 1]);
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  return '$d $hh:$mm';
}
