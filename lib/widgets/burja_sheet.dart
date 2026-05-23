import 'package:flutter/material.dart';
import '../models/burja_station.dart';

const _burjaColors = <Color>[
  Color(0xFF66BB6A), // 0 calm
  Color(0xFFFDD835), // 1 moderate
  Color(0xFFFB8C00), // 2 strong
  Color(0xFFE53935), // 3 severe
];

const _burjaLabels = <String>[
  'Mirno',
  'Zmeren veter',
  'Močan veter',
  'Sunki nevarni',
];

const _burjaAdvice = <String>[
  'Razmere so umirjene.',
  'Pozor pri vleki prikolic in lahkih vozil.',
  'Omejitve za tovornjake in počitniške prikolice so verjetne.',
  'Možne zapore za izpostavljena vozila. Skrajna previdnost!',
];

Color burjaColor(int level) => _burjaColors[level.clamp(0, 3)];

void showBurjaSheet(BuildContext context, BurjaStation station) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BurjaSheet(station: station),
  );
}

class _BurjaSheet extends StatelessWidget {
  final BurjaStation station;

  const _BurjaSheet({required this.station});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = burjaColor(station.level);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.air, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    station.title.isEmpty ? 'Burja' : station.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (station.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                station.description,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _burjaLabels[station.level],
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _burjaAdvice[station.level],
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    cs,
                    Icons.air,
                    'Veter',
                    '${station.wind.round()} km/h',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metric(
                    cs,
                    Icons.storm,
                    'Sunki',
                    '${station.gust.round()} km/h',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(ColorScheme cs, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
