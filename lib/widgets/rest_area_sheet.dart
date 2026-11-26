import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/rest_area.dart';
import 'sheet_snack.dart';
import 'app_sheet.dart';

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
  showAppSheet<void>(context, builder: (_) => _RestAreaSheet(area: area));
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
    bool opened;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      opened = false;
    }
    if (!opened) {
      if (context.mounted) {
        showSheetSnack(
          context,
          message: 'Navigacije ni mogoče odpreti',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = restAreaColor(area);

    final hours = _normaliseHours(area.workingHours);
    final capacity = <Widget>[
      if (area.carSpaces > 0)
        _capChip(
          cs,
          Icons.directions_car,
          '${area.carSpaces} ${_spaces(area.carSpaces)} za avte',
        ),
      if (area.truckSpaces > 0)
        _capChip(
          cs,
          Icons.local_shipping,
          '${area.truckSpaces} ${_spaces(area.truckSpaces)} za tovornjake',
        ),
      if (hours.isNotEmpty) _capChip(cs, Icons.schedule, hours),
    ];

    return AppSheet(
      title: area.title.isEmpty ? 'Počivališče' : area.title,
      titleMaxLines: 2,
      leading: Icon(Icons.local_parking, color: cs.primary),
      actions: [
        IconButton(
          tooltip: 'Navigacija',
          icon: const Icon(Icons.directions),
          onPressed: () => _openDirections(context),
        ),
      ],
      children: [
        if (area.locationDescription.isNotEmpty) ...[
          Text(
            area.locationDescription,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.3),
          ),
          const SizedBox(height: 16),
        ],
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
        // Static capacity; counts the feed reports as 0 mean "no data" and
        // are hidden. Wrap: long working hours or large text would overflow
        // a Row.
        if (capacity.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: capacity),
        if (area.amenities.isNotEmpty) ...[
          if (capacity.isNotEmpty || area.hasLiveAvailability)
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
          // Plain icon + label pairs: informational, not tappable chips.
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              for (final a in _amenityIcons.entries)
                if (area.amenities.contains(a.key))
                  MergeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(a.value.$1, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(a.value.$2, style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }

  /// Slovenian dual/plural of "mesto" for [n].
  static String _spaces(int n) {
    final r = n % 100;
    if (r == 1) return 'mesto';
    if (r == 2) return 'mesti';
    if (r == 3 || r == 4) return 'mesta';
    return 'mest';
  }

  /// "0 - 24h" → "0–24 h": en dash without spaces between numbers and a
  /// space before the hour unit.
  static String _normaliseHours(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAllMapped(
      RegExp(r'(\d)\s*[-–—]\s*(\d)'),
      (m) => '${m[1]}–${m[2]}',
    );
    s = s.replaceAllMapped(RegExp(r'(\d)\s*h\b'), (m) => '${m[1]} h');
    return s.replaceAll(RegExp(r'\s+'), ' ');
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
          Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
