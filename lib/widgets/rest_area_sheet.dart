import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/rest_area.dart';

const _amenityIcons = <String, (IconData, String)>{
  'fuel': (Icons.local_gas_station, 'Bencin'),
  'store': (Icons.shopping_cart, 'Trgovina'),
  'food': (Icons.restaurant, 'Hrana'),
  'wc': (Icons.wc, 'WC'),
  'rv': (Icons.rv_hookup, 'Avtodomi'),
  'atm': (Icons.local_atm, 'Bankomat'),
  'shower': (Icons.shower, 'Tuš'),
  'wifi': (Icons.wifi, 'WiFi'),
  'playground': (Icons.child_care, 'Igrala'),
  'rest': (Icons.weekend, 'Počitek'),
};

/// Marker/accent colour derived from how full the lot is, not the opaque
/// `ColorAvailability` string from the feed. Grey when there is no live data.
Color restAreaColor(RestArea area) {
  if (!area.hasLiveAvailability) return const Color(0xFF6B7B8C); // no data
  final free = area.available / area.total;
  if (free <= 0.05) return const Color(0xFFE53935); // basically full
  if (free < 0.20) return const Color(0xFFFB8C00); // filling up
  return const Color(0xFF66BB6A); // plenty of room
}

void showRestAreaSheet(BuildContext context, RestArea area) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RestAreaSheet(area: area),
  );
}

class _RestAreaSheet extends StatelessWidget {
  final RestArea area;

  const _RestAreaSheet({required this.area});

  Future<void> _openDirections(BuildContext context) async {
    final lat = area.position.latitude;
    final lon = area.position.longitude;
    final label = Uri.encodeComponent(
      area.title.isEmpty ? 'Počivališče' : area.title,
    );
    final uri = PlatformInfo.isIOS
        ? Uri.parse('https://maps.apple.com/?daddr=$lat,$lon&q=$label')
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
          );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        AdaptiveSnackBar.show(
          context,
          message: 'Navigacije ni mogoče odpreti',
          type: AdaptiveSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = restAreaColor(area);

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
                Icon(Icons.local_parking, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    area.title.isEmpty ? 'Počivališče' : area.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Navigacija',
                  icon: const Icon(Icons.directions),
                  onPressed: () => _openDirections(context),
                ),
              ],
            ),
            if (area.locationDescription.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                area.locationDescription,
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
              ),
            ],
            const SizedBox(height: 16),
            // Live availability.
            if (area.hasLiveAvailability) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_parking, color: color, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${area.available} / ${area.total} prostih',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (area.availabilityText.isNotEmpty)
                            Text(
                              area.availabilityText,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Static capacity.
            Row(
              children: [
                _capChip(cs, Icons.directions_car, '${area.carSpaces} avto'),
                const SizedBox(width: 8),
                _capChip(
                  cs,
                  Icons.local_shipping,
                  '${area.truckSpaces} tovornih',
                ),
                if (area.workingHours.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _capChip(cs, Icons.schedule, area.workingHours),
                ],
              ],
            ),
            if (area.amenities.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'PONUDBA',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in _amenityIcons.entries)
                    if (area.amenities.contains(a.key))
                      Chip(
                        avatar: Icon(a.value.$1, size: 18, color: cs.primary),
                        label: Text(a.value.$2),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _capChip(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
